# QEMU sandbox

Before flashing, boot the image in QEMU. It catches most mistakes cheaply:
missing `/dev` nodes, a broken cpio, a wrong compression, a crashing
application.

## QEMU fork

Use the Ingenic fork of QEMU (for example `gtxaspec/qemu`, release
`ingenic-0.7.11`). The T31 machine is `ingenic-t31`; select the T31ZX variant:

```bash
qemu-system-mipsel -M ingenic-t31 -m 128M -display none \
  -global ingenic-t31.soc-variant=t31zx \
  -drive file=image.bin,format=raw,if=none,id=flash0 \
  -serial null -serial chardev:s1
```

## Console in the sandbox

The sandbox itself starts with `console=ttyS3`, so to see anything patch a copy
of the image to `console=ttyS1` first — exactly what `tools/sandbox-check.sh`
does:

```bash
./tools/sandbox-check.sh image.bin <expected-marker>
```

It checks:

- the boot log is non-empty;
- the kernel starts and there is no `Kernel panic`;
- there are no `can't open '/dev/...'` errors (device nodes are present);
- the application starts (`doorbell:` appears in the log);
- optionally, `<expected-marker>` is found in the `/config` area of the image.

## Warnings

- QEMU does not emulate the BL616 Wi-Fi chip or the power MCU, so networking
  and sleep behaviour cannot be tested there.
- The QEMU watchdog model may reset the machine; the fork used for this project
  suppresses that reset so a single boot can be observed.
- The sandbox is a pre-flight check, not a guarantee: test on hardware too.
