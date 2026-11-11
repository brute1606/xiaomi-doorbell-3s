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

On the device the helper `/usr/bin/ota.sh` does the same job; it reads the hub
from `/config/net.env` (or `/etc/net.env`), verifies the size and writes both
slots:

```sh
# from the hub, through the control channel
printf '#LONG\n/usr/bin/ota.sh reboot\n' > /tmp/doorbell-cmdq
```

`#LONG` raises the poller's execution limit to 300 s. Without the `reboot`
argument the script only writes the slots; the restart is then done by
`/usr/bin/reboot.sh` ([docs/11-reboot.md](11-reboot.md)).

`flash_eraseall` and `flashcp` are busybox applets present in the stock
firmware. The rootfs is mounted from RAM, so writing the rootfs partitions of a
running device is safe.

## Making it safe

1. Verify the image in the sandbox **before** publishing it for OTA
   ([docs/07-sandbox-qemu.md](07-sandbox-qemu.md)).
2. Compare sizes before erasing; abort on mismatch.
3. Keep the previous image on the hub for manual recovery.
4. Keep the A/B scheme in mind ([docs/08-ab-slots.md](08-ab-slots.md)): slot A is
   started first, slot B is the fallback; a single-slot update keeps the
   previous image in the other slot.

## Notes

- OTA must not run while the battery is low or while the device is about to
  sleep.
- If the update is interrupted, the slot being written is invalid and the
  loader falls back to the other slot (verified on hardware).

## Slots and rebooting after an update

The bootloader always starts **slot A** (the `rootfs` partition) and falls back
to **slot B** (`rootfs1`) if A cannot be loaded. A single-slot update therefore
writes the candidate into A and keeps B as the previous known-good image.

Write order used by the helper script: slot B first, then slot A. If the write
of A is interrupted, B still holds a bootable image.

After the write the device has to be restarted — see
[docs/11-reboot.md](11-reboot.md). The control channel marks long commands with
a `#LONG` first line; the poller raises its execution budget from 20 s to 300 s
for those, which is enough for a 5 MiB download plus two flash writes.

## Device-side configuration

The poller and the OTA script read `/config/net.env`:

```sh
HUB=192.0.2.10
CMD_PORT=2231
OUT_PORT=2232
OTA_PORT=2233
# optional: static address for the Linux side of the Wi-Fi interface
STATIC_IP=192.0.2.20
STATIC_MASK=255.255.255.0
STATIC_GW=192.0.2.1
```

`STATIC_IP` is only needed when the vendor network setup does not configure the
Linux interface (see [docs/10-troubleshooting.md](10-troubleshooting.md)).
