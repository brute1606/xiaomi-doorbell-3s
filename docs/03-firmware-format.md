# Firmware format

## rootfs (initramfs)

The rootfs partition (5056K) is laid out as:

```
[ uint32 length ][ lzop stream WITHOUT magic ][ 0x00 padding up to 5056K ]
```

- `length` — size of the lzop stream (little-endian), not including this prefix;
- the stream has **no** 9-byte `89 4c 5a 4f ...` magic. To decompress it with a
  standard `lzop`, prepend the magic:

```bash
python3 - <<'PY'
d = open('rootfs_region.bin', 'rb').read()
n = int.from_bytes(d[:4], 'little')
open('rootfs.lzo', 'wb').write(b'\x89LZO\x00\r\n\x1a\n' + d[4:4 + n])
print('lzo stream:', n)
PY
lzop -d -c rootfs.lzo > rootfs.cpio
```

- The decompressed payload is **cpio (newc)** initramfs, about 11.3 MiB;
- **Critical:** the stream must be compressed with **lzop 1.03**. Streams
  produced by 1.04 are rejected by this bootloader.

Sanity check: the cpio must contain the `/dev` device nodes (around 50 of them).
If the cpio is built without root, the nodes are missing, the application fails
and the device ends up in a reboot loop.

## kernel

`mtd2` is a uImage compressed with lzop (`comp=4`), load `0x80010000`, entry
`0x803796b0`. Normally there is no need to touch it.

## tag (cmdline and calibration)

`tag` contains blocks `CMDL/ENVI/BTIF/...` after the `09 c3 08 a1` magic. `CMDL`
holds `console=ttyS3,115200n8 mem=72M@0x0 rmem=56M@0x4800000 root=/dev/ram0 rw
rdinit=/linuxrc mtdparts=... lpj=6955008 quiet`.

Replacing `console=ttyS3` with `console=ttyS1` (and removing `quiet`) enables
the full kernel log on UART1. The replacement has the same length, so it is safe;
patch both the primary and the backup `CMDL` copy.

## system

Squashfs mounted at `/system`; it contains vendor utilities such as `bin/nc`.
The partition is read-only; put your own binaries into the rootfs instead.

## config

JFFS2 mounted at `/config`. The application and scripts write logs and counters
there. The partition is small (768K); if it is corrupted by a power loss, the
stock rcS reformats it automatically when `.tag` is missing.

## "SoC never sleeps" patch

The application asks the MCU to power the SoC off in `fj_system_soc_powerOff`
(`doorbell.out`, vaddr `0x43cd4c`, file offset `0x3cd4c`). Replacing the first
instructions with `jr ra; nop` (`03 e0 00 08`, `00 00 00 00`) disables that:

```bash
./tools/patch-poweroff.py doorbell.out doorbell-nooff.out
```

Note: with sleep disabled the SoC is always on, the camera keeps encoding and
the battery drains quickly — use USB-C power.
