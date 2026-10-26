#!/usr/bin/env python3
"""Hold an interactive SSH client long enough to inspect the server tmux client."""

import os
import fcntl
import pty
import struct
import subprocess
import sys
import termios
import time

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
environment = os.environ.copy()
environment["TERM"] = "xterm-256color"
process = subprocess.Popen(
    sys.argv[1:], stdin=slave, stdout=slave, stderr=slave, env=environment
)
os.close(slave)
try:
    time.sleep(6)
    if process.poll() is not None:
        raise SystemExit(f"SSH client exited early: {process.returncode}")
finally:
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    os.close(master)
