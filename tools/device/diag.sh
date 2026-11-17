#!/bin/sh
# Persistent boot diagnostics: write interface/process state to /config.
i=0
while [ $i -lt 40 ]; do
  { echo "=== diag $(date '+%F %T') up=$(cat /proc/uptime)"
    ps 2>/dev/null
    ifconfig -a 2>/dev/null
    route -n 2>/dev/null
  } >> /config/diag.log 2>&1
  sz=$(stat -c %s /config/diag.log 2>/dev/null)
  [ -n "$sz" ] && [ "$sz" -gt 300000 ] && : > /config/diag.log
  i=$((i+1)); sleep 15
done
