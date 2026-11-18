#!/usr/bin/env bash
# Host-side driver for a safe slot-A write over the device control channel.
# It serves the image, sends the device script, and compares the CRC32 that the
# device prints with the CRC32 of the image file. Reboot only after a match.
#
# usage: HUB=<host> DEVICE=<ip> ./flash-safe.sh <region.bin>
set -eu
IMG=${1:?usage: HUB=... DEVICE=... flash-safe.sh <region.img>}
HUB=${HUB:?set HUB to the host that serves the image}
DEVICE=${DEVICE:?set DEVICE to the doorbell address}
SERVE_PORT=${SERVE_PORT:-2235}
CMD_PORT=${CMD_PORT:-2231}
CMD_DIR=${CMD_DIR:-/tmp/doorbell-cmdq}
EXPECT=$(python3 - "$IMG" <<'PY'
import sys, zlib
d = open(sys.argv[1], "rb").read()
print("%08x %d" % (zlib.crc32(d) & 0xffffffff, len(d)))
PY
)
echo "image: $IMG"; echo "expected CRC32/size: $EXPECT"

python3 "$(dirname "$0")/serve-file.py" "$IMG" "$SERVE_PORT" >/tmp/serve-file.log 2>&1 &
SERVE_PID=$!
trap 'kill $SERVE_PID 2>/dev/null || true' EXIT
sleep 1

SCRIPT=$(cat "$(dirname "$0")/safe/flashsafe-device.sh")
printf '#LONG\n%s\n/tmp/crc32 /dev/mtd3\necho SAFEFLASH-VERIFY-DONE\n' "$SCRIPT" > "$CMD_DIR"
echo "queued; waiting for verification output..."
LAST=""
for i in $(seq 1 120); do
    sleep 5
    LAST=$(grep -a "SAFEFLASH-VERIFY-DONE" -B3 /tmp/doorbell-out 2>/dev/null | tail -4 || true)
    case "$LAST" in *SAFEFLASH-VERIFY-DONE*) break;; esac
done
echo "$LAST"
GOT=$(printf '%s' "$LAST" | awk '/^[0-9a-f]+ [0-9]+$/ {print; exit}')
if [ "$GOT" = "$EXPECT" ]; then
    echo "SAFE FLASH OK: CRC32/size match"
else
    echo "SAFE FLASH CHECK FAILED: got '$GOT', expected '$EXPECT' — do not reboot blindly"
    exit 1
fi
