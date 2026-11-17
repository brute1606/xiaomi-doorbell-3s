#!/bin/sh
# Build the public minimal rootfs region (v0.4.0) from your own full 16 MiB dump.
#
# The image keeps the stock vendor application (it starts by default) and adds:
#   - a single control channel (poller.sh) + poller-guard, logs, diag, trial-run
#   - /etc/net.env with documentation placeholder addresses (edit or embed)
#   - /bin/nc copied from your dump's system partition
#
# usage: sudo NC=/path/to/nc DUMP=stock.bin LZOP_BIN=/path/to/lzop sh build-region-from-dump.sh
#   DUMP      full 16 MiB dump of your device
#   NC        a static/uclibc nc binary (extract /system/bin/nc from the squashfs)
#   LZOP_BIN  lzop 1.03 binary (the bootloader needs 1.03, not 1.04)
#   OUT       output region file (default ./rootfs-region-v0.4.0.bin)
#   WORK      scratch directory (default /tmp/doorbell-build)
# Scripts are taken from tools/device/.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DUMP=${DUMP:?path to full 16 MiB dump (stock.bin)}
LZOP_BIN=${LZOP_BIN:-lzop}
WORK=${WORK:-/tmp/doorbell-build}
OUT=${OUT:-./rootfs-region-v0.4.0.bin}
ROOT="$WORK/root"
command -v "$LZOP_BIN" >/dev/null || { echo "need lzop 1.03 ($LZOP_BIN)" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "run as root: cpio needs it for /dev nodes" >&2; exit 1; }
[ -f "$DUMP" ] || { echo "no dump: $DUMP" >&2; exit 1; }
rm -rf "$WORK"; mkdir -p "$WORK" "$ROOT"
python3 - "$DUMP" "$WORK/b.lzo" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert len(d) == 16777216, 'dump must be 16 MiB'
reg = d[0x2C8000:0x2C8000 + 5056*1024]
n = struct.unpack('<I', reg[:4])[0]
assert set(reg[4+n:]) <= {0, 255}, 'region tail is not 0/0xff'
open(sys.argv[2], 'wb').write(b'\x89LZO' + reg[4:4+n])
PY
$LZOP_BIN -d -c "$WORK/b.lzo" > "$WORK/b.cpio"
(cd "$ROOT" && cpio -idm --no-absolute-filenames < "$WORK/b.cpio")
NC=${NC:?path to a static nc binary (e.g. extracted /system/bin/nc from your dump)}
cp "$NC" "$ROOT/bin/nc"; chmod 755 "$ROOT/bin/nc"
cp "$HERE/device/"*.sh "$ROOT/usr/bin/"
cat > "$ROOT/etc/net.env" <<'ENV'
# Documentation placeholder addresses (RFC 5737). Rewrite before use, or
# rewrite inside the released region: tools/embed-netenv.sh <region> <out> <hub-ip>
HUB=192.0.2.10
CMD_PORT=2231
OUT_PORT=2232
OTA_PORT=2233
LOG_PORT=2234
STATIC_IP=192.0.2.20
STATIC_MASK=255.255.255.0
STATIC_GW=192.0.2.1
ENV
chmod 755 "$ROOT/usr/bin/"*.sh
python3 - "$ROOT/etc/init.d/rcS" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
if '/tmp/version' not in t:
    t = t.replace('export SOC_TYPE=SOC_T31Z',
                  'export SOC_TYPE=SOC_T31Z\necho v0.4.0 > /tmp/version', 1)
if 'poller-guard.sh' not in t:
    old = 'doorbell.out &\n'
    assert old in t, 'no doorbell.out start line'
    block = (
        'doorbell.out &\n'
        'if [ -x /usr/bin/poller-guard.sh ]; then\n'
        '  /usr/bin/diag.sh &\n'
        '  /usr/bin/poller-guard.sh &\n'
        '  /usr/bin/logs.sh &\n'
        '  /usr/bin/boot-guard.sh health &\n'
        '  /usr/bin/trial-run.sh &\n'
        'fi\n'
    )
    t = t.replace(old, block, 1)
open(p, 'w').write(t)
print('rcS patched')
PY
bash -n "$ROOT/etc/init.d/rcS"
grep -q 'doorbell.out &' "$ROOT/etc/init.d/rcS"
(cd "$ROOT" && find . | cpio -o -H newc) > "$WORK/out.cpio" 2>/dev/null
$LZOP_BIN -9 -c "$WORK/out.cpio" > "$WORK/out.lzo"
python3 - "$WORK/out.lzo" "$OUT" <<'PY'
import struct, sys, hashlib
body = open(sys.argv[1], 'rb').read()[4:]
REGION = 5056*1024
assert len(body) <= REGION - 4, f'rootfs too big: {len(body)}'
reg = struct.pack('<I', len(body)) + body + b'\x00'*(REGION-4-len(body))
open(sys.argv[2], 'wb').write(reg)
print('region bytes:', len(reg))
print('sha256:', hashlib.sha256(reg).hexdigest())
PY
