#!/bin/sh
# OTA: download the rootfs region from the hub and write both slots.
# usage: ota.sh [reboot]
CONF=/config/net.env
[ -f "$CONF" ] || CONF=/etc/net.env
[ -f "$CONF" ] && . "$CONF"
H=${HUB:-192.0.2.10}
P=${OTA_PORT:-2233}
EXPECT=5177344
IMG=/tmp/ota.img
say() { echo "$*"; echo "$*" >> /tmp/ota.log; }
: > /tmp/ota.log
say "ota start $(cat /proc/uptime)"
/bin/nc -d -w 240 "$H" "$P" > $IMG 2>/dev/null
sz=$(stat -c%s $IMG 2>/dev/null)
if [ "$sz" != "$EXPECT" ]; then say "ota FAIL size=$sz"; exit 1; fi
say "ota got $sz"
flash_eraseall /dev/mtd4 >/dev/null 2>&1
if ! flashcp $IMG /dev/mtd4; then say "ota FAIL mtd4"; exit 1; fi
flash_eraseall /dev/mtd3 >/dev/null 2>&1
if ! flashcp $IMG /dev/mtd3; then say "ota FAIL mtd3 (slot B valid)"; exit 1; fi
say "ota done $(cat /proc/uptime)"
if [ "${1:-}" = reboot ]; then say "ota rebooting"; /usr/bin/reboot.sh; fi
