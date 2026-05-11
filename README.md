# GCP Spot Lifecycle Guard

A small systemd-based lifecycle guard for Google Cloud Spot / Preemptible VMs.
It detects preemption notices, immediately saves critical state, sends best-effort asynchronous notifications, gracefully stops Docker services, and sends a recovery notification after a Managed Instance Group recreates the VM with the same disk.

## Why

GCP Spot VMs usually provide about 30 seconds of preemption notice. That is not enough for heavy backups, but enough for:

- writing a durable local state file;
- snapshotting Docker/systemd status;
- flushing small config/state changes;
- graceful `docker stop` with short timeouts;
- sending a best-effort alert;
- notifying again after the new VM comes back.

This project is designed for a MIG-managed VM where the boot disk or persistent disk is preserved and reattached.

## Architecture

```text
GCP metadata /instance/preempted
  -> spot-shutdown-watch.service
  -> /opt/spot-lifecycle/shutdown.sh
       - write /var/lib/spot-lifecycle/state.json
       - async notify: preempting
       - save preempt snapshot
       - optional proxy-stack sync-fast
       - graceful docker stop
       - async notify: saved

MIG recreates instance, disk unchanged
  -> systemd boot
  -> docker/nginx/app services recover
  -> spot-boot-recovery.service
       - read previous state.json
       - wait for Docker + containers
       - healthcheck
       - notify: recovered
       - archive recovered state

Daily
  -> spot-lifecycle-cleanup.timer
       - prune old lifecycle logs/snapshots
       - docker system prune without volumes
       - journal vacuum
       - apt clean
```

## Components

| File | Purpose |
| --- | --- |
| `bin/shutdown-daemon.sh` | Polls GCP metadata every 2 seconds for preemption. |
| `bin/shutdown.sh` | Fast shutdown handler; must fit in the Spot grace window. |
| `bin/boot-recovery.sh` | Boot-time recovery notifier and healthcheck runner. |
| `bin/notify.sh` | Notification abstraction: generic webhook, WeCom, DingTalk, Telegram, ntfy, Weixin command. |
| `bin/healthcheck.sh` | Checks systemd, Docker containers, and local HTTP ports. |
| `bin/cleanup.sh` | Safe garbage cleanup. Does not delete Docker volumes. |
| `bin/weixin-push.py` | Optional Hermes Weixin sender. |
| `systemd/*.service` | systemd units. |
| `systemd/*.timer` | daily cleanup timer. |

## Install

```bash
git clone https://github.com/YOUR_USER/gcp-spot-lifecycle-guard.git
cd gcp-spot-lifecycle-guard
sudo ./install.sh
```

Then configure notification:

```bash
sudo cp examples/spot-lifecycle.env.example /etc/spot-lifecycle.env
sudo chmod 600 /etc/spot-lifecycle.env
sudo editor /etc/spot-lifecycle.env
```

Restart notification users if needed:

```bash
sudo systemctl restart spot-shutdown-watch.service
```

## Notification config

### Generic webhook

```bash
WEBHOOK_TYPE=generic
WEBHOOK_URL=https://example.com/webhook
```

Payload:

```json
{"text":"message","level":"info","timestamp":"..."}
```

### WeCom / 企业微信机器人

```bash
WEBHOOK_TYPE=wecom
WEBHOOK_URL=https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx
```

### DingTalk

```bash
WEBHOOK_TYPE=dingtalk
WEBHOOK_URL=https://oapi.dingtalk.com/robot/send?access_token=xxx
```

### Telegram

```bash
WEBHOOK_TYPE=telegram
WEBHOOK_URL=https://api.telegram.org/bot<TOKEN>/sendMessage
TELEGRAM_CHAT_ID=123456
```

### ntfy

```bash
WEBHOOK_TYPE=ntfy
WEBHOOK_URL=https://ntfy.sh/your-topic
```

### Hermes Weixin / WeChat

Requires a working Hermes Agent Weixin gateway/account and its saved account files.
Customize these paths for your host:

```bash
WEBHOOK_TYPE=weixin_cmd
WEBHOOK_CMD="/opt/hermes-agent/venv/bin/python /opt/spot-lifecycle/weixin-push.py"
WEIXIN_HOME_CHANNEL=YOUR_WEIXIN_CHAT_ID
```

## Healthcheck

Run manually:

```bash
sudo /opt/spot-lifecycle/healthcheck.sh
```

The default script checks common services/containers from the original environment. Edit it to match your stack.

## Test notifications

```bash
sudo /opt/spot-lifecycle/notify.sh 'spot lifecycle test message' test
sudo tail -50 /var/lib/spot-lifecycle/notifications.log
```

## Test recovery flow without stopping the VM

```bash
sudo mkdir -p /var/lib/spot-lifecycle
sudo tee /var/lib/spot-lifecycle/state.json >/dev/null <<'JSON'
{"status":"preempting","started_at":"manual-test","recover_notify_pending":true}
JSON
sudo systemctl start spot-boot-recovery.service
sudo tail -100 /var/lib/spot-lifecycle/last-boot-recovery.log
```

## GCP metadata shutdown-script vs watcher

Best option if your VM service account has permission to set metadata:

```bash
gcloud compute instances add-metadata INSTANCE_NAME \
  --zone ZONE \
  --metadata-from-file shutdown-script=/opt/spot-lifecycle/shutdown.sh
```

For MIGs, put it in the **instance template** metadata instead.

If metadata modification is unavailable or not desired, `spot-shutdown-watch.service` is enough for Spot preemption because it polls:

```text
http://metadata.google.internal/computeMetadata/v1/instance/preempted
```

## Garbage cleanup

Daily timer:

```bash
systemctl list-timers | grep spot-lifecycle
```

Cleanup policy:

- lifecycle snapshots/logs older than 14 days;
- recovered state files older than 30 days;
- Docker stopped containers, dangling images, and build cache older than 168h;
- no Docker volume deletion;
- journal logs older than 14 days;
- apt cache.

Manual run:

```bash
sudo systemctl start spot-lifecycle-cleanup.service
```

## Security notes

- Do not store API tokens directly in the repository.
- `/etc/spot-lifecycle.env` should be mode `0600`.
- Shutdown hooks should never perform slow remote backups in the 30-second grace window.
- Prefer writing a local durable state file and doing recovery notifications after boot.

## License

MIT
