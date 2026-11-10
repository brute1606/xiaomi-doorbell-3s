# OTA updates over the air

## Requirements

- The SoC must stay awake (see the `fj_system_soc_powerOff` patch in
  [docs/03-firmware-format.md](03-firmware-format.md)); otherwise it powers off
  in the middle of an update.
- A control channel: the device periodically connects to a hub host, fetches a
  command file and uploads the output. No inbound ports are needed on the
  device.

## Rootfs region transfer

The OTA payload is the **rootfs region** (5056K: length prefix + lzop stream +
padding), not the whole 16 MiB image. Serve it from the hub:

```bash
python3 tools/ota-serve.py rootfs_region.bin 2233
```

On the device, download and write both slots:

```sh
#!/bin/sh
H=HUB_HOST; P=2233; EXPECT=5177344; IMG=/tmp/ota.img
/bin/nc -d -w 120 "$H" "$P" > "$IMG"
sz=$(stat -c%s "$IMG")
[ "$sz" = "$EXPECT" ] || { echo "bad size: $sz"; exit 1; }
flash_eraseall /dev/mtd4; flashcp "$IMG" /dev/mtd4
flash_eraseall /dev/mtd3; flashcp "$IMG" /dev/mtd3
sync
reboot
```

`flash_eraseall` and `flashcp` are busybox applets present in the stock
firmware. The rootfs is mounted from RAM, so writing the rootfs partitions of a
running device is safe.

## Making it safe

1. Verify the image in the sandbox **before** publishing it for OTA
   ([docs/07-sandbox-qemu.md](07-sandbox-qemu.md)).
2. Compare sizes before erasing; abort on mismatch.
3. Keep the previous image on the hub for manual recovery.
4. Prefer the A/B scheme once the slot switching is understood
   ([docs/08-ab-slots.md](08-ab-slots.md)): write one slot, keep the other as a
   known-good fallback.

## Notes

- OTA must not run while the battery is low or while the device is about to
  sleep.
- If the update is interrupted, the slot that was being written is invalid; the
  loader should fall back to the other slot. Verify this behaviour on your
  device before relying on it.
