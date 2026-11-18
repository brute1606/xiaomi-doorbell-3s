#!/usr/bin/env python3
"""Serve one file over a raw TCP stream (for device-side `nc` downloads).

usage: serve-file.py <file> <port> [--once]
"""
import socket
import sys

def main():
    path, port = sys.argv[1], int(sys.argv[2])
    data = open(path, "rb").read()
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("0.0.0.0", port))
    s.listen(1)
    print("serving %s (%d bytes) on %d" % (path, len(data), port), flush=True)
    while True:
        c, addr = s.accept()
        print("client %s" % (addr,), flush=True)
        try:
            c.sendall(data)
        finally:
            c.close()

if __name__ == "__main__":
    main()
