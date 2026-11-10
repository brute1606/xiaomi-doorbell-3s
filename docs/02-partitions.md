# Flash partitions

## mtdparts (from the kernel command line)

```
256K(boot),352K(tag),2240K(kernel),5056K(rootfs),5056K(rootfs1),
1152K(system),1152K(system1),224K(iq_bak),768K(config),16M@0(all)
```

| mtd | Offset | Size | Name | Content |
|---|---|---|---|---|
| mtd0 | 0x000000 | 256K | boot | SPL + U-Boot |
| mtd1 | 0x040000 | 352K | tag | blocks CMDL/ENVI/BTIF/USR0/FWIF/BIND/SENS/SSET/RISC |
| mtd2 | 0x098000 | 2240K | kernel | uImage (lzop), load address 0x80010000 |
| mtd3 | 0x2C8000 | 5056K | rootfs | **slot A**: `[u32 len][lzop]` → cpio/initramfs |
| mtd4 | 0x7B8000 | 5056K | rootfs1 | **slot B**: same format |
| mtd5 | 0xCA8000 | 1152K | system | squashfs, mounted at `/system` |
| mtd6 | 0xDC8000 | 1152K | system1 | second system slot |
| mtd7 | 0xEE8000 | 224K | iq_bak | ISP/IQ backup |
| mtd8 | 0xF20000 | 768K | config | JFFS2, mounted at `/config` |

`config` is the only writable partition: logs, counters and settings live there.

## BTIF (bootloader partition table)

The tag contains a `BTIF` block (two copies):

```
BTIFkernel=2240K@0x98000 rootfs=5056K@0x2c8000 kernel2=2240K@0x98000 rootfs2=5056K@0x7B8000
```

The kernel is **shared**; there are two rootfs slots (A and B). Slot selection
and fallback are described in [docs/08-ab-slots.md](08-ab-slots.md).

## Tag layout

The tag starts with the magic `09 c3 08 a1` and contains blocks with a 4-byte
key followed by string or binary data. Every block has a **primary and a backup
copy** (offset +0x7000):

| Offset | Key | Content |
|---|---|---|
| 0x41000 / 0x48000 | `SENS` | sensor calibration |
| 0x42000 / 0x49000 | `CMDL` | **kernel command line** (`console=ttyS3,...`) |
| 0x43000 / 0x4A000 | `ENVI` | sensor parameters |
| 0x44000 / 0x4B000 | `BTIF` | partitions for the bootloader |
| 0x45000 / 0x4C000 | `USR0` | serial number, DID, etc. |
| 0x47000 / 0x4E000 | `FWIF`/`VERS`/`BIND` | firmware version, bind flag |
| 0x50000 | `RISC` | RISC-V image (BL616 / sensor) |
| 0x70000 | `SSET` | sensor settings |

**Important:** the tag is a separate partition. Flashing a rootfs does not
touch it. To change the `cmdline` (for example, to move the console to UART1)
the tag must be written **with its own layout** — see
[docs/06-uart-console.md](06-uart-console.md).
