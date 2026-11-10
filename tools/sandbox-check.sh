#!/bin/bash
# Boot an image in QEMU and verify that it is usable, before flashing.
#
# usage: sandbox-check.sh <image16M> [expected-marker]
# env: QEMU_BIN (default: qemu-system-mipsel)
set -u
IMG=${1:?image}; MARK=${2:-}
QEMU=${QEMU_BIN:-qemu-system-mipsel}
TMP=/tmp/sbx-check.bin; LOG=/tmp/sbx-check.log
FAIL=0
ok(){ echo "  OK   $*"; }
bad(){ echo "  FAIL $*"; FAIL=$((FAIL+1)); }

echo "== sandbox: $IMG"
command -v "$QEMU" >/dev/null || { echo "QEMU binary not found: $QEMU"; exit 1; }
[ "$(stat -c%s "$IMG")" -eq 16777216 ] || { bad "size is not 16 MiB"; exit 1; }

cp "$IMG" "$TMP"
python3 - "$TMP" <<'PY'
import sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
i = 0
while True:
    j = d.find(b"console=ttyS3", i)
    if j < 0:
        break
    d[j:j+13] = b"console=ttyS1"
    i = j + 1
open(p, "wb").write(bytes(d))
PY

rm -f "$LOG"
timeout 55 "$QEMU" -M ingenic-t31 -m 128M -display none \
  -global ingenic-t31.soc-variant=t31zx \
  -drive file=$TMP,format=raw,if=none,id=flash0 \
  -chardev file,id=s1,path=$LOG -serial null -serial chardev:s1 >/dev/null 2>&1 || true

[ -s "$LOG" ] && ok "boot log captured" || bad "no boot log"
grep -aqE "Linux version|watchdog watchdog0" "$LOG" && ok "kernel started" || bad "no kernel evidence"
grep -aq "Kernel panic" "$LOG" && bad "kernel panic" || ok "no kernel panic"
grep -aq "can't open '/dev/" "$LOG" && bad "missing /dev nodes" || ok "/dev nodes present"
grep -aq "doorbell:" "$LOG" && ok "application started" || bad "application did not start"

if [ -n "$MARK" ]; then
  python3 - "$IMG" "$MARK" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()[0xF20000:0xFE0000]
print("  OK   marker found in /config" if sys.argv[2].encode() in d
      else "  FAIL marker not found in /config")
PY
fi

echo
[ "$FAIL" -eq 0 ] && echo "RESULT: sandbox passed" || echo "RESULT: $FAIL problem(s)"
exit $((FAIL > 0))
