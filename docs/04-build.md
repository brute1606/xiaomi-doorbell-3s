# Building a custom rootfs and a full image

## Prerequisites

```bash
sudo apt install cpio lzop gcc make
# lzop 1.03 is required by the bootloader; distro packages may ship 1.04.
# Build 1.03 from source if needed:
#   ./configure CFLAGS="-O2 -std=gnu89 -fcommon -Wno-error" && make
```

You also need a full flash dump of your device (`stock.bin`, 16 MiB) — the
image is assembled by patching this dump, so the bootloader, tag, kernel and
calibration data are preserved.

## Step 1 — extract the stock rootfs as root

```bash
mkdir rootfs
sudo cpio -idm --no-absolute-filenames -D rootfs < stock.cpio
```

Extraction **must** run as root: otherwise the `/dev` device nodes are missing
and the resulting image will not work.

## Step 2 — modify the rootfs

At the very minimum you may append a block to `etc/init.d/rcS`. Example: start
a small poller that talks to your own server (replace the placeholders, do not
commit real addresses):

```sh
(
  exec > /tmp/poller.log 2>&1
  sleep 10
  while true; do
    /bin/nc -d -w 4 "$HUB_HOST" "$HUB_PORT" > /tmp/cmd 2>/dev/null &
    p=$!
    sleep 6
    kill -9 $p 2>/dev/null
    wait $p 2>/dev/null
    if [ -s /tmp/cmd ]; then
      /bin/sh /tmp/cmd > /tmp/out 2>&1
      /bin/nc -w 4 "$HUB_HOST" "$HUB_OUT" < /tmp/out 2>/dev/null &
      p2=$!
      sleep 6
      kill -9 $p2 2>/dev/null
      wait $p2 2>/dev/null
    fi
    sleep 15
  done
) &
```

Note: stock busybox has no `nc`; copy a static/uclibc `nc` (from `/system/bin/nc`)
into the rootfs, for example `/bin/nc`.

## Step 3 — repack the cpio and build the rootfs region

```bash
cd rootfs
sudo find . | cpio -o -H newc > ../rootfs.cpio
cd ..
lzop-1.03 -9 -c rootfs.cpio > rootfs.lzo
```

Then wrap it into the region format:

```bash
python3 - <<'PY'
import struct
body = open('rootfs.lzo', 'rb').read()[4:]      # drop lzop magic
part = 5056 * 1024
assert len(body) <= part - 4, 'rootfs too big'
region = struct.pack('<I', len(body)) + body + b'\x00' * (part - 4 - len(body))
open('rootfs_region.bin', 'wb').write(region)
print('region:', len(region), 'compressed:', len(body))
PY
```

## Step 4 — assemble the 16 MiB image

```bash
./tools/build-image.sh stock.bin rootfs_region.bin image.bin
```

The script writes the region into **both** rootfs slots (A and B) and prints the
image sha256. Single-slot images are also possible (see
[docs/05-flashing.md](05-flashing.md)).

## Step 5 — verify before flashing

```bash
./tools/sandbox-check.sh image.bin <expected-marker>
```

The sandbox boots the image in QEMU and checks that the kernel starts, the
device nodes work, the application starts and the marker file appears in
`/config`. Do not flash an image that has not passed this check.


## Reproducing the released minimal image (v0.4.0)

The released region can be rebuilt from your own dump with the scripts in
`tools/`:

```bash
# prerequisites: cpio, python3, lzop 1.03, root (cpio keeps /dev nodes)
sudo NC=/path/to/nc DUMP=stock.bin LZOP_BIN=/path/to/lzop \
     OUT=rootfs-region-v0.4.0.bin sh tools/build-region-from-dump.sh
```

What the script does:

1. extracts the rootfs region from the 16 MiB dump (offset `0x2C8000`);
2. unpacks the LZO+cpio archive as root;
3. copies the control-channel scripts from `tools/device/`
   (`poller.sh`, `poller-guard.sh`, `logs.sh`, `diag.sh`, `boot-guard.sh`,
   `trial-run.sh`, `wdt-feed.sh`, `netcfg.sh`) into `/usr/bin/`;
4. installs `/bin/nc` from the path you provide (stock busybox has no `nc`;
   extract `/system/bin/nc` from the squashfs of your dump);
5. writes `/etc/net.env` with documentation placeholder addresses and patches
   `etc/init.d/rcS` to start the poller, logs, diagnostics, boot guard and the
   trial runner next to the stock vendor application;
6. repacks the region, prints its size and SHA-256.

The released image keeps the vendor application: it starts by default, so the
device behaves like stock until you point `net.env` at your own hub. No video,
RTSP or vendor-app replacement is included in v0.4.0.

### Helper binaries (optional daemon experiments)

The C helpers used for the experiments (replacement daemon, keep-awake client)
are **not** part of the released image: a static MIPS binary is large (~600 KiB)
and does not fit into the 5056 KiB rootfs region next to the vendor
application. They are built with a MIPS GCC 4.7.2 (glibc 2.16, 64-bit host)
toolchain, e.g. from the Dafang-Hacks `mips-gcc472-glibc216-64bit` archive:

```bash
mips-linux-gnu-gcc -mips32r2 -Os -static -s -o doorbeld doorbeld.c
```

Static linking matters: the device rootfs uses uClibc and dynamic glibc
binaries fail with `can't load library 'libc.so.6'`.
