# Firmware releases

## Video over RTSP: [v0.6.0](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.6.0)

The custom image now also serves the encoder stream over RTSP directly from the
device. The vendor application is still absent; the Wi-Fi module firmware and
the control/power firmware are untouched.

- **RTSP server on the device** (`/usr/bin/doorbell_rtsp`, static): `/main`
  (H.265, 2048×1536, 15 fps), `/sub` (H.265, 512×384, 15 fps) and `/detect`
  (key-frame only, about 1 fps) — no transcoding, no intermediate server, see
  [docs/17-video-rtsp.md](../docs/17-video-rtsp.md);
- Home Assistant **MQTT discovery**: the device and its entities are created
  automatically (events, switches, select, binary sensors, battery);
- **gratuitous ARP** announcements, so other LAN hosts do not need static ARP
  entries for the doorbell;
- MQTT keep-alive raised for unstable Wi-Fi links; discovery is published once
  per boot;
- all previous functionality: ring, motion, tamper, chime, battery, sleep, LED,
  IR-cut, siren, "on base".

Assets: `rootfs-region-v0.6.0.bin` (slot A region, 5,177,344 bytes),
`SHA256SUMS`, `RELEASE-NOTES.md`. A full 16 MiB image is not published: a
complete dump also contains factory device data (boot environment identifiers,
vendor configuration and cloud logs). Merge the region into your own dump
instead — see [docs/12-install-release.md](../docs/12-install-release.md).


## First build without the vendor application: [v0.5.0](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.5.0)

This is the first image where the device boots **without** `doorbell.out`.
The Wi-Fi module firmware and the control/power firmware stay untouched.

- custom static daemon replaces the vendor application: ring, motion, tamper,
  chime, battery level and charging, low-power sleep;
- MQTT client with retained states, events, commands and a last-will
  (`doorbell3s/#`) — Home Assistant examples in
  [docs/15-mqtt-home-assistant.md](../docs/15-mqtt-home-assistant.md);
- controls over MQTT: LED, IR-cut filter, tamper siren, sleep enable/disable;
  "on base" state is published as well;
- optional serial control channel (`poller`) with documentation placeholders in
  `/etc/net.env`; not required for MQTT operation;
- **no credentials in the image**: Wi-Fi (`/config/wifi.env` or USB gadget
  provisioning) and MQTT (`/config/mqtt.env`) are configured on the device;
- **no video/RTSP yet** — `imp_sync_server` is kept for future work;
- safe re-flashing procedure, recovery notes and a programmer-based path:
  [docs/16-safe-flashing.md](../docs/16-safe-flashing.md),
  [docs/12-install-release.md](../docs/12-install-release.md).

Assets: `rootfs-region-v0.5.0.bin` (slot A region, 5,177,344 bytes),
`SHA256SUMS`, `RELEASE-NOTES.md`. Note: the full 16 MiB asset of this release
was withdrawn because a complete dump contains factory device data; only the
rootfs region is published.

## Minimal working build: [v0.4.0](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.4.0)
 [v0.4.0](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.4.0)

Starting point for a root-capable device that still behaves like stock:

- **stock vendor application, unmodified** (it starts by default);
- one control channel (`poller.sh`) with a supervisor (`poller-guard.sh`),
  continuous logs, diagnostics, boot guard and a one-shot trial runner;
- the endpoint is read from `/etc/net.env` with documentation placeholders —
  rewrite it with `tools/embed-netenv.sh` before relying on the channel;
- **not included**: video/RTSP, vendor-app removal, MQTT/Home Assistant
  integration. Those experiments are described in the documentation but are
  not part of this image.

Rebuild it from your own dump: `tools/build-region-from-dump.sh`
(see [docs/04-build.md](../docs/04-build.md)).

## Minimal root build: [v0.3.0](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.3.0)

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
