#!/usr/bin/env python3
"""Hold an interactive SSH client long enough to inspect the server tmux client."""

import os
import pty
import subprocess
import sys
import time

master, slave = pty.openpty()
process = subprocess.Popen(sys.argv[1:], stdin=slave, stdout=slave, stderr=slave)
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
