#!/usr/bin/env python3
"""Real-process checks: no installed app, server, TCC access, or network required."""
import os
import signal
import subprocess
import sys
import time
import unittest
import tempfile
from pathlib import Path

supervisor = os.path.abspath(sys.argv.pop(1))

def wait_child(path):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        if path.exists():
            content = path.read_text().strip()
            if content:
                return int(content)
        time.sleep(.02)
    raise AssertionError('Supervisor did not start its child')

def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False

class SupervisorTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.pid_file = Path(directory.name) / 'backend.pid'
        self.backend_command = ['/bin/sh', '-c', 'echo $$ > "$1"; exec /bin/sleep 30', 'backend', str(self.pid_file)]

    def test_forwards_termination_and_reaps_backend(self):
        process = subprocess.Popen([supervisor, *self.backend_command])
        backend = None
        try:
            backend = wait_child(self.pid_file)
            process.terminate()
            process.wait(timeout=4)
            self.assertFalse(alive(backend), 'Backend survived normal supervisor shutdown')
        finally:
            if process.poll() is None:
                process.kill(); process.wait()
            if backend and alive(backend):
                os.kill(backend, signal.SIGKILL)

    def test_parent_crash_stops_backend(self):
        launcher = 'import subprocess,sys,time; p=subprocess.Popen(sys.argv[1:]); print(p.pid,flush=True); time.sleep(30)'
        parent = subprocess.Popen([sys.executable, '-c', launcher, supervisor, *self.backend_command], stdout=subprocess.PIPE, text=True)
        backend = worker = None
        try:
            worker = int(parent.stdout.readline())
            backend = wait_child(self.pid_file)
            parent.kill(); parent.wait()
            deadline = time.monotonic() + 4
            while alive(backend) and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertFalse(alive(backend), 'Backend survived its owning app crash')
        finally:
            if parent.poll() is None:
                parent.kill(); parent.wait()
            parent.stdout.close()
            if worker and alive(worker):
                os.kill(worker, signal.SIGKILL)
            if backend and alive(backend):
                os.kill(backend, signal.SIGKILL)

if __name__ == '__main__':
    unittest.main()
