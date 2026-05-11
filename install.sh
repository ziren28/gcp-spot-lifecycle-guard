#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -d -m 0755 /opt/spot-lifecycle /var/lib/spot-lifecycle
install -m 0755 "$ROOT"/bin/*.sh /opt/spot-lifecycle/
if [ -f "$ROOT/bin/weixin-push.py" ]; then
  install -m 0755 "$ROOT/bin/weixin-push.py" /opt/spot-lifecycle/weixin-push.py
fi
install -m 0644 "$ROOT"/systemd/*.service /etc/systemd/system/
install -m 0644 "$ROOT"/systemd/*.timer /etc/systemd/system/ 2>/dev/null || true
if [ ! -f /etc/spot-lifecycle.env ]; then
  install -m 0600 "$ROOT/examples/spot-lifecycle.env.example" /etc/spot-lifecycle.env
fi
systemctl daemon-reload
systemctl enable --now spot-shutdown-watch.service
systemctl enable spot-boot-recovery.service
systemctl enable --now spot-lifecycle-cleanup.timer
systemctl status spot-shutdown-watch.service --no-pager -l || true
