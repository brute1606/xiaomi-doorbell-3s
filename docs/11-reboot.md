# Rebooting the device

## Why plain `reboot` does not work

The kernel's restart handler needs a reset method. On this device the default
method is `null`, so `reboot`, `echo b > /proc/sysrq-trigger` and `kill -TERM 1`
all terminate userspace but never reset the SoC — the device stays up with a
half-dead system until the power is cycled.

The TCU watchdog registers are no help either: writing `TCSR`/`TDR`/`TCER`
directly (with RTC, PCK or EXT clock sources) does not reset the board, and
writing `wdt` to `/proc/jz/reset/reset` blocks the writing process forever.

## What works: drop the watchdog holder

`/dev/watchdog` is held by the vendor application (`doorbell.out`), and the
driver is built with `nowayout`, so the hardware watchdog keeps running when
the holder dies. Killing the holder therefore resets the SoC.

```sh
#!/bin/sh
# /usr/bin/reboot.sh
sync
for p in /proc/[0-9]*; do
    [ "$(cat "$p/comm" 2>/dev/null)" = "doorbell.out" ] && kill -9 "${p#/proc/}"
done
# fallback for environments where the watchdog does not fire
sleep 5
echo b > /proc/sysrq-trigger
```

Observed timings on the device: ping drops about 13 s after the call, the
bootloader banner and a new kernel appear on the UART, and the control channel
is back within ~20 s.

## Emulation caveat

In QEMU the watchdog reset is suppressed by the model (for stock-firmware
debugging), while `sysrq-b` does reset the machine. So in the sandbox this
script appears to work through the fallback path; on real hardware only the
watchdog path works. Both paths should be kept.
