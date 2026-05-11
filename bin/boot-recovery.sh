#!/usr/bin/env bash
set -u

BASE=/var/lib/spot-lifecycle
LOG="$BASE/last-boot-recovery.log"
STATE="$BASE/state.json"
mkdir -p "$BASE"
exec >> "$LOG" 2>&1

echo "[$(date -Is)] boot recovery started"

if [ ! -f "$STATE" ]; then
  echo "no previous lifecycle state, skip"
  exit 0
fi

INSTANCE_NAME="$(curl -fsS -m 2 -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/name 2>/dev/null || hostname)"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"

# Notify early that the replacement/new boot is alive; non-blocking.
/opt/spot-lifecycle/notify.sh "🟡 GCP Spot 实例已启动：$INSTANCE_NAME，开始等待服务恢复" info >/tmp/spot-notify-boot.log 2>&1 &

# Wait for Docker daemon.
for i in $(seq 1 60); do
  if systemctl is-active --quiet docker; then
    echo "docker active after ${i} checks"
    break
  fi
  sleep 2
done

# Wait for important containers to reappear. Docker restart policy should do the work.
required="autoteam-autoteam-1 cliproxyapi cpa-manager sub2api-proxy sub2api sub2api-postgres sub2api-redis"
for i in $(seq 1 90); do
  running="$(docker ps --format '{{.Names}}' 2>/dev/null | sort | tr '\n' ' ')"
  echo "check=$i running=$running"
  all=1
  for c in $required; do
    echo "$running" | grep -q "\b$c\b" || all=0
  done
  [ "$all" -eq 1 ] && break
  sleep 2
done

HEALTH="$BASE/post-boot-health-$(date +%Y%m%d-%H%M%S).txt"
if /opt/spot-lifecycle/healthcheck.sh > "$HEALTH" 2>&1; then
  STATUS="healthy"
  MSG="🟢 GCP Spot 实例已重新上线：$INSTANCE_NAME，服务健康检查通过"
else
  STATUS="degraded"
  MSG="🟠 GCP Spot 实例已重新上线：$INSTANCE_NAME，但健康检查有失败项，请查看 $HEALTH"
fi
cp -f "$HEALTH" "$BASE/post-boot-health-latest.txt" || true

/opt/spot-lifecycle/notify.sh "$MSG" info || true

RECOVERED="$BASE/recovered-$(date +%Y%m%d-%H%M%S).json"
python3 - <<PY > "$RECOVERED"
import json, time, pathlib
state_path=pathlib.Path('$STATE')
try:
    state=json.loads(state_path.read_text())
except Exception:
    state={}
state.update({
    'status': '$STATUS',
    'recovered_at': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
    'recovered_instance_name': '$INSTANCE_NAME',
    'recovered_boot_id': '$BOOT_ID',
    'health_file': '$HEALTH',
})
print(json.dumps(state, ensure_ascii=False, indent=2))
PY
rm -f "$STATE" || true
sync || true

echo "[$(date -Is)] boot recovery finished status=$STATUS"
exit 0
