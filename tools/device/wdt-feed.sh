#!/bin/sh
# Watchdog feeder/owner for images without the vendor application.
# Feeds while /tmp/keepalive is fresh; when stale — or when the file was never
# created within WDT_GRACE seconds after start — stops feeding so the hardware
# watchdog resets the SoC (rollback actuator).
GRACE=${WDT_GRACE:-120}
echo $$ > /tmp/wdt-feed.pid
if ! exec 3>/dev/watchdog 2>/dev/null; then
  echo "WDTFEED: cannot open /dev/watchdog (held?), exiting" > /dev/console
  exit 1
fi
start=$(cat /proc/uptime); start=${start%%.*}
echo "WDTFEED: started pid=$$ grace=${GRACE}s" > /dev/console
while true; do
  now=$(cat /proc/uptime); now=${now%%.*}
  ka=$(cat /tmp/keepalive 2>/dev/null)
  case "$ka" in ''|*[!0-9]*) ka=0 ;; esac
  if [ "$ka" -gt 0 ]; then
    stale=$((now - ka))
  else
    stale=$((now - start))
  fi
  if [ "$stale" -gt "$GRACE" ]; then
    echo "WDTFEED: keepalive stale (${stale}s > ${GRACE}s), stop feeding" > /dev/console
    sleep 3600
  fi
  printf '\0' >&3 2>/dev/null
  sleep 1
done
