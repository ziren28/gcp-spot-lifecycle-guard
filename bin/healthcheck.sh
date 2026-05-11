#!/usr/bin/env bash
set -u

BASE=/var/lib/spot-lifecycle
mkdir -p "$BASE"

ok=0
fail=0
check_cmd() {
  local name="$1"; shift
  if "$@" >/tmp/spot-healthcheck-one.out 2>&1; then
    echo "OK $name"
    ok=$((ok+1))
  else
    echo "FAIL $name :: $(tr '\n' ' ' </tmp/spot-healthcheck-one.out | cut -c1-200)"
    fail=$((fail+1))
  fi
}

check_http() {
  local name="$1" url="$2"
  check_cmd "$name" curl -fsS -m 5 "$url"
}

echo "spot lifecycle healthcheck $(date -Is)"
echo "hostname=$(hostname)"
echo "boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
echo

check_cmd systemd-running systemctl is-system-running --quiet
check_cmd docker-active systemctl is-active --quiet docker
check_cmd nginx-active systemctl is-active --quiet nginx
check_cmd hermesclaw-active systemctl is-active --quiet hermesclaw
check_cmd proxy-sync-watch-active systemctl is-active --quiet proxy-stack-sync-watch

for c in autoteam-autoteam-1 cliproxyapi cpa-manager sub2api-proxy sub2api sub2api-postgres sub2api-redis; do
  check_cmd "container:$c" docker inspect -f '{{.State.Running}}' "$c"
done

check_cmd autoteam-listening bash -lc "curl -fsS -m 5 http://127.0.0.1:8787/ >/dev/null || [ \"$(curl -sS -m 5 -o /tmp/autoteam-health.body -w '%{http_code}' http://127.0.0.1:8787/api/auth/check)\" = 401 ]"
check_http cliproxyapi http://127.0.0.1:8317/
check_http cpa-manager http://127.0.0.1:18317/
check_http sub2api http://127.0.0.1:18080/

echo
echo "summary ok=$ok fail=$fail"
[ "$fail" -eq 0 ]
