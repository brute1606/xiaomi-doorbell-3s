# Installing the published firmware

This is the shortest path from a release asset to a working device. Read
[docs/05-flashing.md](05-flashing.md) first: it covers the programmer, the clip
and the layouts, and it is the part where most mistakes happen.

## Option A — flash the released region as is

The released `rootfs-region-<version>.bin` is generic: it contains no device
data, but it also contains **no hub address** (the poller uses a documentation
placeholder and simply finds nothing). The device works like the stock one, with
the SoC kept awake. Use this option if you only want the region without the
control channel, or as a sanity check before building your own.

1. Download the release assets and verify them:

   ```bash
   sha256sum -c SHA256SUMS
   ```

2. Take your own full dump (board unpowered, clip attached):

   ```bash
   sudo flashrom -p ch341a_spi -r stock.bin
   ```

3. Merge the released region into **your** dump:

   ```bash
   ./tools/build-image.sh stock.bin rootfs-region-v0.2.0.bin my-image.bin both
   ```

4. Flash the two rootfs slots and verify:

   ```bash
   printf '002c8000:007b7fff rootfs\n007b8000:00ca7fff rootfs1\n' > rootfs.layout
   sudo flashrom -p ch341a_spi -l rootfs.layout -i rootfs -i rootfs1 -w my-image.bin
   sudo flashrom -p ch341a_spi -l rootfs.layout -i rootfs -i rootfs1 -v my-image.bin
   ```

5. (Optional) patch the tag to get kernel logs on the UART console —
   see [docs/06-uart-console.md](06-uart-console.md). The tag holds per-device
   data, so only patch your own dump.

## Option B — build a region with your own hub address (recommended)

`tools/build-rootfs.sh` unpacks the stock rootfs from your dump, adds the
control-channel scripts and writes your hub address into `/etc/net.env`, then
repacks the region:

```bash
sudo ./tools/build-rootfs.sh \
  --dump stock.bin \
  --out my-region.bin \
  --hub 192.0.2.10            # the host that runs tools/hub.py
# optional: --cmd-port 2231 --out-port 2232 --ota-port 2233
# optional: --static-ip 192.0.2.20 --static-gw 192.0.2.1
# optional: --console-shell   # shell on the UART console (open case only)
```

Then assemble the image and flash it as in option A, steps 3-4, using
`my-region.bin` instead of the released asset. Verify the result in the sandbox
before touching the chip:

```bash
QEMU_BIN=qemu-system-mipsel ./tools/sandbox-check.sh my-image.bin
```

## Running the hub

```bash
python3 tools/hub.py --cmdq /tmp/doorbell-cmdq --out /tmp/doorbell-out
```

Send a command by writing the command file; the output appears in the output
file:

```bash
printf 'echo hello; cat /tmp/version\n' > /tmp/doorbell-cmdq
sleep 30 && cat /tmp/doorbell-out
```

Commands are executed with a 20 s limit; prefix the first line with `#LONG` for
long ones (OTAs need 300 s).

## Over-the-air updates after the first flash

Once the channel is up, updates no longer need the programmer:

1. serve the new region on the hub (port 2233):

   ```bash
   python3 tools/ota-serve.py new-region.bin 2233
   ```

2. send the OTA command through the channel:

   ```bash
   printf '#LONG\n/usr/bin/ota.sh reboot\n' > /tmp/doorbell-cmdq
   ```

The script downloads the region, writes both slots and calls `reboot.sh`; the
device restarts by itself and comes back on the channel in about 20 s. Keep one
known-good region on the hub for manual recovery.

## If something goes wrong

- The bootloader starts **slot A** and falls back to **slot B** if A does not
  load. If a fresh image fails to boot, the device should come up on the other
  slot.
- If neither slot boots, flash your own `stock.bin` back with
  `sudo flashrom -p ch341a_spi -w stock.bin` and start over.
- `docs/10-troubleshooting.md` lists the failures we hit: undetected chip, boot
  loop, dead console, missing network on the Linux side.
