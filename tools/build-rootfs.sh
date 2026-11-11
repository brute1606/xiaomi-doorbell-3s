#!/bin/bash
# Build a rootfs region for the doorbell from your own stock dump.
#
# The script unpacks the stock rootfs from the dump, adds the control-channel
# scripts (poller, reboot, ota, service) and an /etc/net.env with your hub
# address, repacks it and writes the 5 177 344-byte region.
#
# usage:
#   sudo tools/build-rootfs.sh --dump stock.bin --out region.bin --hub 192.0.2.10
#        [--cmd-port 2231] [--out-port 2232] [--ota-port 2233]
#        [--static-ip 192.0.2.20 --static-mask 255.255.255.0 --static-gw 192.0.2.1]
#        [--console-shell]
#
# Must run as root: the rootfs contains /dev nodes, and cpio drops them when
# run as a normal user.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)

DUMP=""; OUT=""; HUB=""; CMD_PORT=2231; OUT_PORT=2232; OTA_PORT=2233
STATIC_IP=""; STATIC_MASK=255.255.255.0; STATIC_GW=""; CONSOLE_SHELL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dump) DUMP=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --hub) HUB=$2; shift 2 ;;
    --cmd-port) CMD_PORT=$2; shift 2 ;;
    --out-port) OUT_PORT=$2; shift 2 ;;
    --ota-port) OTA_PORT=$2; shift 2 ;;
    --static-ip) STATIC_IP=$2; shift 2 ;;
    --static-mask) STATIC_MASK=$2; shift 2 ;;
    --static-gw) STATIC_GW=$2; shift 2 ;;
    --console-shell) CONSOLE_SHELL=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$DUMP" ] && [ -n "$OUT" ] && [ -n "$HUB" ] || {
  echo "usage: $0 --dump stock.bin --out region.bin --hub HUB_IP [options]" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo "run as root (cpio needs it for /dev nodes)" >&2; exit 1; }
[ "$(stat -c%s "$DUMP")" -eq 16777216 ] || { echo "dump must be 16 MiB" >&2; exit 1; }
command -v cpio >/dev/null && command -v lzop >/dev/null || { echo "need cpio and lzop" >&2; exit 1; }

WORK=$(mktemp -d /tmp/doorbell-rootfs-XXXXXX)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root"

python3 - "$DUMP" "$WORK/rootfs.lzo" <<'PY'
import struct, sys
dump, lzo = sys.argv[1:3]
d = open(dump, "rb").read()
REGION = 5056 * 1024
off = 0x2C8000
region = d[off:off + REGION]
length = struct.unpack("<I", region[:4])[0]
assert 0 < length <= REGION - 4, f"bad rootfs length: {length}"
open(lzo, "wb").write(b"\x89LZO" + region[4:4 + length])
print(f"rootfs stream: {length} bytes")
PY

lzop -d -c "$WORK/rootfs.lzo" > "$WORK/rootfs.cpio"
(cd "$WORK/root" && cpio -idm --no-absolute-filenames < "$WORK/rootfs.cpio" 2>/dev/null)

install -m 0755 "$HERE/device/poller.sh"   "$WORK/root/usr/bin/poller.sh"
install -m 0755 "$HERE/device/reboot.sh"   "$WORK/root/usr/bin/reboot.sh"
install -m 0755 "$HERE/device/ota.sh"      "$WORK/root/usr/bin/ota.sh"
install -m 0755 "$HERE/device/service.sh"  "$WORK/root/usr/bin/service.sh"

{
  echo "HUB=$HUB"
  echo "CMD_PORT=$CMD_PORT"
  echo "OUT_PORT=$OUT_PORT"
  echo "OTA_PORT=$OTA_PORT"
  [ -n "$STATIC_IP" ] && echo "STATIC_IP=$STATIC_IP"
  [ -n "$STATIC_IP" ] && echo "STATIC_MASK=$STATIC_MASK"
  [ -n "$STATIC_GW" ] && echo "STATIC_GW=$STATIC_GW"
} > "$WORK/root/etc/net.env"

# start the poller from rcS; it re-checks the network before every poll
cat >> "$WORK/root/etc/init.d/rcS" <<'RC'
# --- control channel ---
echo 1 > /config/channel_enabled
echo custom > /tmp/version
/usr/bin/poller.sh &
echo $! > /tmp/poller.pid
RC

if [ "$CONSOLE_SHELL" -eq 1 ]; then
  python3 - "$WORK/root/etc/inittab" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
s = re.sub(r"^console::.*\n?", "", s, flags=re.M)
open(p, "w").write(s.rstrip("\n") + "\nconsole::respawn:/bin/sh -i\n")
PY
fi

(cd "$WORK/root" && find . | cpio -o -H newc 2>/dev/null) | lzop -9 -c > "$WORK/new.lzo"
python3 - "$WORK/new.lzo" "$OUT" <<'PY'
import struct, sys
lzo, out = sys.argv[1:3]
body = open(lzo, "rb").read()
assert body[:4] == b"\x89LZO", "unexpected lzop output"
body = body[4:]
REGION = 5056 * 1024
assert len(body) <= REGION - 4, f"rootfs too big: {len(body)}"
region = struct.pack("<I", len(body)) + body + b"\x00" * (REGION - 4 - len(body))
open(out, "wb").write(region)
print(f"region written: {out} ({len(region)} bytes, stream {len(body)})")
PY
