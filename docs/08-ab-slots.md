# A/B slots and rollback

## Layout

From the bootloader partition table (`BTIF` block in the tag):

```
kernel  = 2240K@0x98000    rootfs  = 5056K@0x2c8000   (slot A)
kernel2 = 2240K@0x98000    rootfs2 = 5056K@0x7B8000   (slot B)
```

The kernel is shared between the slots; only the rootfs is duplicated. The
`system` partition also has a second copy (`system1`).

## What the bootloader supports

Strings in the boot area (`0x0..0x40000`) show an A/B-aware loader:

- `os2_flag=1` — booting the second OS image;
- `rootfs error:%d`, `try rootfs2`, `try kernel2` — fallback to slot B;
- `boot error, goto normal boot`;
- `Invalid bootinfo, try backup` / `Invalid bootinfo and backup` — a backup copy
  of the boot info exists;
- `tag error:%d`.

So there is a two-slot boot with fallback: if the primary rootfs cannot be read
or unpacked, the loader tries the second one.

## Open questions

- How exactly the active slot is chosen: a persistent flag in the boot info, or
  a fallback that always prefers slot A and switches to B only on error.
- Whether the choice alternates between boots.
- No boot counter (`bootcount`) has been found in the bootloader.

## Experiment plan

The current state of a test device was `A = B = v60`. To settle the questions:

1. Flash a **different** image into slot B only, keep slot A as is. Boot and
   watch the UART console to see which image runs.
2. Power-cycle again and see whether the loader switches slots by itself.
3. Write an invalid image into slot A, keep a valid one in B, and boot: if the
   device still boots, the fallback to slot B works.

Tools: `tools/flash-slot.sh rootfs|rootfs1 <image>`.

## Consequences for OTA

- Writing **both** slots is safe against a partially written partition, but it
  removes the A/B safety net (there is no older image left to fall back to).
- Writing **one inactive slot** and letting the loader switch preserves
  rollback — but only once the slot-switch mechanism is understood.
