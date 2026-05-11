#!/usr/bin/env bash
set -u
LOG=/var/lib/spot-lifecycle/preemption-watch.log
mkdir -p /var/lib/spot-lifecycle
exec >> "$LOG" 2>&1

echo "[$(date -Is)] preemption watcher started"
triggered=0
while true; do
  preempted="$(curl -fsS -m 1 -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/preempted 2>/dev/null || echo UNKNOWN)"
  if [ "$preempted" = "TRUE" ]; then
    echo "[$(date -Is)] metadata preempted=TRUE; invoking shutdown handler"
    if [ "$triggered" -eq 0 ]; then
      triggered=1
      /opt/spot-lifecycle/shutdown.sh || true
    fi
    sleep 1
  else
    sleep 2
  fi
done
