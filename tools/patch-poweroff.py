#!/usr/bin/env python3
"""Disable the SoC power-off call in the stock doorbell application.

The stock app asks the MCU to cut SoC power in `fj_system_soc_powerOff`
(vaddr 0x43cd4c, file offset 0x3cd4c in doorbell.out).  The first two
instructions are replaced with `jr ra; nop`, so the function returns
immediately and the SoC stays powered.

Usage: patch-poweroff.py <doorbell.out> <doorbell-patched.out>
"""
import sys

OFFSET = 0x3CD4C
ORIGINAL = bytes.fromhex("46001c3c54799c27")   # lui gp,0x46 ; addiu gp,gp,0x7954
PATCH = bytes.fromhex("0800e00300000000")      # jr ra ; nop


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    data = bytearray(open(src, "rb").read())
    if data[OFFSET:OFFSET + 8] != ORIGINAL:
        print(f"Unexpected bytes at 0x{OFFSET:x}: {data[OFFSET:OFFSET+8].hex()}")
        print("This doorbell.out version differs; adjust OFFSET/ORIGINAL.")
        return 1
    data[OFFSET:OFFSET + 8] = PATCH
    open(dst, "wb").write(data)
    print(f"patched {src} -> {dst} (jr ra at 0x{OFFSET:x})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
