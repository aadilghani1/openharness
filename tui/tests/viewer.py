#!/usr/bin/env python3
"""Exercise hn's public viewer commands against a private mock and a recording browser opener."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

root = Path(__file__).resolve().parents[1]
source = Path(os.environ.get('HN_VIEWER_TEST_BINARY', root / 'target/release/harness-tui')).resolve()
port = int(os.environ.get('HN_VIEWER_TEST_PORT', '19671'))
if not 19000 <= port <= 19999 or port in (18473, 18907):
    raise SystemExit('Viewer tests require an isolated port in 19000–19999')
prefix = f'hn-viewer-test-{os.getpid()}'
with tempfile.TemporaryDirectory(prefix='hnv-', dir='/tmp') as tmp:
    home = Path(tmp)
    binary = home / 'hn'
    shutil.copy2(source, binary)
    bin_dir = home / 'bin'
    bin_dir.mkdir()
    log = home / 'browser.jsonl'
    for name in ('open', 'xdg-open'):
        opener = bin_dir / name
        opener.write_text('#!' + sys.executable + '\nimport json,os,sys\nwith open(os.environ["HN_VIEWER_OPENER_LOG"],"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\nsys.exit(int(os.environ.get("HN_VIEWER_OPENER_EXIT","0")))\n')
        opener.chmod(0o700)
    env = {k: v for k, v in os.environ.items() if k not in ('TMUX', 'TMUX_PANE', 'HN_SOCKET', 'SSH_TTY', 'SSH_CONNECTION', 'SSH_CLIENT')}
    env.update(HOME=tmp, PORT=str(port), HN_SOCKET_NAME=prefix, HN_TMPDIR=tmp,
               HARNESS_TUI_DESK='off', HARNESS_TUI_NOTIFY='off', HN_DESKTOP='off',
               HN_VIEWER_OPENER_LOG=str(log), PATH=str(bin_dir) + os.pathsep + env.get('PATH', ''),
               MOCK_VIEWER='1', MOCK_WEB_URL='https://harness.example', DISPLAY=':hn-test')
    def hn(*args, extra=None, ok=True):
        result = subprocess.run([str(binary), '-L', prefix, '--port', str(port), *args],
                                env={**env, **(extra or {})}, text=True, capture_output=True, timeout=20)
        if ok and result.returncode:
            raise AssertionError(f'{args}: {result.returncode}: {result.stderr}')
        return result
    def opened():
        return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
    def web_link(result, agent):
        uri = urllib.parse.urlparse(result.stdout.strip())
        assert uri.scheme == 'https' and uri.netloc == 'harness.example', result.stdout
        assert uri.path == '/', result.stdout
        assert urllib.parse.parse_qs(uri.query) == {
            'viewer': ['1'], 'machine': ['mock000000000000000000000000000' + ('2' if agent.startswith('remote') else '1')],
            'agent': [agent]}, result.stdout
    mock = subprocess.Popen(['node', str(root / 'tests/mock-daemon.mjs'), str(port)], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        for _ in range(100):
            if mock.poll() is not None: raise AssertionError(mock.stderr.read().decode())
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/status', timeout=.2): break
            except OSError: time.sleep(.05)
        else: raise AssertionError('Mock did not start')
        local = f'http://127.0.0.1:{port}/test-viewer?file=model.glb'
        assert hn('view', '-p', '-t', 'Mock Blender').stdout.strip() == local
        assert not opened()
        hn('view', '-t', 'Mock Blender')
        assert opened() == [[local]], opened()
        web_link(hn('view', '-t', 'Mock Blender', extra={'SSH_CONNECTION': 'fixture ssh'}), 'mock-blender')
        assert opened() == [[local]], 'SSH must never launch a server-side browser'
        web_link(hn('view', '-p', '-t', 'Remote Blender'), 'remote-blender')
        web_link(hn('view', '-pw', '-t', 'Mock Blender'), 'mock-blender')
        assert hn('view', '-p', '-t', 'Mock Claude', ok=False).returncode == 1
        assert hn('view', '-p', '-t', 'Missing', ok=False).returncode == 1
        assert hn('view', '--unknown', ok=False).returncode == 2
        assert hn('view', '-t', ok=False).returncode == 2
        assert hn('view', '-t', 'Mock Blender', extra={'HN_VIEWER_OPENER_EXIT': '1'}).stdout.strip() == local
        print('PASS: standalone viewer, exact opener argv, SSH, remote target, print and browser-failure fallback')
        hn('new-session', '-d', '-s', 'viewer-test')
        hn('open-harness', '-s', 'Mock Blender')
        assert hn('view', '-p').stdout.strip() == local
        count = len(opened())
        web_link(hn('view', extra={'SSH_TTY': '/dev/fixture'}), 'mock-blender')
        assert len(opened()) == count
        assert hn('view', '-p', '-t', 'Mock Claude', ok=False).returncode == 1
        assert 'open-viewer' in hn('list-commands').stdout
        print('PASS: active pane through hn IPC; caller SSH environment controls the handoff')
    finally:
        hn('kill-server', ok=False)
        mock.terminate()
        try: mock.wait(timeout=5)
        except subprocess.TimeoutExpired: mock.kill(); mock.wait(timeout=5)
