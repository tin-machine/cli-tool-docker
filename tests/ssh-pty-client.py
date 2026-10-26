#!/usr/bin/env python3
"""Exercise terminal input/output while the parent inspects the tmux client."""

import os
import fcntl
import pty
import select
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
    sys.argv[3:], stdin=slave, stdout=slave, stderr=slave, env=environment
)
os.close(slave)
output = bytearray()
try:
    started = time.monotonic()
    sent = False
    while time.monotonic() - started < 6:
        if process.poll() is not None:
            raise SystemExit(f"SSH client exited early: {process.returncode}\n{output.decode(errors='replace')}")
        if not sent and time.monotonic() - started >= 1:
            os.write(master, (sys.argv[1] + "\r").encode())
            sent = True
        if select.select([master], [], [], 0.1)[0]:
            try:
                output.extend(os.read(master, 65536))
            except OSError:
                raise SystemExit(f"SSH terminal closed\n{output.decode(errors='replace')}")
    if sys.argv[2].encode() not in output:
        raise SystemExit(f"Expected terminal output was absent\n{output.decode(errors='replace')}")
finally:
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
    os.close(master)
