# Installing a published firmware release

This is the shortest path from a release asset to a working device. Read
[docs/05-flashing.md](05-flashing.md) first: it covers the programmer, the clip
and the layouts, and it is the part where most mistakes happen.
[docs/16-safe-flashing.md](16-safe-flashing.md) describes how to write an image
without leaving a half-written slot.

## Current release

**v0.5.0 — first build without the vendor application.**

- the vendor `doorbell.out` is **not** in the image; a small custom daemon
  (`/usr/bin/doorbeld`) is started by `rcS` and talks to the control/power
  firmware over the local JSON-RPC bridge;
- the Wi-Fi module firmware and the control/power firmware are untouched;
- features: ring / motion / tamper events, chime, battery level and charging,
  low-power sleep, LED, IR-cut filter, tamper siren, "on base" state, all over
  MQTT ([docs/15-mqtt-home-assistant.md](15-mqtt-home-assistant.md));
- **no video/RTSP yet** (`imp_sync_server` is kept, but no client is shipped);
- the image contains **no credentials**: MQTT and Wi-Fi are configured on the
  device after flashing.

Assets:

| File | Purpose |
|---|---|
| `rootfs-region-v0.5.0.bin` | rootfs region for slot A (5,177,344 bytes) |
| `doorbell-3s-v0.5.0-full16M.bin` | full 16 MiB image: slot A = v0.5.0, slot B = original factory firmware from the source dump |
| `SHA256SUMS` | checksums |

Use the region asset if you already have your own dump and want to keep your own
slot B. Use the full image if you prefer a single programmer write and accept
that slot B becomes the same factory firmware as in the source dump.

## Option A — merge the released region into your own dump (recommended)

The released region contains no device data (tag block, identifiers, credentials
— all absent by design).

1. Download the assets and verify them:

   ```bash
   sha256sum -c SHA256SUMS
   ```

2. Take your own full dump (board unpowered, clip attached):

   ```bash
   sudo flashrom -p ch341a_spi -r stock.bin
   ```

3. Merge the released region into **slot A only** of your dump:

   ```bash
   ./tools/build-image.sh stock.bin rootfs-region-v0.5.0.bin my-image.bin a
   ```

   Keeping slot B untouched leaves the factory firmware as a fallback. If you
   want both slots on the new build, use `both` — but keep a separate copy of
   your stock dump.

4. Flash the rootfs area with `flashrom`:

   ```bash
   printf '002c8000:007b7fff rootfs\n007b8000:00ca7fff rootfs1\n' > rootfs.layout
   sudo flashrom -p ch341a_spi -l rootfs.layout -i rootfs -w my-image.bin
   sudo flashrom -p ch341a_spi -l rootfs.layout -i rootfs -v my-image.bin
   ```

   For a full-image write use `sudo flashrom -p ch341a_spi -w my-image.bin`.

## First boot: Wi-Fi and MQTT

The image ships with documentation placeholders in `/etc/net.env` and no
credentials. Configure the device:

- **Wi-Fi** — either write `/config/wifi.env` on the `config` partition (a small
  JFFS2 volume on the flash, see [docs/02-partitions.md](02-partitions.md)):

  ```
  SSID=your-network
  PASS=your-passphrase
  ```

  It is applied on boot. Alternatively use the USB gadget provisioning mode:
  create `/config/prov.enable`, reboot with the device on USB; the doorbell
  exposes a serial port and accepts `SSID` / password lines, see
  `docs/14-vendor-app-replacement.md`.

- **MQTT** — create `/config/mqtt.env` (mode 0600):

  ```
  MQTT_HOST=192.0.2.10
  MQTT_PORT=1883
  MQTT_USER=doorbell
  MQTT_PASS=change-me
  ```

  Without this file the device still runs the control firmware side (ring,
  motion, tamper, chime, battery), but publishes nothing over MQTT.

After reboot check the daemon log:

```bash
cat /tmp/doorbeld.log
```

You should see `=== doorbeld v2 start ===` and, with a reachable broker,
`MQTT connected <host>:<port>`.

## Option B — build your own region

`tools/build-rootfs.sh` unpacks the stock rootfs from your dump, installs the
scripts you provide and writes your own settings into `/etc/net.env`:

```bash
sudo ./tools/build-rootfs.sh \
  --dump stock.bin \
  --out my-region.bin \
  --hub 192.0.2.10            # host for the optional control channel
```

Then assemble the image and flash it as in option A, steps 3-4, and test it in
the sandbox first:

```bash
QEMU_BIN=qemu-system-mipsel ./tools/sandbox-check.sh my-image.bin
```

## Optional control channel

The image also contains the old serial-command channel (`poller`), whose
endpoint is read from `/etc/net.env`. With the published placeholders it simply
finds nothing, which is fine: MQTT is the primary interface. If you want the
channel for remote maintenance, point `HUB` at a host running the small server
from this repository (`tools/hub.py`) and use ports 2231/2232.

## Over-the-air updates after the first flash

Once device and host are on the same network, updates do not need the
programmer. Serve the new region and write it with the safe procedure from
[docs/16-safe-flashing.md](16-safe-flashing.md): the device downloads the image,
erases and writes slot A, verifies the CRC32 and only then reboots.

## If something goes wrong

- The bootloader starts **slot A** and falls back to **slot B** if A does not
  load. If a fresh image fails to boot, the device should come up on the other
  slot (stock firmware if you kept it).
- If neither slot boots, flash your own `stock.bin` back with
  `sudo flashrom -p ch341a_spi -w stock.bin` and start over.
- [docs/10-troubleshooting.md](10-troubleshooting.md) lists the failures we hit:
  undetected chip, boot loop, missing network, a broken `rcS`.
