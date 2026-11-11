#!/bin/sh
# Service mode: UART console or USB CDC-ACM gadget, on demand only.
# Flags live in /tmp (RAM): a reboot always clears them.
# usage: service.sh uart|usb|off|status [minutes]
MIN_DEFAULT=15
PID_UART=/tmp/svc_uart.pid
PID_USB=/tmp/svc_usb.pid
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> /config/service.log; }
timer() { ( sleep $(( $2 * 60 )); kill "$(cat "$1" 2>/dev/null)" 2>/dev/null; rm -f "$1"; log "auto-off $1" ) & }

usb_gadget() {
  : > /config/usb.log
  for m in udc-core usb-common dwc2 libcomposite u_serial usb_f_acm g_serial; do
    ko=/lib/modules/$m.ko
    [ -f "$ko" ] || ko=/system/lib/modules/$m.ko
    if [ -f "$ko" ]; then
      err=$(insmod "$ko" 2>&1)
      echo "$m: ${err:-ok}" >> /config/usb.log
    else
      echo "$m: missing" >> /config/usb.log
    fi
  done
  sleep 1
  [ -c /dev/ttyGS0 ] || { mdev -s 2>/dev/null; sleep 1; }
  [ -c /dev/ttyGS0 ]
}

case "${1:-}" in
  uart)
    MIN=${2:-$MIN_DEFAULT}
    [ -f "$PID_UART" ] && { echo "uart already on"; exit 0; }
    ( exec /bin/sh -i < /dev/ttyS1 > /dev/ttyS1 2>&1 ) &
    echo $! > "$PID_UART"
    timer "$PID_UART" "$MIN"
    log "uart on ${MIN}min pid=$(cat "$PID_UART")"
    echo "uart on for ${MIN} min"
    ;;
  usb)
    MIN=${2:-$MIN_DEFAULT}
    [ -f "$PID_USB" ] && { echo "usb already on"; exit 0; }
    if ! usb_gadget; then
      log "usb FAIL: no /dev/ttyGS0"
      echo "usb FAIL: no /dev/ttyGS0"
      cat /config/usb.log 2>/dev/null
      exit 1
    fi
    ( exec /bin/sh -i < /dev/ttyGS0 > /dev/ttyGS0 2>&1 ) &
    echo $! > "$PID_USB"
    timer "$PID_USB" "$MIN"
    log "usb on ${MIN}min pid=$(cat "$PID_USB")"
    echo "usb on for ${MIN} min"
    ;;
  off)
    for f in "$PID_UART" "$PID_USB"; do
      [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null && rm -f "$f"
    done
    log "service off (manual)"
    echo off
    ;;
  status)
    [ -f "$PID_UART" ] && echo "uart: on" || echo "uart: off"
    [ -f "$PID_USB" ] && echo "usb: on" || echo "usb: off"
    ;;
  *) echo "usage: $0 uart|usb|off|status [minutes]" ;;
esac
