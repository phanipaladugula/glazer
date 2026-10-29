#!/usr/bin/env python3
"""Runs a command in a pseudo-terminal of a given size and checks its terminal drawing.

Used by Tests/Install/run.sh to test install.sh's animated output the way a user sees it.

Usage: pty_run.py COLUMNS ROWS [--interrupt-after SECONDS] -- COMMAND...

Prints a one-line JSON summary: exit code, frames drawn, the widest line drawn, whether
the cursor was hidden and shown again, and whether every byte was valid UTF-8.
"""

import fcntl
import json
import os
import pty
import re
import struct
import sys
import termios
import time


def main() -> int:
    args = sys.argv[1:]
    separator = args.index("--")
    options, command = args[:separator], args[separator + 1 :]
    columns, rows = int(options[0]), int(options[1])
    interrupt_after = None
    if "--interrupt-after" in options:
        interrupt_after = float(options[options.index("--interrupt-after") + 1])

    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.execvp(command[0], command)

    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
    output = b""
    start = time.time()
    interrupted = False
    while True:
        if interrupt_after is not None and not interrupted and time.time() - start > interrupt_after:
            os.write(fd, b"\x03")  # Ctrl-C, as the terminal sends it.
            interrupted = True
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            break
        if not chunk:
            break
        output += chunk
    _, status = os.waitpid(pid, 0)

    try:
        text = output.decode("utf-8")
        valid_utf8 = True
    except UnicodeDecodeError:
        text = output.decode("utf-8", "replace")
        valid_utf8 = False

    # A frame starts by moving the cursor up over the previous one.
    frames = re.split(r"\x1b\[\d+A", text)
    visible = lambda line: re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\r", "", line)
    widest = max((len(visible(line)) for frame in frames[:-1] for line in frame.split("\n")), default=0)

    print(json.dumps({
        "exit": os.waitstatus_to_exitcode(status),
        "frames": len(frames) - 1,
        "widest": widest,
        "columns": columns,
        "cursor_hidden": text.count("\x1b[?25l"),
        "cursor_shown": text.count("\x1b[?25h"),
        "utf8": valid_utf8,
        "cancelled_message": "Nothing was installed" in text,
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
