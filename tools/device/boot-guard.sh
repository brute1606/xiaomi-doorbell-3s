#!/bin/sh
# Boot guard v3 (v98b): attempt counter, health check, rollback, diagnostics.
LOG=/config/guard.log
CNT=/config/boot_fail_count
INPROG=/config/attempt_in_progress
TRIAL=/config/trial
HEALTH_WINDOW=${HEALTH_WINDOW:-600}
STEP=5
MAX_FAILS=${MAX_FAILS:-3}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; echo "BOOTGUARD $*" > /dev/console; }

region_valid() {
  b=$(dd if="$1" bs=4 count=1 2>/dev/null)
  ff=$(printf '\377\377\377\377')
  case "$b" in "$ff") return 1 ;; esac
  return 0
}
slot_name() { if region_valid /dev/mtd3ro; then echo A; else echo B; fi; }

count() {
  n=$(cat "$CNT" 2>/dev/null); case "$n" in ''|*[!0-9]*) n=0 ;; esac
  prev=$(cat "$INPROG" 2>/dev/null)
  if [ -n "$prev" ]; then n=$((n+1)); log "previous boot did not finish (was: $prev), failures=$n"; fi
  [ "$n" -gt 100 ] && n=100
  echo "$n" > "$CNT"
  echo "boot $(cat /proc/uptime)" > "$INPROG"
  sync
  log "boot attempt failures=$n of $MAX_FAILS (ver=$(cat /tmp/version 2>/dev/null) slot=$(slot_name))"
}

actuator() {
  p=$(cat /tmp/wdt-feed.pid 2>/dev/null)
  if [ -n "$p" ] && [ -d "/proc/$p" ]; then kill -9 "$p" 2>/dev/null; fi
  for q in /proc/[0-9]*; do
    c=$(cat "$q/comm" 2>/dev/null)
    if [ "$c" = "doorbell.out" ]; then log "actuator: kill watchdog holder ${q#/proc/}"; kill -9 "${q#/proc/}" 2>/dev/null; fi
  done
  sync; sleep 3
}

diag() {
  {
    echo "=== diag $* $(date '+%F %T') up=$(cat /proc/uptime)"
    ps 2>/dev/null
    ifconfig -a 2>/dev/null
    route -n 2>/dev/null
    cat /proc/net/dev 2>/dev/null
  } >> /config/diag.log 2>&1
  sz=$(stat -c %s /config/diag.log 2>/dev/null)
  [ -n "$sz" ] && [ "$sz" -gt 300000 ] && { : > /config/diag.log; }
}

healthy() {
  s=$(ifconfig bleth0 2>/dev/null)
  case "$s" in *"inet addr"*) ;; *) return 1 ;; esac
  r=$(route -n 2>/dev/null)
  case "$r" in *"0.0.0.0"*) ;; *) return 1 ;; esac
  . /etc/net.env 2>/dev/null
  hub=${HUB:-192.0.2.10}; lp=${LOG_PORT:-2234}
  /bin/nc -w 3 "$hub" "$lp" >/dev/null 2>&1
  return $?
}

do_health() {
  i=0
  while [ $i -lt $((HEALTH_WINDOW / STEP)) ]; do
    now=$(cat /proc/uptime); now=${now%%.*}
    echo "$now" > /tmp/keepalive
    if healthy; then
      echo 0 > "$CNT"; rm -f "$INPROG"
      echo "ok $(cat /tmp/version 2>/dev/null) $(cat /proc/uptime)" > /config/boot_ok
      log "healthy (ver=$(cat /tmp/version 2>/dev/null) slot=$(slot_name)), counter reset"
      return 0
    fi
    [ $((i % 12)) -eq 0 ] && diag "health-check"
    sleep $STEP; i=$((i+1))
  done
  n=$(cat "$CNT" 2>/dev/null); case "$n" in ''|*[!0-9]*) n=0 ;; esac
  slot=$(slot_name)
  diag "unhealthy"
  log "UNHEALTHY after ${HEALTH_WINDOW}s (ver=$(cat /tmp/version 2>/dev/null) slot=$slot failures=$n)"
  if [ "$slot" = "B" ]; then log "on fallback B: staying put"; return 1; fi
  if [ -f "$TRIAL" ]; then log "trial mode: immediate rollback"; n=$MAX_FAILS; fi
  if [ "$n" -ge "$MAX_FAILS" ]; then
    if region_valid /dev/mtd4ro; then
      log "rollback: invalidating slot A, fallback B is valid"
      flash_eraseall /dev/mtd3 >/dev/null 2>&1
      log "slot A erasure rc=$?"
      sync; actuator
    else
      log "rollback aborted: fallback B is NOT valid"
    fi
    return 1
  fi
  log "retrying: reboot to attempt $((n+1))"
  actuator
}

case "$1" in
  count) count ;;
  health) do_health ;;
  slot) slot_name ;;
  diag) diag manual ;;
  *) echo "usage: $0 count|health|slot|diag" >&2; exit 2 ;;
esac
