#!/usr/bin/env python3
"""claudius container-side clipboard shim.

Invoked as (via symlink): xclip, xsel, wl-copy, wl-paste, pbcopy, pbpaste.
Talks to the host bridge via a Unix socket mounted into the container.

Mode inference:
    argv[0] == wl-paste | pbpaste            → read
    argv[0] == wl-copy  | pbcopy             → write
    argv[0] == xclip/xsel with -o/-out/--output → read
    anything else                            → write (stdin → clipboard)
"""

from __future__ import annotations

import os
import pathlib
import socket
import sys


DEFAULT_SOCK = "/run/claudius/clipboard.sock"


def infer_mode(name: str, args: list[str]) -> str:
    if name in ("wl-paste", "pbpaste"):
        return "r"
    if name in ("wl-copy", "pbcopy"):
        return "w"
    return "r" if any(a in ("-o", "-out", "--output") for a in args) else "w"


def main() -> int:
    sock_path = os.environ.get("CLAUDIUS_CLIPBOARD_SOCK", DEFAULT_SOCK)
    name = pathlib.Path(sys.argv[0]).name

    if not pathlib.Path(sock_path).is_socket():
        print(f"{name}: clipboard bridge not available at {sock_path}", file=sys.stderr)
        return 1

    mode = infer_mode(name, sys.argv[1:])

    with socket.socket(socket.AF_UNIX) as s:
        s.connect(sock_path)
        s.sendall(mode.encode())
        if mode == "r":
            s.shutdown(socket.SHUT_WR)
            while chunk := s.recv(65536):
                sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
        else:
            data = sys.stdin.buffer.read()
            s.sendall(data)
            s.shutdown(socket.SHUT_WR)
    return 0


if __name__ == "__main__":
    sys.exit(main())
