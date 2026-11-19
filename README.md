# Xiaomi Smart Doorbell 3S (`MJML07-FJ`) — reverse engineering & custom firmware

Unofficial documentation and tooling for the **Xiaomi Smart Doorbell 3S**
(`MJML07-FJ`): firmware analysis, building and flashing custom images, UART
console, A/B slots, OTA.

> ⚠️ Everything is at **your own risk**. A bad flash can brick the device.
> Always take a full flash dump and keep several copies before experimenting.

## Hardware (short)

- SoC: **Ingenic T31** (MIPS32r2, Linux 3.10.14)
- Camera: **SmartSens SC301IoT** (3 MP)
- Wi-Fi/BT: **Bouffalo Lab BL616** in the `MSHWB01L-IB` module (SDIO)
- Control/power: handled by that module's firmware over UART (no separate MCU chip)
- Flash: **Zbit ZB25VQ128**, 16 MiB SPI NOR
- Power: Li-ion battery + charging board, USB-C
- Firmware: vendor **ZRT/Zeratul**, app `doorbell.out` + `imp_sync_server`

See [docs/01-hardware.md](docs/01-hardware.md) for details.

## Repository layout

| Path | Purpose |
|---|---|
| `docs/` | Hardware, partitions, image format, build, flashing (including safe re-flashing), UART, QEMU sandbox, A/B slots, OTA, network addressing, replacing the vendor application, MQTT/Home Assistant, video over RTSP, release installation |
| `tools/` | Build / verify / flash / OTA scripts |
| `firmware/` | Release notes; actual images are published as **GitHub Releases** assets |

## Quick start

1. Dump the flash and keep it safe (CH341A + SOIC-8 clip, board unpowered).
2. Unpack the image: [docs/03-firmware-format.md](docs/03-firmware-format.md).
3. Build your own rootfs: [docs/04-build.md](docs/04-build.md).
4. Test it in the QEMU sandbox: [docs/07-sandbox-qemu.md](docs/07-sandbox-qemu.md).
5. Flash the device: [docs/05-flashing.md](docs/05-flashing.md).

To install a **published release** instead of building from scratch, follow
[docs/12-install-release.md](docs/12-install-release.md): download the asset,
merge it into your own dump, flash, then configure Wi-Fi and MQTT on the device.

## Releases

- **[v0.6.0 — video over RTSP](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.6.0)**:
  the custom daemon now also serves the encoder stream over RTSP directly from
  the device: `/main` (3 MP H.265), `/sub` (512×384) and `/detect` (key-frame
  only, about 1 fps) — no vendor application and no intermediate server, see
  [docs/17-video-rtsp.md](docs/17-video-rtsp.md). Adds Home Assistant MQTT
  discovery and gratuitous ARP announcements; keeps ring/motion/tamper/chime/
  battery/sleep/LED/IR-cut/siren control.

- **[v0.5.0 — first build without the vendor application](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.5.0)**:
  the stock `doorbell.out` is gone; a small custom daemon handles ring, motion,
  tamper, chime, battery, low-power sleep, LED, IR-cut and the tamper siren, and
  talks MQTT (retained states, commands, last-will) to any broker — see
  [docs/15-mqtt-home-assistant.md](docs/15-mqtt-home-assistant.md). No
  video/RTSP yet. Credentials are not in the image; see
  [docs/12-install-release.md](docs/12-install-release.md).
- **[v0.4.0 — minimal working build](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.4.0)**:
  stock vendor application plus one control channel, continuous logs,
  diagnostics, boot guard and a trial runner. No video/RTSP, the vendor
  application is **not** removed. See [firmware/README.md](firmware/README.md).
- **[v0.3.0 — minimal root build](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.3.0)**: stock vendor firmware with a single
  patch (the SoC stays awake) plus the control channel and `reboot.sh`; the
  smallest starting point if you only want root on your own device.
- **[v0.2.0 — first working control channel](https://github.com/brute1606/xiaomi-doorbell-3s/releases/tag/v0.2.0)**: same patch plus OTA,
  service mode and log helpers.

Only the rootfs region is published; your own dump is required for flashing
(see [docs/12-install-release.md](docs/12-install-release.md)).

## Status

Working today: control channel over Wi-Fi (outbound only), OTA to both slots
with a watchdog-based restart, UART console for logs, and a service mode that
enables a console shell on demand.

Reverse engineering of the application ↔ `agent` JSON bus made it possible to
run the device **without the vendor application**: a small static daemon
receives button/PIR events, rings the chime, and reproduces the vendor's
autonomous sleep sequence so the button still wakes the device (see
[docs/14-vendor-app-replacement.md](docs/14-vendor-app-replacement.md)).
Still ahead: MQTT/Home Assistant events, PIR/tamper logic and video/RTSP.


## What is published (and what is not)

Only the **rootfs region** (5 177 344 bytes) is published as firmware: it is
generic system software and contains no network credentials, serial numbers or
calibration data.

**Never share full 16 MiB dumps or full images.** They contain the `tag`
partition (serial number, DID, Wi-Fi data, cloud keys and per-device sensor
calibration) and the `config` partition (logs and cached settings). Build images
from **your own** dump with `tools/build-image.sh` so your device data stays with
you.

## License

MIT — see [LICENSE](LICENSE). This project is not affiliated with Xiaomi;
all trademarks belong to their owners.
