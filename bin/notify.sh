#!/usr/bin/env bash
set -u

MSG="${1:-spot lifecycle event}"
LEVEL="${2:-info}"
BASE=/var/lib/spot-lifecycle
LOG="$BASE/notifications.log"
mkdir -p "$BASE"

ts="$(date -Is)"
echo "[$ts][$LEVEL] $MSG" >> "$LOG"

# Optional external notification config:
# /etc/spot-lifecycle.env:
#   WEBHOOK_URL=https://...
#   WEBHOOK_TYPE=generic|wecom|dingtalk|telegram|ntfy|weixin_cmd
#   TELEGRAM_CHAT_ID=...
#   WEBHOOK_CMD=/path/to/sender command
if [ -f /etc/spot-lifecycle.env ]; then
  # shellcheck disable=SC1091
  . /etc/spot-lifecycle.env
fi

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' <<< "$1"
}

if [ "${WEBHOOK_TYPE:-}" = "weixin_cmd" ] && [ -n "${WEBHOOK_CMD:-}" ]; then
  timeout 8 bash -lc "$WEBHOOK_CMD \"\$1\"" _ "$MSG" >> "$LOG" 2>&1 || true
elif [ -n "${WEBHOOK_URL:-}" ]; then
  escaped="$(json_escape "$MSG")"
  case "${WEBHOOK_TYPE:-generic}" in
    wecom)
      payload="{\"msgtype\":\"text\",\"text\":{\"content\":\"$escaped\"}}"
      ;;
    dingtalk)
      payload="{\"msgtype\":\"text\",\"text\":{\"content\":\"$escaped\"}}"
      ;;
    telegram)
      if [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        payload="{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"$escaped\"}"
      else
        payload="{\"text\":\"$escaped\"}"
      fi
      ;;
    ntfy)
      curl -fsS -m 3 -H "Title: GCP Spot Lifecycle" -H "Priority: high" -d "$MSG" "$WEBHOOK_URL" >/dev/null 2>&1 || true
      exit 0
      ;;
    *)
      payload="{\"text\":\"$escaped\",\"level\":\"$LEVEL\",\"timestamp\":\"$ts\"}"
      ;;
  esac
  curl -fsS -m 3 -X POST "$WEBHOOK_URL" -H 'Content-Type: application/json' -d "$payload" >/dev/null 2>&1 || true
fi

# Best-effort local syslog/journal marker.
logger -t spot-lifecycle "[$LEVEL] $MSG" 2>/dev/null || true
