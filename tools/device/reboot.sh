#!/bin/sh
# Reboot the SoC.
# doorbell.out holds /dev/watchdog; the driver is nowayout, so when the holder
# dies the watchdog fires and resets the SoC. That is the only reliable restart
# on this board: the kernel's own restart path hangs (reset type is "null") and
# the TCU WDT register writes do not fire from userspace.
sync
for p in /proc/[0-9]*; do
  [ "$(cat "$p/comm" 2>/dev/null)" = "doorbell.out" ] && kill -9 "${p#/proc/}"
done
# If we are still alive after 5 s, the watchdog did not fire: fall back.
sleep 5
echo b > /proc/sysrq-trigger 2>/dev/null
exit 1
