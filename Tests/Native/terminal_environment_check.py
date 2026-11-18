"""Exercise the real host PTY with a colour-disabled parent and resize signals."""
import ctypes
import json
import os
from pathlib import Path
import select
import shlex
import signal
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / '.build/terminal-power'
BUILD.mkdir(parents=True, exist_ok=True)
library = BUILD / 'pty-environment.dylib'
subprocess.run(['clang', '-dynamiclib', str(ROOT / 'Apps/macOS/Features/Terminal/TerminalPTY.c'),
                '-o', str(library)], check=True)
launcher = BUILD / 'TrunklineTerminalLauncher'
subprocess.run(['clang', str(ROOT / 'Services/TerminalLauncher/main.c'), '-o', str(launcher)], check=True)
pty = ctypes.CDLL(str(library))
pty.MPStartTerminal.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
pty.MPResizeTerminal.argtypes = [ctypes.c_int, ctypes.c_ushort, ctypes.c_ushort]
pty.MPSignalTerminalMembers.argtypes = [ctypes.c_int, ctypes.c_int]

with tempfile.TemporaryDirectory(prefix='trunkline-terminal-environment-') as directory:
    os.environ.update(ZDOTDIR=directory, NO_COLOR='1', FORCE_COLOR='0', CLICOLOR='0',
                      TERM='dumb', COLORTERM='', TERM_PROGRAM='ParentAutomation',
                      COLUMNS='17', LINES='11', CI='1')
    descriptor = ctypes.c_int(-1)
    pid = pty.MPStartTerminal(directory.encode(), str(launcher).encode(), ctypes.byref(descriptor))
    assert pid > 0, 'Could not create isolated terminal'
    fd = descriptor.value
    code = '''import os,json,signal,termios,tty,time
tty.setraw(0)
resized=False
def changed(*args):
 global resized
 resized=True
def report():
 s=os.get_terminal_size(0)
 print("__PTY_REPORT__"+json.dumps(dict(columns=s.columns,rows=s.lines,
   environment={k:os.environ.get(k) for k in
   ["TERM","COLORTERM","TERM_PROGRAM","NO_COLOR","FORCE_COLOR","CLICOLOR","CI","COLUMNS","LINES"]})),flush=True)
signal.signal(signal.SIGWINCH,changed)
report()
while True:
 if resized:
  resized=False
  report()
 time.sleep(0.01)
'''
    pending = b''

    def report():
        global pending
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if select.select([fd], [], [], 0.1)[0]:
                try:
                    pending += os.read(fd, 65536)
                except BlockingIOError:
                    continue
            while b'\n' in pending:
                line, pending = pending.split(b'\n', 1)
                if line.startswith(b'__PTY_REPORT__'):
                    return json.loads(line[len(b'__PTY_REPORT__'):])
        raise AssertionError('PTY did not report its size. Remaining output: '+repr(pending))

    try:
        # Launch a foreground job, not the shell itself. The PTY must notify the
        # job's process group, just as it does for an interactive CLI or editor.
        os.write(fd, ('/usr/bin/python3 -u -c ' + shlex.quote(code) + '\r').encode())
        initial = report()
        print('Initial PTY:', initial, 'foreground', os.tcgetpgrp(fd), 'shell group', os.getpgid(pid), flush=True)
        assert os.tcgetpgrp(fd) > 0 and os.tcgetpgrp(fd) != os.getpgid(pid), 'Foreground job did not acquire the terminal'
        for columns, rows in [(46, 24), (100, 8), (46, 38)]:
            assert pty.MPResizeTerminal(fd, columns, rows) == 0
            received = report()
            print('Resize:', received['columns'], received['rows'], flush=True)
            assert (received['columns'], received['rows']) == (columns, rows), received
        env = initial['environment']
        assert env['TERM'] == 'xterm-256color' and env['COLORTERM'] == 'truecolor', env
        for key in ['NO_COLOR', 'FORCE_COLOR', 'CLICOLOR', 'CI']:
            assert env[key] is None, f'{key} leaked into the terminal: {env[key]}'
        assert env['TERM_PROGRAM'] == 'Trunkline', env
        assert env['COLUMNS'] != '17' and env['LINES'] != '11', env
        print('PASS: independent colour environment and real SIGWINCH resizes in both directions')
    finally:
        pty.MPSignalTerminalMembers(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        os.close(fd)
