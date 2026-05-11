#!/usr/bin/env bash
set -u

BASE=/var/lib/spot-lifecycle
LOG="$BASE/last-shutdown.log"
STATE="$BASE/state.json"
mkdir -p "$BASE"
exec >> "$LOG" 2>&1

START_TS="$(date -Is)"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
INSTANCE_ID="$(curl -fsS -m 1 -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/id 2>/dev/null || true)"
INSTANCE_NAME="$(curl -fsS -m 1 -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name 2>/dev/null || hostname)"
ZONE="$(curl -fsS -m 1 -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone 2>/dev/null || true)"
PREEMPTED="$(curl -fsS -m 1 -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/preempted 2>/dev/null || true)"

echo "[$START_TS] spot shutdown started instance=$INSTANCE_NAME preempted=$PREEMPTED"

cat > "$STATE" <<JSON
{
  "status": "preempting_or_shutdown",
  "started_at": "$START_TS",
  "boot_id": "$BOOT_ID",
  "instance_id": "$INSTANCE_ID",
  "instance_name": "$INSTANCE_NAME",
  "zone": "$ZONE",
  "preempted": "$PREEMPTED",
  "notify_pending": true,
  "recover_notify_pending": true
}
JSON
sync "$STATE" 2>/dev/null || sync || true

/opt/spot-lifecycle/notify.sh "⚠️ GCP Spot/实例即将停机：$INSTANCE_NAME，开始保存数据" warning >/tmp/spot-notify-preempt.log 2>&1 &

SNAP="$BASE/preempt-snapshot-$(date +%Y%m%d-%H%M%S).txt"
{
  echo "--- metadata ---"
  echo "instance=$INSTANCE_NAME"
  echo "instance_id=$INSTANCE_ID"
  echo "zone=$ZONE"
  echo "preempted=$PREEMPTED"
  echo "boot_id=$BOOT_ID"
  echo "--- date ---"
  date -Is
  echo "--- uptime ---"
  uptime || true
  echo "--- disk ---"
  df -h / /opt /var/lib 2>/dev/null || true
  echo "--- memory ---"
  free -h || true
  echo "--- docker ps ---"
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
  echo "--- docker restart policies ---"
  docker inspect --format '{{.Name}} restart={{.HostConfig.RestartPolicy.Name}} status={{.State.Status}}' $(docker ps -aq) 2>/dev/null || true
  echo "--- failed units ---"
  systemctl --failed --no-pager || true
  echo "--- key service status ---"
  systemctl --no-pager --plain status docker nginx hermesclaw proxy-stack-sync-watch 2>/dev/null || true
} > "$SNAP" 2>&1
cp -f "$SNAP" "$BASE/preempt-snapshot-latest.txt" || true
sync "$SNAP" "$BASE/preempt-snapshot-latest.txt" 2>/dev/null || sync || true

# Fast config/auth sync. Never let it consume the 30s window.
timeout 6 /usr/local/bin/proxy-stack sync-fast || true

# Stop business containers first, persistence containers last. Bound total time.
timeout 22 docker stop -t 12 \
  autoteam-autoteam-1 \
  cliproxyapi \
  cpa-manager \
  sub2api-proxy \
  sub2api \
  sub2api-postgres \
  sub2api-redis || true

date -Is > "$BASE/shutdown-finished-at"
sync || true

/opt/spot-lifecycle/notify.sh "✅ Spot 停机前保存动作已完成：$INSTANCE_NAME" info >/tmp/spot-notify-saved.log 2>&1 &

echo "[$(date -Is)] spot shutdown finished"
exit 0
