#!/bin/sh
# One-shot trial runner: /config/trial contains a shell command to execute once.
# Guards are already up; the guard health check will trigger a rollback if the
# trial breaks the system. The trial file is removed so it never loops.
[ -f /config/trial ] || exit 0
CMD=$(cat /config/trial 2>/dev/null)
[ -n "$CMD" ] || { rm -f /config/trial; exit 0; }
echo "trial start $(date '+%F %T'): $CMD" > /config/trial_status
sh -c "$CMD" > /config/trial_out 2>&1 &
P=$!
i=0
while [ $i -lt 300 ]; do
  kill -0 "$P" 2>/dev/null || break
  sleep 1
  i=$((i+1))
done
if kill -0 "$P" 2>/dev/null; then
  kill -9 "$P" 2>/dev/null
  echo "timeout 300s" >> /config/trial_status
  echo "trial TIMEOUT" > /dev/console
else
  echo "finished" >> /config/trial_status
  echo "trial finished" > /dev/console
fi
rm -f /config/trial
sync
