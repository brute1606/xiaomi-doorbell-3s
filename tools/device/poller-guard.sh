#!/bin/sh
# Supervisor: keep poller.sh alive AND restart it if it stops writing heartbeat.
while true; do
  p=$(cat /tmp/poller.pid 2>/dev/null)
  ok=1
  if [ -z "$p" ] || ! kill -0 "$p" 2>/dev/null; then ok=0; fi
  hb=$(stat -c %Y /tmp/poller.alive 2>/dev/null)
  now=$(date +%s)
  if [ -z "$hb" ] || [ $((now - hb)) -gt 90 ]; then ok=0; fi
  if [ $ok -eq 0 ]; then
    [ -n "$p" ] && kill -9 "$p" 2>/dev/null
    /usr/bin/poller.sh >/dev/null 2>&1 &
    echo $! > /tmp/poller.pid
    echo "GUARD started poller $(cat /proc/uptime)" > /dev/console
  fi
  sleep 10
done
