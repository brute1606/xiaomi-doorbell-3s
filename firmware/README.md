# Firmware releases

## Minimal root build: v0.3.0

For people who only want **root access** on their own device as a starting point
for their own firmware:

- stock vendor application, unchanged, plus **one** patch: the SoC no longer
  powers itself off, so the device stays reachable;
- a control channel (`poller.sh`) and `reboot.sh` — no logs, no OTA helpers, no
  services;
- the hub address is read from `/config/net.env`; the published region ships
  with a documentation placeholder, so rewrite it first:

  ```bash
  sudo tools/embed-netenv.sh rootfs-region-v0.3.0.bin my-region.bin 192.0.2.10
  ```

- root = shell commands through the channel; the UART console stays read-only on
  the device we tested (the pad carries the SoC TX only).

Everything else is the same as v0.2.0: merge the region into your own dump with
`tools/build-image.sh`, flash both rootfs slots, keep your dump for rollback.

## Current release: v0.2.0 (first working control channel)

Contents: vendor firmware with the SoC-sleep patch, a control-channel poller,
`reboot.sh` (watchdog reset), `ota.sh` and an optional UART service mode. The
device reads its endpoint from `/config/net.env` (see
[docs/09-ota.md](../docs/09-ota.md)); no addresses are baked into the image.

Tested on: `MJML07-FJ`, 16 MiB Zbit ZB25VQ128, both slots written.


Binary images are published as **GitHub Releases** assets, not committed to the
repository. Each release contains:

- `rootfs-region-<version>.bin` — 5 177 344 bytes, the rootfs region
  (`length + lzop + padding`), ready for OTA or for a direct slot write;
- `image-<version>.bin.zst` — optional full 16 MiB image (bootloader, tag,
  kernel included), compressed;
- `SHA256SUMS` — checksums for all assets;
- release notes: what changed, which device revision it was tested on, known
  issues and the rollback command.

## What is inside (and what is not)

Release assets contain **only the rootfs region**: system software, no Wi-Fi
credentials, no serial numbers, no calibration. Full 16 MiB images are never
published — build one from your own dump (see `docs/05-flashing.md`).

## Installation

See [docs/05-flashing.md](../docs/05-flashing.md) for the clip/flashrom method
and [docs/09-ota.md](../docs/09-ota.md) for over-the-air updates.

## Important

- Images are built from a dump of a specific device revision. Verify the flash
  chip and partition layout on your unit before flashing.
- Always keep a full dump of your own device; it is the only reliable way back.
