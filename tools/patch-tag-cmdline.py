#!/usr/bin/env python3
"""Patch the kernel command line inside the tag of a *user's own* dump.

Changes `console=ttyS3` -> `console=ttyS1` (full kernel log on UART1) and
removes `quiet`. Both primary and backup CMDL copies are patched.

The patched dump is written to a new file; flashing is still done by the user.
The tag contains per-device data (serial number, calibration), which is why this
script never ships a ready-made tag: it edits the dump of the specific device.

usage: patch-tag-cmdline.py <dump16M.bin> <out16M.bin>
"""
import sys

CMDL_PRIMARY = 0x42004
CMDL_BACKUP = 0x49004
QUIET_PRIMARY = 0x420FA
QUIET_BACKUP = 0x490FA


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    d = bytearray(open(src, "rb").read())
    if len(d) != 16 * 1024 * 1024:
        print("dump must be exactly 16 MiB")
        return 1
    for off in (CMDL_PRIMARY, CMDL_BACKUP):
        if d[off:off + 13] != b"console=ttyS3":
            print(f"unexpected CMDL at 0x{off:x}: {d[off:off+13]!r}")
            return 1
        d[off:off + 13] = b"console=ttyS1"
    for off in (QUIET_PRIMARY, QUIET_BACKUP):
        if d[off:off + 5] == b"quiet":
            d[off:off + 5] = b"     "
    open(dst, "wb").write(bytes(d))
    print(f"patched {src} -> {dst}")
    print("flash the tag with: flashrom -l tag.layout -i tag -w", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
