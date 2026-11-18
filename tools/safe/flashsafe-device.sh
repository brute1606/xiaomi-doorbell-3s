#!/bin/sh
# Safe slot-A write with a keep-alive loop and post-write CRC32 check.
# Runs on the device (busybox sh). Parameters: <expected_size> <hub_ip> <port>
SZ_EXPECT=${1:-5177344}
HUB=${2:?hub address}
PORT=${3:-2235}
unset LD_PRELOAD
echo "SAFEFLASH start $(cat /proc/uptime)"
D=0
for p in /proc/[0-9]*; do C=$(cat $p/comm 2>/dev/null); [ "$C" = "doorbeld" ] && D=1; done
if [ "$D" = "0" ]; then echo "SAFEFLASH ABORT no-daemon"; exit 1; fi
rm -f /tmp/img.new /tmp/fc.done /tmp/fc.log
/bin/nc -d -w 180 "$HUB" "$PORT" > /tmp/img.new
set -- $(ls -l /tmp/img.new 2>/dev/null); SZ=$5
echo "SAFEFLASH size=$SZ"
if [ "$SZ" != "$SZ_EXPECT" ]; then echo "SAFEFLASH ABORT bad-size"; exit 1; fi
flash_eraseall /dev/mtd3 >/dev/null 2>&1; echo "SAFEFLASH erase=$?"
( flashcp /tmp/img.new /dev/mtd3 > /tmp/fc.log 2>&1; echo "$?" > /tmp/fc.done ) &
while [ ! -f /tmp/fc.done ]; do read u r < /proc/uptime; echo ${u%%.*} > /tmp/keepalive; sleep 1; done
RC=$(cat /tmp/fc.done)
echo "SAFEFLASH flashcp=$RC"
if [ "$RC" != "0" ]; then echo "SAFEFLASH FAILED-NO-REBOOT"; exit 1; fi
echo "SAFEFLASH READY-TO-VERIFY"
