#!/bin/sh
# Continuous log shipper: sends the new bytes of the app logs to the hub.
# A separate background process, so the command channel is never affected.
. /etc/net.env 2>/dev/null
HUB=${HUB:-192.0.2.10}
PORT=${LOG_PORT:-2234}
INTERVAL=3
MAXCHUNK=16000
send() {  # $1 = file, $2 = offset file
  [ -f "$1" ] || return 0
  sz=$(stat -c%s "$1" 2>/dev/null)
  [ -z "$sz" ] && return 0
  off=$(cat "$2" 2>/dev/null)
  if [ -z "$off" ]; then
    off=$((sz > MAXCHUNK ? sz - MAXCHUNK : 0))
  fi
  [ "$sz" -le "$off" ] && return 0
  n=$((sz - off))
  if [ "$n" -gt "$MAXCHUNK" ]; then
    off=$((sz - MAXCHUNK)); n=$MAXCHUNK
  fi
  { echo "=== $(date '+%Y-%m-%d %H:%M:%S') $1 +$n from $off"
    dd if="$1" bs=1 skip=$off count=$n 2>/dev/null
    echo; } >> /tmp/chunk 2>&1
  echo "$sz" > "$2"
}
while true; do
  : > /tmp/chunk
  send /tmp/error_m3s.log /tmp/off_err
  send /tmp/m3s.log /tmp/off_m3s
  send /tmp/doorbeld.log /tmp/off_doorbeld
  send /config/guard.log /tmp/off_guard
  send /tmp/poller.log /tmp/off_poller
  send /config/rcs.log /tmp/off_rcs
  if [ -s /tmp/chunk ]; then
    /bin/nc -w 4 "$HUB" "$PORT" < /tmp/chunk 2>/dev/null &
    p=$!
    sleep 5
    kill -9 "$p" 2>/dev/null
    wait "$p" 2>/dev/null
  fi
  sleep $INTERVAL
done
