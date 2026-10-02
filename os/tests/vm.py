#!/usr/bin/env python3
"""Boot and install the actual ISO in a disposable QEMU machine.

Uses a private qcow2 disk with a known serial. Never passes a host block device
to QEMU. Screenshots, serial logs, timings and checks survive every failure.
"""
from __future__ import annotations
import argparse
import base64
import json
import os
from pathlib import Path
import re
import select
import shlex
import shutil
import socket
import subprocess
import time
import uuid


class VM:
    def __init__(self, folder, iso, firmware, memory):
        self.folder, self.iso, self.firmware, self.memory = folder, iso, firmware, memory
        self.process = None
        self.serial = None
        self.qmp = None
        self.qmp_file = None
        self.log = (folder / 'serial.log').open('ab', buffering=0)
        self.stderr = (folder / 'qemu.log').open('ab', buffering=0)
        self.disk = folder / 'target.qcow2'
        subprocess.run(['qemu-img', 'create', '-f', 'qcow2', str(self.disk), '24G'], check=True)
        if firmware == 'uefi':
            self.code = Path('/usr/share/OVMF/OVMF_CODE_4M.fd')
            self.vars = folder / 'OVMF_VARS.fd'
            shutil.copyfile('/usr/share/OVMF/OVMF_VARS_4M.fd', self.vars)

    def start(self, live):
        for name in ['serial.sock', 'qmp.sock']:
            (self.folder / name).unlink(missing_ok=True)
        self.started = time.monotonic()
        acceleration = 'kvm' if os.access('/dev/kvm', os.R_OK | os.W_OK) else 'tcg'
        args = ['qemu-system-x86_64', '-accel', acceleration, '-m', str(self.memory), '-smp', '2',
                '-cpu', 'host' if acceleration == 'kvm' else 'max', '-device', 'virtio-vga',
                '-display', 'none', '-no-reboot',
                '-drive', f'file={self.disk},format=qcow2,if=virtio,serial=HN_OS_TEST',
                '-device', 'virtio-net-pci,netdev=net', '-netdev', 'user,id=net',
                '-serial', f'unix:{self.folder / "serial.sock"},server=on,wait=off',
                '-qmp', f'unix:{self.folder / "qmp.sock"},server=on,wait=off']
        if live:
            args += ['-cdrom', str(self.iso), '-boot', 'd']
        else:
            args += ['-boot', 'c']
        if self.firmware == 'uefi':
            args += ['-drive', f'if=pflash,format=raw,readonly=on,file={self.code}',
                     '-drive', f'if=pflash,format=raw,file={self.vars}']
        self.process = subprocess.Popen(args, stdout=self.stderr, stderr=self.stderr)
        self.serial = self.connect('serial.sock')
        self.qmp = self.connect('qmp.sock')
        self.qmp.settimeout(10)
        self.qmp_file = self.qmp.makefile('rb')
        json.loads(self.qmp_file.readline())
        self.monitor('qmp_capabilities')

    def connect(self, name):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError('QEMU exited before opening its control sockets.')
            sock = socket.socket(socket.AF_UNIX)
            try:
                sock.connect(str(self.folder / name))
                return sock
            except (FileNotFoundError, ConnectionRefusedError):
                sock.close()
                time.sleep(0.1)
        raise TimeoutError(f'QEMU did not expose {name}')

    def monitor(self, name, **arguments):
        identity = uuid.uuid4().hex
        self.qmp.sendall((json.dumps({'execute': name, 'arguments': arguments, 'id': identity}) + '\n').encode())
        while True:
            result = json.loads(self.qmp_file.readline())
            if result.get('id') == identity:
                if 'error' in result:
                    raise RuntimeError(result['error'])
                return result.get('return')

    def wait(self, pattern, timeout=180):
        deadline = time.monotonic() + timeout
        output = b''
        regex = re.compile(pattern.encode(), re.S)
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError(f'QEMU exited while waiting for {pattern!r}')
            if select.select([self.serial], [], [], min(1, max(0, deadline - time.monotonic())))[0]:
                chunk = self.serial.recv(65536)
                if not chunk:
                    raise RuntimeError('Guest serial console disconnected.')
                self.log.write(chunk)
                output += chunk
                if regex.search(output):
                    return output.decode(errors='replace')
        raise TimeoutError(f'Guest did not produce {pattern!r}; see serial.log')

    def send(self, text):
        self.serial.sendall(text.encode())

    def command(self, command, timeout=90, check=True):
        marker = 'HN_RESULT_' + uuid.uuid4().hex
        self.send(command + f"; hn_status=$?; printf '\\n{marker}:%s\\n' \"$hn_status\"\n")
        output = self.wait(r'\r?\n' + marker + r':\d+\r?\n', timeout)
        match = re.search(r'\r?\n' + marker + r':(\d+)\r?\n', output)
        status = int(match.group(1))
        if check and status:
            raise RuntimeError(f'Guest command failed ({status}): {command}\n{output[-2000:]}')
        return output[:match.start()], status

    def screenshot(self, name):
        ppm = self.folder / (name + '.ppm')
        self.monitor('screendump', filename=str(ppm))
        from PIL import Image
        Image.open(ppm).save(self.folder / (name + '.png'))
        ppm.unlink()

    def keys(self, *keys):
        self.monitor('send-key', keys=[{'type': 'qcode', 'data': key} for key in keys], **{'hold-time': 100})

    def stop(self):
        if self.process and self.process.poll() is None:
            try:
                self.monitor('quit')
            except (OSError, ValueError, RuntimeError):
                self.process.terminate()
            try:
                self.process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        for handle in [self.serial, self.qmp_file, self.qmp]:
            if handle:
                handle.close()
        self.serial = self.qmp_file = self.qmp = None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iso', required=True, type=Path)
    parser.add_argument('--firmware', choices=['bios', 'uefi'], default='bios')
    parser.add_argument('--encrypt', action='store_true')
    parser.add_argument('--memory', type=int, default=2048)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    folder = (args.output or Path('os/test-results') / (args.firmware + ('-encrypted' if args.encrypt else '-plain'))).resolve()
    folder.mkdir(parents=True, exist_ok=False)
    result = {'firmware': args.firmware, 'encrypted': args.encrypt, 'memory_mib': args.memory,
              'started_at_unix': time.time(), 'checks': [], 'status': 'running'}
    vm = VM(folder, args.iso.resolve(), args.firmware, args.memory)
    user = lambda cmd: 'runuser -u programmer -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus ' + cmd
    try:
        vm.start(live=True)
        vm.wait(r'root@[^\r\n]*[#] ')
        vm.command('stty -echo')
        vm.command('foot --check-config --config=/usr/share/harness-os/foot.ini')
        vm.command(user("sh -c 'for n in $(seq 1 90); do systemctl --user is-active --quiet hn-screen && pgrep -u 1000 -x harness-tui >/dev/null && exit 0; sleep 1; done; systemctl --user --no-pager status hn-screen harness-daemon; exit 1'"), timeout=110)
        result['live_hn_ready_seconds'] = round(time.monotonic() - vm.started, 3)
        vm.command('! pgrep -x chromium')
        result['checks'].append('Live hn ready; browser absent at boot')
        vm.screenshot('01-live-hn')
        output, _ = vm.command(user('hn-os measure'))
        (folder / 'live-measurement.txt').write_text(output)
        vm.keys('meta_l', 'b')
        vm.command("for n in $(seq 1 45); do pgrep -x chromium >/dev/null && break; sleep 1; done; pgrep -x chromium", timeout=60)
        time.sleep(3)
        vm.screenshot('02-browser')
        vm.keys('meta_l', 'b')
        time.sleep(1)
        vm.screenshot('03-return-to-hn')
        result['checks'].append('Browser starts only on shortcut; toggle screenshots recorded')
        # A long-lived terminal process proves a screen restart does not kill the work.
        survivor = "echo $$ > /tmp/hn-survivor.pid; exec sleep 1800"
        vm.command(user("hn new-window -n persistence " + shlex.quote(survivor)))
        vm.command('test -s /tmp/hn-survivor.pid')
        vm.command(user('systemctl --user restart hn-screen'))
        vm.command('sleep 3; kill -0 "$(cat /tmp/hn-survivor.pid)"')
        result['checks'].append('Terminal process survives screen restart')
        config = dict(disk='/dev/vda', expected_serial='HN_OS_TEST', confirm_erase='/dev/vda',
                      username='programmer', hostname='hn-test', password='test-password-123',
                      encrypt=args.encrypt, serial_console=True)
        encoded = base64.b64encode(json.dumps(config).encode()).decode()
        vm.command(f"printf %s {shlex.quote(encoded)} | base64 -d > /run/hn-install-test.json; chmod 600 /run/hn-install-test.json")
        vm.command('hn-os install --config /run/hn-install-test.json --yes-erase-disk', timeout=900)
        result['checks'].append('Offline installer completed on disposable disk')
        vm.command('sync')
        vm.stop()
        vm.start(live=False)
        if args.encrypt:
            vm.wait(r'(?:passphrase|Passphrase|Password)[^\r\n]*:', timeout=180)
            vm.send(config['password'] + '\n')
        vm.wait(r'login:', timeout=180)
        vm.send('programmer\n')
        vm.wait(r'Password:')
        vm.send(config['password'] + '\n')
        vm.wait(r'\$ ')
        vm.command('stty -echo')
        # For plain installs, authenticate the graphical console by keyboard too.
        if not args.encrypt:
            # The root console shows login on tty1; serial authentication is separate.
            for word in ['programmer', config['password']]:
                for char in word:
                    vm.keys('minus' if char == '-' else char)
                vm.keys('ret')
                time.sleep(2)
        vm.command('for n in $(seq 1 90); do systemctl --user is-active --quiet hn-screen && exit 0; sleep 1; done; exit 1', timeout=110)
        result['installed_hn_ready_seconds_including_test_login'] = round(time.monotonic() - vm.started, 3)
        vm.command('test ! -e /etc/sudoers.d/10-live && ! sudo -n true')
        vm.command('! pgrep -x chromium')
        vm.command('findmnt -n -o FSTYPE / | grep -qx btrfs')
        vm.command('test -s /boot/grub/grub.cfg')
        output, _ = vm.command('cat /var/lib/harness-os/install.json; hn-os measure')
        (folder / 'installed-measurement.txt').write_text(output)
        vm.screenshot('04-installed-hn')
        result['checks'].append('Installed disk boots to hn with intended account permissions and no browser')
        result['status'] = 'passed'
    except Exception as error:
        result['status'] = 'failed'
        result['error'] = str(error)
        try:
            vm.screenshot('failure')
        except Exception:
            pass
        raise
    finally:
        vm.stop()
        result['finished_at_unix'] = time.time()
        (folder / 'receipt.json').write_text(json.dumps(result, indent=2) + '\n')
        # Large disposable disks are never uploaded with the small evidence set.
        vm.disk.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
