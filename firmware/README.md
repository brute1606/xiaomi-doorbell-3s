# Firmware releases

Binary images are published as **GitHub Releases** assets, not committed to the
repository. Each release contains:

- `rootfs-region-<version>.bin` — 5 177 344 bytes, the rootfs region
  (`length + lzop + padding`), ready for OTA or for a direct slot write;
- `image-<version>.bin.zst` — optional full 16 MiB image (bootloader, tag,
  kernel included), compressed;
- `SHA256SUMS` — checksums for all assets;
- release notes: what changed, which device revision it was tested on, known
  issues and the rollback command.

## What is inside (and what is not)

Release assets contain **only the rootfs region**: system software, no Wi-Fi
credentials, no serial numbers, no calibration. Full 16 MiB images are never
published — build one from your own dump (see `docs/05-flashing.md`).

## Installation

See [docs/05-flashing.md](../docs/05-flashing.md) for the clip/flashrom method
and [docs/09-ota.md](../docs/09-ota.md) for over-the-air updates.

## Important

- Images are built from a dump of a specific device revision. Verify the flash
  chip and partition layout on your unit before flashing.
- Always keep a full dump of your own device; it is the only reliable way back.
