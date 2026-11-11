#!/bin/sh
# Control channel poller.
# Reads its endpoint from /config/net.env:
#   HUB=192.0.2.10  CMD_PORT=2231  OUT_PORT=2232
#   STATIC_IP=192.0.2.20  STATIC_MASK=255.255.255.0  STATIC_GW=192.0.2.1
# Without STATIC_IP the vendor network setup is used as-is.
CONF=/config/net.env
[ -f "$CONF" ] || CONF=/etc/net.env
[ -f "$CONF" ] && . "$CONF"
HUB=${HUB:-192.0.2.10}
CMD_PORT=${CMD_PORT:-2231}
OUT_PORT=${OUT_PORT:-2232}
STATIC_IP=${STATIC_IP:-}
STATIC_MASK=${STATIC_MASK:-255.255.255.0}
STATIC_GW=${STATIC_GW:-}
CMD_TIMEOUT=20
NC_TIMEOUT=6
ensure_net() {
  [ -n "$STATIC_IP" ] || return 0
  s=$(ifconfig bleth0 2>/dev/null)
  case "$s" in
    *"inet addr"*) return 0 ;;
    *)
      ifconfig bleth0 "$STATIC_IP" netmask "$STATIC_MASK" up 2>/dev/null
      [ -n "$STATIC_GW" ] && route add default gw "$STATIC_GW" 2>/dev/null
      echo "NETFIX re-applied $(cat /proc/uptime)" > /dev/console ;;
  esac
}
run_with_timeout() {
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
  ensure_net
  run_with_timeout $NC_TIMEOUT /bin/nc -d -w 4 "$HUB" "$CMD_PORT" > /tmp/c 2>/tmp/cerr
  if [ -s /tmp/c ]; then
    echo "POLL cmd $(cat /proc/uptime)" > /dev/console
    TMO=$CMD_TIMEOUT
    case "$(dd if=/tmp/c bs=1 count=32 2>/dev/null)" in
      *"#LONG"*) TMO=300 ;;
    esac
    run_with_timeout $TMO /bin/sh /tmp/c > /tmp/o 2>&1
    # Upload must be its own background command: a job started from inside a
    # function gets stdin=/dev/null and would send nothing.
    /bin/nc -w 4 "$HUB" "$OUT_PORT" < /tmp/o 2>/dev/null &
    upid=$!
    sleep $NC_TIMEOUT
    kill -9 "$upid" 2>/dev/null
    wait "$upid" 2>/dev/null
  else
    echo "POLL $(cat /proc/uptime) empty err=$(cat /tmp/cerr 2>/dev/null)" > /dev/console
  fi
  sleep 15
done
