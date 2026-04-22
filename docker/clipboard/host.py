#!/usr/bin/env python3
"""claudius host-side clipboard bridge.

Listens on a Unix socket and brokers clipboard read/write for a container,
avoiding the need to mount /tmp/.X11-unix (which would expose the entire
X screen to the sandbox).

Protocol (per connection, binary):
    Client opens the socket, sends one of:
        b'r'        → server responds with current clipboard bytes, then closes
        b'w<bytes>' → server writes <bytes> to the clipboard (EOF terminates payload)

Args:
    socket_path: path at which to create the listening Unix socket (0600).
"""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
import sys
import threading


def detect_tools() -> tuple[list[str], list[str]]:
    """Pick reader/writer commands based on what's available on the host."""
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-paste") and shutil.which("wl-copy"):
        return (["wl-paste", "-n"], ["wl-copy"])
    if os.environ.get("DISPLAY") and shutil.which("xclip"):
        return (["xclip", "-selection", "clipboard", "-o"],
                ["xclip", "-selection", "clipboard", "-i"])
    print("claudius-clipboard-host: no clipboard tool available "
          "(need xclip+DISPLAY or wl-clipboard+WAYLAND_DISPLAY)",
          file=sys.stderr)
    sys.exit(1)


def _handle(conn: socket.socket, read_cmd: list[str], write_cmd: list[str]) -> None:
    with conn:
        mode = conn.recv(1)
        if mode == b"r":
            try:
                out = subprocess.check_output(read_cmd)
            except subprocess.CalledProcessError:
                out = b""
            conn.sendall(out)
        elif mode == b"w":
            payload = bytearray()
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                payload.extend(chunk)
            subprocess.run(write_cmd, input=bytes(payload), check=False)


def main(sock_path: str) -> None:
    read_cmd, write_cmd = detect_tools()

    if os.path.exists(sock_path):
        os.unlink(sock_path)

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(sock_path)
    os.chmod(sock_path, 0o600)
    srv.listen(8)

    while True:
        conn, _ = srv.accept()
        threading.Thread(
            target=_handle, args=(conn, read_cmd, write_cmd), daemon=True
        ).start()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: clipboard-host.py <socket-path>", file=sys.stderr)
        sys.exit(2)
    try:
        main(sys.argv[1])
    except KeyboardInterrupt:
        pass
