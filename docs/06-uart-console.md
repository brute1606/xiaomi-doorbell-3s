# UART console

## Wiring

- Pad **A** = UART1 (bootloader and kernel console), **3.3 V**, 115200 8N1.
- Adapter `RXD → pad A`, adapter `GND → board GND`.
- The board must be powered for the console to work.

On power-up you should see the bootloader banner:

```
Ver:20220831-Turret
Build:Jan 10 2025 17:23:49
```

## Enabling the kernel console

By default the kernel console is `ttyS3`, which is not routed to pad A, and
`quiet` suppresses most messages. Patch the `CMDL` block in the tag:

- `console=ttyS3` → `console=ttyS1` (same length);
- remove `quiet` (replace its 5 bytes with spaces).

Patch both the primary (`0x42004`) and backup (`0x49004`) copies, then flash the
tag partition:

```bash
sudo flashrom -p ch341a_spi -l tag.layout -i tag -w image.bin
```

**This is easy to forget:** flashing only `-i rootfs -i rootfs1` does not touch
the tag, so the console change will not take effect.

## Shell on the console

The stock `/etc/inittab` starts a getty on the console:

```
console::respawn:/sbin/getty -L console 115200 vt100
```

For a root shell without login, replace it with:

```
console::respawn:/bin/sh -i
```

The prompt looks like `~ #`. Note that when the SoC is allowed to sleep the
shell dies with the SoC; keep the device awake for an interactive session (see
[docs/03-firmware-format.md](03-firmware-format.md)).

## Capturing logs

```bash
stty -F /dev/ttyUSB0 115200 cs8 -cstopb -parenb raw -echo
cat /dev/ttyUSB0 | tee boot.log
```

Check the capture: `grep -c "Ver:" boot.log` shows how many times the device
booted during the capture.
