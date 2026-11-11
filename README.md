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
| `docs/` | Hardware, partitions, image format, build, flashing, UART, QEMU sandbox, A/B slots, OTA, network addressing |
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
merge it into your own dump, flash, and (optionally) enable the control channel
by building a region with your own hub address.

## Releases

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
enables a console shell on demand. Release **v0.2.0** is the first published
build of this state. Still ahead: local RTSP for Home Assistant, MQTT events,
and the BL616/wake research.


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
