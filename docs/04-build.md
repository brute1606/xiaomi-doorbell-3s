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
