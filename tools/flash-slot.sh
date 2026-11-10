#!/bin/bash
# Flash a single rootfs slot (or both) on a device attached to a CH341A.
#
# usage: flash-slot.sh <rootfs|rootfs1|both> <image.bin>
set -eu
REGION=${1:?rootfs|rootfs1|both}; IMG=${2:?image}

case "$REGION" in
  rootfs)  LAY="002c8000:007b7fff rootfs" ;;
  rootfs1) LAY="007b8000:00ca7fff rootfs1" ;;
  both)    LAY=$'002c8000:007b7fff rootfs\n007b8000:00ca7fff rootfs1' ;;
  *) echo "usage: $0 rootfs|rootfs1|both <image>"; exit 1 ;;
esac

printf '%s\n' "$LAY" > /tmp/flash.layout
case "$REGION" in
  rootfs)  SEL="-i rootfs" ;;
  rootfs1) SEL="-i rootfs1" ;;
  both)    SEL="-i rootfs -i rootfs1" ;;
esac

sudo modprobe -r spi_ch341 2>/dev/null || true
sudo modprobe -r ch341 2>/dev/null || true
sudo flashrom -p ch341a_spi -l /tmp/flash.layout $SEL -w "$IMG" | tail -3
sudo flashrom -p ch341a_spi -l /tmp/flash.layout $SEL -v "$IMG" | grep -E "VERIFIED|FAILED"
