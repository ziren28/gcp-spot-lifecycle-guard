#!/usr/bin/env bash
set -u

BASE=/var/lib/spot-lifecycle
LOG="$BASE/cleanup.log"
mkdir -p "$BASE"
exec >> "$LOG" 2>&1

echo "[$(date -Is)] cleanup started"

# Keep lifecycle state/recovery files compact: 14 days for logs/snapshots, 30 days for recovered markers.
find "$BASE" -type f \( -name '*.log' -o -name '*snapshot*.txt' -o -name 'post-boot-health*.txt' \) -mtime +14 -print -delete 2>/dev/null || true
find "$BASE" -type f -name 'recovered-*.json' -mtime +30 -print -delete 2>/dev/null || true
find "$BASE" -type f -name 'preempt-snapshot-*.txt' -mtime +14 -print -delete 2>/dev/null || true

# Docker garbage cleanup: safe/pruned only, preserves named volumes. Use a short timeout.
if command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker; then
  echo "docker system df before"
  docker system df || true
  timeout 60 docker container prune -f || true
  timeout 60 docker image prune -f || true
  timeout 60 docker builder prune -f --filter 'until=168h' || true
  echo "docker system df after"
  docker system df || true
fi

# Journal vacuum. Keep enough history for debugging.
if command -v journalctl >/dev/null 2>&1; then
  journalctl --vacuum-time=14d || true
fi

# Apt cache cleanup, non-fatal.
if command -v apt-get >/dev/null 2>&1; then
  apt-get clean || true
fi

df -h / || true
echo "[$(date -Is)] cleanup finished"
