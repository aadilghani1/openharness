#!/usr/bin/env python3
"""Pane presentation with real hn keys, mouse input, copy mode and tiny PTYs.

Uses only guarded reconnect-fixture ports 19783..19789 and disposable hn/tmux servers.
HN_PANE_UI_OUTPUT optionally keeps ANSI captures for rendering a visual review.
"""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PORT = int(os.environ.get('HN_PANE_UI_PORT', '19783'))
assert 19783 <= PORT <= 19789, 'refusing non-test pane UI port'
PREFIX = f'hn-pane-ui-{os.getpid()}'
BASE = Path(tempfile.mkdtemp(prefix='hnpu-', dir='/tmp')).resolve()
HN = BASE / 'hn'
shutil.copy2(os.environ.get('HN_PANE_UI_BINARY', ROOT / 'target/release/harness-tui'), HN)
TMUX = shutil.which('tmux')
assert TMUX
ENV = {k: os.environ[k] for k in ('PATH', 'LANG', 'LC_ALL', 'TZ') if k in os.environ}
ENV.update(HOME=str(BASE), HN_TMPDIR=str(BASE), HN_SOCKET_NAME=PREFIX, PORT=str(PORT),
           TERM='xterm-256color', COLORTERM='truecolor', SHELL='/bin/sh', HARNESS_TUI_DESK='sync',
           HARNESS_TUI_NOTIFY='off', HN_DESKTOP='off', MOCK_DEMO='1', MOCK_RECONNECT='1')
CONF = BASE / 'tmux.conf'
CONF.write_text('set -g automatic-rename off\nset -g status-right "#{fleet}  studio  20:41 "\n')
OUTPUT = Path(os.environ['HN_PANE_UI_OUTPUT']) if os.environ.get('HN_PANE_UI_OUTPUT') else None
if OUTPUT:
    OUTPUT.mkdir(parents=True, exist_ok=True)


def hn(*args, ok=True):
    assert 19783 <= PORT <= 19789 and PREFIX.startswith('hn-pane-ui-')
    p = subprocess.run([str(HN), '-L', PREFIX, '--port', str(PORT), '-f', str(CONF), *args], env=ENV,
                       cwd=BASE, text=True, capture_output=True, timeout=12)
    if ok:
        assert p.returncode == 0, (args, p.stdout, p.stderr)
    return p.stdout.strip()


def tmux(*args, ok=True):
    p = subprocess.run([TMUX, '-L', PREFIX + '-outer', *args], env=ENV, cwd=BASE,
                       text=True, capture_output=True, timeout=10)
    if ok:
        assert p.returncode == 0, (args, p.stderr)
    return p.stdout


def api():
    with urllib.request.urlopen(f'http://127.0.0.1:{PORT}/test/reconnect', timeout=2) as r:
        return json.load(r)['data']


def wait(fn, label, seconds=8):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if fn():
            return
        time.sleep(.05)
    raise AssertionError(label + '\n' + tmux('capture-pane', '-p', '-t', 'test', ok=False))


def value(fmt, target=None):
    return hn('display-message', '-p', *(['-t', target] if target else []), fmt)


def keys(*args):
    tmux('send-keys', '-t', 'test', *args)


def mouse(code, x, y, release=False):
    raw = f'\x1b[<{code};{x + 1};{y + 1}{"m" if release else "M"}'.encode()
    tmux('send-keys', '-H', '-t', 'test', *[f'{b:02x}' for b in raw])


def snapshot(name):
    if OUTPUT:
        (OUTPUT / (name + '.ansi')).write_text(tmux('capture-pane', '-p', '-e', '-t', 'test'))


mock = None
started = False
try:
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(('127.0.0.1', PORT))
    mock = subprocess.Popen(['node', str(ROOT / 'tests/mock-daemon.mjs'), str(PORT)], env=ENV,
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    for _ in range(100):
        assert mock.poll() is None, mock.stderr.read().decode() if mock.poll() is not None else ''
        try:
            api()
            break
        except OSError:
            time.sleep(.05)
    else:
        raise AssertionError('mock startup timeout')
    command = shlex.join(['env', '-u', 'TMUX', '-u', 'TMUX_PANE', '-u', 'HN_SOCKET',
                          *[f'{k}={v}' for k, v in ENV.items()], str(HN), '-L', PREFIX,
                          '--port', str(PORT), '-f', str(CONF)])
    tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'test', '-x', '150', '-y', '42', command)
    started = True
    wait(lambda: 'Fix flaky login test' in tmux('capture-pane', '-p', '-t', 'test'), 'demo panes')
    hn('select-layout', 'even-horizontal')
    panes = hn('list-panes', '-F', '#{pane_id}').splitlines()
    assert len(panes) == 3
    first, second, third = panes
    hn('select-pane', '-t', first)
    keys('C-b', 'Right')
    keys('C-b', 'Left')
    wait(lambda: value('#{pane_id}') == first, 'focus before visual capture')
    time.sleep(.2)
    snapshot('panes-columns')
    original = value('#{window_layout}')

    keys('C-b', 'Right')
    wait(lambda: value('#{pane_id}') == second, 'C-b Right with insets')
    keys('C-b', 'Right')
    wait(lambda: value('#{pane_id}') == third, 'second C-b Right')
    keys('C-b', 'Right')
    wait(lambda: value('#{pane_id}') == first, 'directional wrap')
    keys('C-b', 'z')
    wait(lambda: value('#{window_zoomed_flag}') == '1', 'zoom')
    keys('C-b', 'z')
    wait(lambda: value('#{window_zoomed_flag}') == '0', 'unzoom')
    assert value('#{window_layout}') == original
    print('PASS pane UI: directional keys, wrap, zoom preserve layout structure', flush=True)

    # Switching presentation must not change the serialized split structure.
    hn('set', '-g', '@hn-look', 'classic')
    assert value('#{window_layout}') == original
    border = int(value('#{pane_left}', first)) + int(value('#{pane_width}', first))
    snapshot('classic-columns')
    hn('set', '-g', '@hn-look', 'panes')
    assert value('#{window_layout}') == original
    x, y, w, h = map(int, value('#{pane_left} #{pane_top} #{pane_width} #{pane_height}', first).split())
    assert x > 0 and y > 1 and w > 0 and h > 0
    hn('send-keys', '-t', first, '-l', '\x1b[?1000h\x1b[?1006h')
    wait(lambda: value('#{mouse_sgr_flag}', first) == '1', 'program mouse mode')
    before = len(api()['inputs'])
    mouse(0, x + 3, y + 2)
    mouse(0, x + 3, y + 2, release=True)
    wait(lambda: {'\x1b[<0;4;3M', '\x1b[<0;4;3m'} <= {i['text'] for i in api()['inputs'][before:]}, 'mouse press and release start inside the inset content')
    print('PASS pane UI: same layout across appearances; mouse coordinates match PTY content', flush=True)

    # Titles and padding focus the pane without sending a click to its program.
    before = len(api()['inputs'])
    second_x = int(value('#{pane_left}', second))
    mouse(0, second_x, 1)
    mouse(0, second_x, 1, release=True)
    wait(lambda: value('#{pane_id}') == second, 'click the pane header')
    assert len(api()['inputs']) == before, api()['inputs'][before:]
    mouse(0, border, 10)
    mouse(32, border + 3, 10)
    mouse(0, border + 3, 10, release=True)
    wait(lambda: value('#{window_layout}') != original, 'drag the blank divider gutter')
    print('PASS pane UI: header focus and gutter dragging', flush=True)

    hn('select-pane', '-t', first)
    keys('C-b', '[')
    wait(lambda: value('#{pane_in_mode}') == '1', 'copy mode')
    hn('send-keys', '-X', 'history-top')
    hn('send-keys', '-X', 'start-of-line')
    hn('send-keys', '-X', 'begin-selection')
    for _ in range(5):
        hn('send-keys', '-X', 'cursor-right')
    hn('send-keys', '-X', 'copy-selection-and-cancel')
    wait(lambda: value('#{pane_in_mode}') == '0', 'leave copy mode')
    assert hn('show-buffer'), 'copy selection should retain terminal text'
    print('PASS pane UI: copy mode and selection', flush=True)

    # Layout targets and percentages operate on the split tree, not inset content.
    targets = ('top', 'bottom', 'left', 'right', 'top-left', 'top-right', 'bottom-left', 'bottom-right')
    layouts = ('even-horizontal', 'even-vertical', 'main-horizontal', 'main-vertical', 'tiled',
               'main-horizontal-mirrored', 'main-vertical-mirrored')
    for status in ('top', 'bottom', 'off'):
        hn('set', '-gw', 'pane-border-status', status)
        for layout in layouts:
            hn('set', '-g', '@hn-look', 'classic')
            hn('select-layout', layout)
            shape = value('#{window_layout}')
            expected = [value('#{pane_id}', '.' + t) for t in targets]
            hn('set', '-g', '@hn-look', 'panes')
            assert value('#{window_layout}') == shape, (status, layout)
            assert [value('#{pane_id}', '.' + t) for t in targets] == expected, (status, layout)
    hn('set', '-gw', 'pane-border-status', 'top')
    hn('select-layout', 'even-horizontal')
    shape = value('#{window_layout}')
    def structure(layout):
        return re.sub(r'(\d+x\d+,\d+,\d+),\d+', r'\1,P', layout[5:])
    for axis in ('-h', '-v'):
        resulting = []
        for look in ('classic', 'panes'):
            hn('set', '-g', '@hn-look', look)
            hn('select-layout', shape)
            new_pane = hn('split-window', axis, '-l', '35%', '-t', first, '-P', '-F', '#{pane_id}')
            assert new_pane.startswith('%'), new_pane
            resulting.append(structure(value('#{window_layout}')))
            hn('kill-pane', '-t', new_pane)
        assert resulting[0] == resulting[1], (axis, resulting)
    print('PASS pane UI: seven layouts, eight position targets, top/bottom/off titles, percentage splits', flush=True)

    hn('select-layout', 'even-vertical')
    time.sleep(.2)
    snapshot('panes-rows')
    hn('select-layout', 'main-vertical')
    time.sleep(.2)
    snapshot('panes-main')
    # Extra status rows above the panes must not leak into application mouse coordinates.
    hn('set', '-g', 'status', '2')
    hn('set', '-g', 'status-position', 'top')
    hn('select-pane', '-t', first)
    x, y = map(int, value('#{pane_left} #{pane_top}', first).split())
    # The mock emits a terminal reset on resize, so enable its program mouse mode again.
    hn('send-keys', '-t', first, '-l', '\x1b[?1000h\x1b[?1006h')
    wait(lambda: value('#{mouse_sgr_flag}', first) == '1', 'mouse mode after resized keyframe')
    before = len(api()['inputs'])
    mouse(0, x + 2, y + 2 + 1)
    mouse(0, x + 2, y + 2 + 1, release=True)
    wait(lambda: {'\x1b[<0;3;2M', '\x1b[<0;3;2m'} <= {i['text'] for i in api()['inputs'][before:]}, 'top status rows and program mouse coordinates')
    hn('set', '-g', 'status-position', 'bottom')
    hn('set', '-g', 'status', 'on')
    # OSC replies are metadata, not keystrokes. Surface defaults follow live light/dark changes.
    def background(hex_value):
        raw = f'\x1b]11;{hex_value}\x07'.encode()
        tmux('send-keys', '-H', '-t', 'test', *[f'{b:02x}' for b in raw])
    layout_before_theme = value('#{window_layout}')
    before = len(api()['inputs'])
    background('#f7f7f7')
    wait(lambda: hn('show', '-gwv', 'window-style') == 'fg=#1a1a1a,bg=#f7f7f7', 'light surface defaults')
    assert value('#{window_layout}') == layout_before_theme
    snapshot('panes-light')
    hn('set', '-gw', 'window-style', 'fg=red,bg=blue')
    background('#101010')
    wait(lambda: hn('show', '-gv', 'status-style').endswith('bg=#101010'), 'dark theme after a light theme')
    assert hn('show', '-gwv', 'window-style') == 'fg=red,bg=blue'
    assert len(api()['inputs']) == before, 'terminal query replies reached an application'
    hn('set', '-gwu', 'window-style')
    assert hn('show', '-gwv', 'window-style').startswith('fg=#f5f5f5,')
    print('PASS pane UI: live light/dark themes, reported defaults and custom style preservation', flush=True)

    hn('send-keys', '-t', first, '-l', '\x1b[H\x1b[31;44mHN_COLOR\x1b[0m')
    wait(lambda: 'HN_COLOR' in tmux('capture-pane', '-p', '-t', 'test'), 'explicit program colours')
    coloured = next(row for row in tmux('capture-pane', '-p', '-e', '-t', 'test').splitlines() if 'HN_COLOR' in row)
    assert '\x1b[31m' in coloured and '\x1b[44m' in coloured, repr(coloured)
    print('PASS pane UI: top status rows and explicit program foreground/background colours', flush=True)

    for width, height in [(80, 24), (24, 8), (6, 4), (1, 1), (150, 42)]:
        tmux('resize-window', '-t', 'test', '-x', str(width), '-y', str(height))
        wait(lambda: value('#{client_width} #{client_height}') == f'{width} {height}', 'terminal resize')
        assert value('#{window_panes}') == '3'
    print('PASS pane UI: compact and one-cell terminals, return to full size', flush=True)
finally:
    if started:
        if OUTPUT:
            snapshot('last-frame')
        hn('kill-server', ok=False)
        tmux('kill-server', ok=False)
    def clients():
        rows = subprocess.check_output(['ps', '-ax', '-o', 'pid=,command='], text=True).splitlines()
        return [int(parts[0]) for row in rows if len(parts := row.strip().split(None, 1)) == 2
                and parts[1].startswith(str(HN) + ' ') and f'-L {PREFIX} ' in parts[1]]
    for pid in clients():
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    try:
        deadline = time.monotonic() + 5
        while clients() and time.monotonic() < deadline:
            time.sleep(.05)
        assert not clients(), 'pane UI client did not exit'
    finally:
        if mock is not None:
            mock.terminate()
            mock.wait(timeout=5)
    shutil.rmtree(BASE)
