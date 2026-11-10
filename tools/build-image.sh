#!/bin/bash
# Assemble a 16 MiB flash image by writing a rootfs region into a stock dump.
#
# usage: build-image.sh <stock.bin> <rootfs_region.bin> <out.bin> [slot]
#   slot: both (default) | a | b
set -eu
STOCK=${1:?stock dump}; REGION=${2:?rootfs region}; OUT=${3:?output image}; SLOT=${4:-both}

[ "$(stat -c%s "$STOCK")" -eq 16777216 ] || { echo "stock dump must be 16 MiB"; exit 1; }
[ "$(stat -c%s "$REGION")" -eq 5177344 ] || { echo "rootfs region must be 5177344 bytes"; exit 1; }

python3 - "$STOCK" "$REGION" "$OUT" "$SLOT" <<'PY'
import sys
stock, region, out, slot = sys.argv[1:5]
d = bytearray(open(stock, "rb").read())
r = open(region, "rb").read()
if slot in ("both", "a"):
    d[0x2C8000:0x2C8000 + len(r)] = r
if slot in ("both", "b"):
    d[0x7B8000:0x7B8000 + len(r)] = r
open(out, "wb").write(bytes(d))
PY
sha256sum "$OUT"
