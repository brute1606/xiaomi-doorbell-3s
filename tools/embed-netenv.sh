#!/bin/sh
# Embed /etc/net.env into a released rootfs region.
#
# The minimal-root region ships with a documentation placeholder address. This
# script rewrites /etc/net.env inside the region with your own hub address, so
# the device can reach your control channel after flashing.
#
# usage: sudo tools/embed-netenv.sh <region.bin> <out-region.bin> <hub-ip>
#                                   [cmd-port] [out-port]
# Requires: cpio, lzop, root (cpio needs root to keep /dev nodes).
set -eu
REGION=${1:?rootfs region}; OUT=${2:?output region}; HUB=${3:?hub address}
CMD_PORT=${4:-2231}; OUT_PORT=${5:-2232}
HERE=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" -eq 0 ] || { echo "run as root (cpio needs it for /dev nodes)" >&2; exit 1; }
[ "$(stat -c%s "$REGION")" -eq 5177344 ] || { echo "region must be 5177344 bytes" >&2; exit 1; }
command -v cpio >/dev/null && command -v lzop >/dev/null || { echo "need cpio and lzop" >&2; exit 1; }

WORK=$(mktemp -d /tmp/doorbell-netenv-XXXXXX)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root"

python3 - "$REGION" "$WORK/r.lzo" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
length = struct.unpack("<I", d[:4])[0]
open(sys.argv[2], "wb").write(b"\x89LZO" + d[4:4 + length])
PY
lzop -d -c "$WORK/r.lzo" > "$WORK/r.cpio"
(cd "$WORK/root" && cpio -idm --no-absolute-filenames < "$WORK/r.cpio" 2>/dev/null)

{
  echo "HUB=$HUB"
  echo "CMD_PORT=$CMD_PORT"
  echo "OUT_PORT=$OUT_PORT"
} > "$WORK/root/etc/net.env"

(cd "$WORK/root" && find . | cpio -o -H newc 2>/dev/null) | lzop -9 -c > "$WORK/new.lzo"
python3 - "$WORK/new.lzo" "$OUT" <<'PY'
import struct, sys
body = open(sys.argv[1], "rb").read()[4:]
REGION = 5056 * 1024
assert len(body) <= REGION - 4, f"rootfs too big: {len(body)}"
open(sys.argv[2], "wb").write(struct.pack("<I", len(body)) + body + b"\x00" * (REGION - 4 - len(body)))
print(f"written: {sys.argv[2]} (hub {sys.argv[3] if len(sys.argv) > 3 else ''})")
PY
sha256sum "$OUT"
