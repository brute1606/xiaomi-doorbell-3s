# Safe re-flashing over the control channel

A/B slots make over-the-air updates possible, but an interrupted write to slot A
leaves the device unbootable until the other slot or a programmer is used. This
page describes the procedure we use to avoid that, and how to recover if it
still happens.

The short version: **never let the watchdog fire in the middle of a write**, and
**always verify what was written before rebooting**.

## Preconditions

1. The image passed the local gate (`tools/flash-gate.sh` in the companion
   build repository): static checks, `rcS` shell syntax, QEMU boot.
2. The device is awake and the daemon is running (it writes a keep-alive file
   that the watchdog feeder watches).
3. Power is stable: battery connected, charger attached.
4. You have a known-good fallback image and, ideally, a programmer.

## Why the watchdog matters

These images run a small feeder (`wdt-feed.sh`) that pets `/dev/watchdog` while
the daemon keeps `/tmp/keepalive` fresh. If the daemon dies, the feeder stops
and the SoC resets after ~120 s. A 5 MiB write + verify can take 1–3 minutes, so
a crash mid-write is exactly the failure mode that leaves a half-written rootfs.

The safe procedure therefore runs the write in the background and keeps writing
the keep-alive timestamp from the shell loop until the write finishes:

```sh
( flashcp /tmp/image.bin /dev/mtd3 >/tmp/fc.log 2>&1; echo $? > /tmp/fc.done ) &
while [ ! -f /tmp/fc.done ]; do
    read u r < /proc/uptime; echo ${u%%.*} > /tmp/keepalive
    sleep 1
done
rc=$(cat /tmp/fc.done)
[ "$rc" = 0 ] || { echo "write failed, not rebooting"; exit 1; }
```

## Verify before reboot

`flashcp` verifies what it wrote, but a second independent check is cheap and
catches surprises. A tiny static CRC32 tool (`tools/safe/crc32.c`) is built for
the target and run on the device against the flash device node; the host
compares the value with the CRC32 of the image file. Only when they match is
`reboot` issued.

```sh
# on the device
/tmp/crc32 /dev/mtd3          # -> <crc32> <size>
```

```sh
# on the host
python3 -c 'import zlib,sys; d=open(sys.argv[1],"rb").read(); print("%08x %d" % (zlib.crc32(d)&0xffffffff, len(d)))' image.bin
```

## Procedure (host side)

```bash
# 1. serve the image (example: port 2235)
python3 tools/serve-file.py image.bin 2235

# 2. queue a single long command on the control channel
#    (see docs/12-install-release.md for the channel itself)
#    the command downloads the image, erases, writes with the keep-alive loop,
#    verifies and only then calls reboot
```

The device-side script is published in this repository as
`tools/safe/flashsafe-device.sh`; `tools/flash-safe.sh` is the host-side driver
that serves the image, collects the verification value and compares checksums.

## If it goes wrong

- **Wrong checksum / failed write:** do not reboot. The running system is still
  intact; retry, or flash slot A with your programmer.
- **Device reboots and does not come back:** wait for the boot guard; if slot A
  is invalid the bootloader falls back to slot B (stock firmware in the released
  full image). Re-flash slot A with the programmer.
- **Both slots bad:** the full 16 MiB dump is the way back. Keep several copies,
  including one stored outside the device's location.

## Recovering with a programmer

1. Power off completely: battery disconnected, USB unplugged, wait a minute.
2. Attach the SPI clip to the flash chip, connect the programmer to a PC.
3. Read first (always): `flashrom -p ch341a_spi -r current.bin`, verify the chip
   is detected and the dump is 16 MiB.
4. Write the prepared image, then verify:
   `flashrom -p ch341a_spi -w image.bin` → `Verifying flash... VERIFIED`.
5. Remove the clip, reconnect the battery, boot.

Never write the reserved slot by accident: in this project slot A is the rootfs
at offset `0x2C8000` (5,177,344 bytes) and slot B starts at `0x7B8000`. Only the
rootfs region is published; merge it into your own dump so slot B and the
device-specific partitions stay yours.
