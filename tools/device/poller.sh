#!/bin/sh
# Poller. Keeps the Linux side of the Wi-Fi interface configured and never
# lets a hung nc or a hung command block the channel: both are run in the
# background and killed by a timer. It also writes a heartbeat file so that
# poller-guard can restart a hung instance.
. /etc/net.env 2>/dev/null
HUB=${HUB:-192.0.2.10}
CMD_PORT=${CMD_PORT:-2231}
OUT_PORT=${OUT_PORT:-2232}
CMD_TIMEOUT=20
NC_TIMEOUT=6
IP=${STATIC_IP:-192.0.2.20}
MASK=${STATIC_MASK:-255.255.255.0}
GW=${STATIC_GW:-192.0.2.1}
ensure_net() {
  s=$(ifconfig bleth0 2>/dev/null)
  case "$s" in
    *"inet addr:$IP"*) return 0 ;;
  esac
  ifconfig bleth0 "$IP" netmask "$MASK" up 2>/dev/null
  route del default gw "$GW" 2>/dev/null
  route add default gw "$GW" 2>/dev/null
  echo "NETFIX $IP $(cat /proc/uptime)" > /dev/console
}
run_with_timeout() {  # $1 = max seconds, rest = command; output already redirected
  _t=$1
  shift
  "$@" &
  _p=$!
  _i=0
  while [ "$_i" -lt "$_t" ] && kill -0 "$_p" 2>/dev/null; do
    sleep 1
    _i=$((_i+1))
  done
  kill -9 "$_p" 2>/dev/null
  wait "$_p" 2>/dev/null
}
echo "POLLER start $(cat /proc/uptime)" > /dev/console
while true; do
  echo "$(cat /proc/uptime)" > /tmp/poller.alive
  ensure_net
  run_with_timeout $NC_TIMEOUT /bin/nc -d -w 4 "$HUB" "$CMD_PORT" > /tmp/c 2>/tmp/cerr
  if [ -s /tmp/c ]; then
    echo "POLL cmd $(cat /proc/uptime)" > /dev/console
    TMO=$CMD_TIMEOUT
    case "$(dd if=/tmp/c bs=1 count=32 2>/dev/null)" in
      *"#LONG"*) TMO=300 ;;
    esac
    run_with_timeout $TMO /bin/sh /tmp/c > /tmp/o 2>&1
    /bin/nc -w 4 "$HUB" "$OUT_PORT" < /tmp/o 2>/dev/null &
    upid=$!
    sleep $NC_TIMEOUT
    kill -9 "$upid" 2>/dev/null
    wait "$upid" 2>/dev/null
  fi
  sleep 15
done
