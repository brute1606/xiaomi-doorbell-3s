#!/usr/bin/env python3
"""Minimal control-channel hub for the doorbell.

The device connects out to the hub, so no inbound ports are needed on it:

  port 2231  command channel: if the command file exists, it is sent to the
             device and removed;
  port 2232  output channel: everything the device uploads is appended to the
             output file.

usage:
  hub.py [--cmdq PATH] [--out PATH] [--cmd-port 2231] [--out-port 2232]

Send a command by writing a file:
  printf 'echo hello\n' > /tmp/doorbell-cmdq
Long commands (OTA) must start with a first line containing "#LONG".
"""
import argparse
import os
import socket
import threading
import time

args = argparse.ArgumentParser()
args.add_argument("--cmdq", default="/tmp/doorbell-cmdq")
args.add_argument("--out", default="/tmp/doorbell-out")
args.add_argument("--cmd-port", type=int, default=2231)
args.add_argument("--out-port", type=int, default=2232)
opts = args.parse_args()


def serve(port, handler):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", port))
    s.listen(5)
    print(f"listening on {port}", flush=True)
    while True:
        conn, addr = s.accept()
        try:
            handler(conn, addr)
        except Exception as exc:  # keep the hub alive
            print(f"{port}: {exc}", flush=True)
        finally:
            try:
                conn.close()
            except OSError:
                pass


def cmd_handler(conn, addr):
    print(time.strftime("%H:%M:%S"), "cmd", addr, flush=True)
    if not os.path.exists(opts.cmdq):
        return
    data = open(opts.cmdq, "rb").read()
    os.remove(opts.cmdq)
    if data:
        conn.sendall(data)


def out_handler(conn, addr):
    print(time.strftime("%H:%M:%S"), "out", addr, flush=True)
    conn.settimeout(8)
    data = b""
    while True:
        try:
            chunk = conn.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        data += chunk
    with open(opts.out, "ab") as fh:
        fh.write(b"\n=== " + time.strftime("%Y-%m-%d %H:%M:%S").encode() + b" ===\n" + data)


threading.Thread(target=serve, args=(opts.cmd_port, cmd_handler), daemon=True).start()
serve(opts.out_port, out_handler)
