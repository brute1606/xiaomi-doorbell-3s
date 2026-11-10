#!/usr/bin/env python3
"""Serve a rootfs region to a doorbell over TCP (OTA).

usage: ota-serve.py <rootfs_region.bin> [port]
"""
import socket
import sys

port = int(sys.argv[2]) if len(sys.argv) > 2 else 2233
data = open(sys.argv[1], "rb").read()
print(f"serving {sys.argv[1]} ({len(data)} bytes) on :{port}", flush=True)
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("0.0.0.0", port))
srv.listen(5)
while True:
    conn, addr = srv.accept()
    print("download from", addr, flush=True)
    try:
        conn.sendall(data)
    except OSError as exc:
        print("send error:", exc, flush=True)
    conn.close()
