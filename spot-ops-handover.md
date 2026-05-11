# GCP Spot VM 运维交接文档

生成时间：2026-05-11 22:55 CST  
目标 VM：`34.0.156.8`  
主机名：`instance-group-2-v4xz`  
定位：GCP Spot VM / MIG 内实例，承载 Sub2API、Hermes/微信 ClawBot、AutoTeam、CLI Proxy API、CPA Manager、导航页等轻量服务。

## 1. 交接摘要

这台 VM 当前是一个低成本 Spot 实例，月成本预估约 10 美元量级。它不是严格意义上的高可用架构：Spot 实例随时可能被回收，MIG 可以帮助重建实例，但只有在启动脚本、镜像、持久盘、备份和 DNS/IP 策略都配好时，服务才能自动恢复。

当前机器的核心入口已经集中到导航页：

```text
https://nav.999968.xyz/
```

敏感信息统一放在 KMS，不在本文明文记录。接手人需要从既有安全渠道取得 KMS API Key 或管理员密码。

KMS 文档：

```text
https://kms-admin-4lo.pages.dev/docs
```

## 2. 当前健康快照

最近核对时间：2026-05-11 22:52 CST

```text
hostname: instance-group-2-v4xz
uptime: up 23 hours, 43 minutes
load: 0.17 0.16 0.21
memory: 2.3Gi / 7.8Gi used
root disk: 12G / 49G used, 25%
```

系统服务状态：

```text
nginx: active
ssh: active
fail2ban: active
hermesclaw: active
hermes-gateway: active
hermes-dashboard: active
```

Docker 容器状态：

```text
autoteam-autoteam-1   -> 0.0.0.0:8787
sub2api-proxy         -> 0.0.0.0:8080
sub2api               -> 127.0.0.1:18080, healthy
sub2api-postgres      -> internal, healthy
sub2api-redis         -> internal, healthy
cpa-manager           -> 0.0.0.0:18317
cliproxyapi           -> 0.0.0.0:8317
```

## 3. 公网访问入口

| 服务 | 地址 | 说明 |
|---|---|---|
| 导航页 | `https://nav.999968.xyz/` | 当前服务总入口，Nginx 静态页 |
| SSH | `34.0.156.8:22222` | 仅密钥登录，禁用密码和 root 登录 |
| Sub2API | `https://openapi.999968.xyz/` | HTTPS 正式入口 |
| Sub2API 健康检查 | `https://openapi.999968.xyz/health` | 应返回 200 |
| Sub2API 旧入口 | `http://34.0.156.8:8080/` | 旧 IP 入口，会跳 HTTPS |
| CLI Proxy API | `http://34.0.156.8:8317/` | OpenAI-compatible API，Hermes 正在使用 |
| CPA Manager | `http://34.0.156.8:18317/` | Docker 容器，当前常见返回 307 |
| AutoTeam | `http://34.0.156.8:8787/` | 学习模式部署 |
| Hermes Dashboard | `https://hermes.999968.xyz/` | Nginx Basic Auth 保护 |
| Cloudflare Temp Email | `https://temp-email-pages-v2x.pages.dev/` | Cloudflare Pages，不在 VM 端口上 |

## 4. 本机内部服务

| 服务 | 内部地址 | 说明 |
|---|---|---|
| Sub2API 容器 | `127.0.0.1:18080` | Nginx 反代到 `openapi.999968.xyz` |
| Hermes Dashboard | `127.0.0.1:9119` | Nginx 反代到 `hermes.999968.xyz` |
| HermesClaw 代理 | `127.0.0.1:19998` | 微信/iLink 到 Hermes gateway 的本地代理 |
| Postgres/Redis | Docker 内部网络 | 给 Sub2API 使用，不对外开放 |

## 5. SSH 与安全

SSH 配置目标：

```text
port: 22222
PasswordAuthentication: no
PermitRootLogin: no
PubkeyAuthentication: yes
fail2ban: enabled
```

常用检查命令：

```bash
sudo systemctl status ssh
sudo journalctl -u ssh -n 100 --no-pager
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

当前为了抗暴力扫描，`sshd_config.d` 中设置过：

```text
MaxStartups 100:30:200
PerSourceMaxStartups 4
LoginGraceTime 20
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

如果 SSH 被大量扫描影响，优先检查：

```bash
sudo journalctl -u ssh -f
sudo fail2ban-client status sshd
sudo systemctl restart ssh
```

## 6. KMS 与敏感信息

KMS 地址：

```text
https://kms-admin-4lo.pages.dev/
https://kms-admin-4lo.pages.dev/docs
```

查询示例：

```bash
curl "https://kms-admin-4lo.pages.dev/api/query?primary=autoteam" \
  -H "Authorization: Bearer $KMS_API_KEY"
```

读取单字段示例：

```bash
curl "https://kms-admin-4lo.pages.dev/api/v1/secrets/autoteam?fields=key_data.api_key" \
  -H "Authorization: Bearer $KMS_API_KEY"
```

已知或建议维护的 KMS primary：

```text
autoteam           AutoTeam API key，来源 /opt/autoteam/data/.env
docker             Docker Hub 账号/PAT
github             GitHub token
cloudflare-d1      Cloudflare D1 相关 token/query endpoint
cloudflare-pages   Cloudflare Pages 部署 token
```

注意事项：

- 文档、Git 仓库、聊天记录里不要粘贴完整 token、私钥、密码。
- 自动化脚本优先使用 KMS API Key，不要硬编码管理员密码。
- 若 token 已暴露，立即去对应平台轮换，并更新 KMS。

## 7. 关键路径

```text
/var/www/vm-nav/index.html                         导航页静态文件
/etc/nginx/sites-enabled/vm-nav.conf               nav.999968.xyz Nginx 配置
/etc/nginx/sites-enabled/openapi-sub2api           openapi.999968.xyz Nginx 配置
/etc/nginx/sites-enabled/hermes-dashboard.conf      hermes.999968.xyz Nginx 配置

/opt/autoteam                                      AutoTeam 项目目录
/opt/autoteam/data/.env                            AutoTeam 配置，API_KEY 已同步到 KMS
/opt/cloudflare_temp_email                         Cloudflare 临时邮箱项目
/opt/cloudflare_temp_email/admin-credentials.txt   临时邮箱后台凭据

/home/brook/.hermes                                Hermes 配置目录
/home/brook/.hermes/dashboard-public-credentials.txt Hermes Dashboard Basic Auth 凭据
```

## 8. Nginx 与证书

当前 Nginx 站点：

```text
hermes-dashboard.conf
openapi-sub2api
vm-nav.conf
```

证书由 certbot 管理。导航页证书：

```text
domain: nav.999968.xyz
expires: 2026-08-09
auto renew: enabled by certbot
```

常用命令：

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo certbot certificates
sudo certbot renew --dry-run
```

## 9. Hermes / 微信 ClawBot

当前状态：

```text
Hermes gateway: active
Hermes dashboard: active
HermesClaw: active
默认主力模型: gpt-5.5
API endpoint: http://34.0.156.8:8317
```

微信里曾收到状态消息：

```text
HermesClaw v3
/hermes    -> Hermes only
/openclaw  -> OpenClaw only
/opencode  -> OpenCode only
/both      -> Hermes + OpenClaw
/three     -> all three
/whoami    -> status
```

微信不回复时优先执行：

```bash
systemctl --user restart hermes-gateway.service
sudo systemctl restart hermesclaw.service
```

查看日志：

```bash
journalctl --user -u hermes-gateway -n 100 --no-pager
journalctl --user -u hermes-dashboard -n 100 --no-pager
sudo journalctl -u hermesclaw -n 100 --no-pager
```

Hermes 网页控制台：

```text
https://hermes.999968.xyz/
```

登录凭据位置：

```text
/home/brook/.hermes/dashboard-public-credentials.txt
```

## 10. Sub2API

公网入口：

```text
https://openapi.999968.xyz/
https://openapi.999968.xyz/health
```

内部服务：

```text
sub2api               127.0.0.1:18080 -> 8080
sub2api-proxy         0.0.0.0:8080
sub2api-postgres      Docker internal
sub2api-redis         Docker internal
```

如果访问 `http://34.0.156.8:8080/` 白屏，优先改用 HTTPS 域名入口。此前白屏和浏览器 CSP/inline script 拦截有关，`openapi.999968.xyz` 的 HTTPS 入口是正式入口。

常用命令：

```bash
docker ps | grep sub2api
docker logs --tail=100 sub2api
docker logs --tail=100 sub2api-proxy
cd /opt/sub2api-deploy && docker compose restart
```

## 11. AutoTeam

入口：

```text
http://34.0.156.8:8787/
```

项目路径：

```text
/opt/autoteam
/opt/autoteam/data/.env
```

`.env` 中的 `API_KEY` 已保存到 KMS：

```text
primary: autoteam
field: key_data.api_key
```

读取方式：

```bash
curl "https://kms-admin-4lo.pages.dev/api/v1/secrets/autoteam?fields=key_data.api_key" \
  -H "Authorization: Bearer $KMS_API_KEY"
```

常用命令：

```bash
docker ps | grep autoteam
docker logs --tail=100 autoteam-autoteam-1
```

## 12. CLI Proxy API / CPA Manager

CLI Proxy API：

```text
http://34.0.156.8:8317/
container: cliproxyapi
```

CPA Manager：

```text
http://34.0.156.8:18317/
container: cpa-manager
```

Hermes 当前通过 CLI Proxy API 调用模型。若 Hermes 回复异常，除了重启 Hermes 服务，还要确认：

```bash
curl -i http://34.0.156.8:8317/
docker logs --tail=100 cliproxyapi
docker logs --tail=100 cpa-manager
```

## 13. Cloudflare Temp Email

入口：

```text
https://temp-email-pages-v2x.pages.dev/
```

项目路径：

```text
/opt/cloudflare_temp_email
```

后台凭据：

```text
/opt/cloudflare_temp_email/admin-credentials.txt
```

已纳入/计划纳入临时邮箱托管的域名：

```text
001096.xyz
001286.xyz
033090.xyz
0797chihuo.com
1225510.xyz
181225.xyz
999968.xyz
dezinify.com
gsetrade.com
maxcole.app
multitechshub.com
nexus-code.app
quantum20equities.tech
zirun.me
```

修改 `wrangler.toml`、Worker 代码或域名配置后需要重新部署：

```bash
cd /opt/cloudflare_temp_email/worker
node node_modules/wrangler/bin/wrangler.js deploy --minify
```

Cloudflare Pages 前端如有变更，也需要重新部署 Pages。

## 14. 导航页

入口：

```text
https://nav.999968.xyz/
```

部署路径：

```text
/var/www/vm-nav/index.html
/etc/nginx/sites-enabled/vm-nav.conf
```

本地源码副本：

```text
D:\GCP\vm-nav\index.html
D:\GCP\vm-nav\nginx-nav.conf
```

更新步骤：

```bash
sudo cp /tmp/vm-nav-index.html /var/www/vm-nav/index.html
sudo nginx -t
sudo systemctl reload nginx
```

## 15. Spot / MIG 风险与恢复策略

当前需要特别提醒接手人：Spot VM 不是稳定长久在线机器。Google Cloud 可以随时回收实例，MIG 只负责重建，不天然保证应用数据完整恢复。

当前架构风险：

- 若外部 IP 不是保留静态 IP，实例重建后 IP 可能变化，DNS 需要更新。
- 若 MIG 模板没有完整启动脚本，新实例不会自动恢复所有服务。
- Sub2API 的 Postgres/Redis 在 Docker 内部，必须确认 volume 备份策略。
- `/home/brook/.hermes`、`/opt/autoteam/data`、`/opt/cloudflare_temp_email`、Nginx 配置都需要备份。
- 单 VM 上跑多个服务，VM 被抢占时所有本机服务都会同时中断。

建议的 HA 改造顺序：

1. 确认 `34.0.156.8` 是保留静态 IP，或改为负载均衡/DNS 自动更新。
2. 把服务启动流程写成 startup script 或 Ansible 脚本。
3. 把 `/opt`、Docker volumes、Hermes 配置做定期快照。
4. Sub2API 数据库迁到外部托管数据库，或至少做每日备份。
5. 为 MIG 配 health check，让 Nginx/核心端口异常时自动重建。
6. 将 Cloudflare DNS/API 更新脚本纳入恢复流程。

## 16. 常用巡检命令

```bash
hostname
uptime
free -h
df -h
docker ps
sudo systemctl status nginx ssh fail2ban hermesclaw
systemctl --user status hermes-gateway hermes-dashboard
sudo nginx -t
sudo certbot certificates
```

端口检查：

```bash
ss -tulpn | grep -E ':22222|:8080|:8317|:8787|:9119|:18317|:19998'
```

公网检查：

```bash
curl -I https://nav.999968.xyz/
curl -I https://openapi.999968.xyz/health
curl -I https://hermes.999968.xyz/
curl -I http://34.0.156.8:8317/
curl -I http://34.0.156.8:8787/
curl -I http://34.0.156.8:18317/
```

## 17. 备份清单

优先备份：

```text
/opt/autoteam/data
/opt/cloudflare_temp_email
/home/brook/.hermes
/var/www/vm-nav
/etc/nginx/sites-available
/etc/nginx/sites-enabled
/etc/ssh/sshd_config.d
Docker volumes for sub2api-postgres/sub2api-redis
```

Docker volume 先盘点：

```bash
docker volume ls
docker inspect sub2api-postgres
docker inspect sub2api-redis
```

如果要做最小化恢复包，至少包含：

```text
Nginx 配置
Docker compose 文件
Hermes 配置
AutoTeam data/.env
Cloudflare Temp Email 配置
Sub2API 数据库 volume 备份
KMS primary 清单
```

## 18. 故障处理速查

### 微信 Hermes 不回复

```bash
systemctl --user restart hermes-gateway.service
sudo systemctl restart hermesclaw.service
journalctl --user -u hermes-gateway -n 100 --no-pager
sudo journalctl -u hermesclaw -n 100 --no-pager
```

同时检查 CLI Proxy API：

```bash
curl -i http://34.0.156.8:8317/
docker logs --tail=100 cliproxyapi
```

### Sub2API 页面白屏

优先访问：

```text
https://openapi.999968.xyz/
```

不要直接用裸 IP 的旧入口作为主入口。

### HTTPS 证书异常

```bash
sudo certbot certificates
sudo certbot renew --dry-run
sudo nginx -t
sudo systemctl reload nginx
```

### SSH 被扫或连接不稳定

```bash
sudo journalctl -u ssh -f
sudo fail2ban-client status sshd
sudo systemctl restart ssh
```

### Spot 实例重建后服务缺失

按顺序检查：

```bash
docker ps -a
sudo systemctl status nginx ssh fail2ban hermesclaw
systemctl --user status hermes-gateway hermes-dashboard
ls -lah /opt
ls -lah /home/brook/.hermes
sudo nginx -t
```

如果公网 IP 变化，需要更新：

```text
openapi.999968.xyz
hermes.999968.xyz
nav.999968.xyz
可能还有其他直接指向 VM 的 A 记录
```

## 19. 接手人第一天 checklist

- 打开 `https://nav.999968.xyz/`，确认所有入口可见。
- 登录 VM，运行巡检命令确认服务状态。
- 确认 KMS API Key 可用，并能查询 `primary=autoteam`。
- 确认 SSH 密钥、GCP 控制台/IAP 登录路径可用。
- 确认 `34.0.156.8` 是否为保留静态 IP。
- 确认 Docker volumes 的备份位置和最近一次备份时间。
- 确认 Cloudflare token 权限是否最小化，是否仍有效。
- 记录当前 MIG 模板是否包含自动恢复脚本。
- 做一次 `certbot renew --dry-run`。
- 做一次 Hermes 微信消息收发测试。

## 20. 不应做的事

- 不要把 KMS API Key、Cloudflare token、GitHub token、SSH 私钥写进 Git 仓库或交接文档。
- 不要在未备份 volume 的情况下重建 Sub2API 数据库容器。
- 不要随手 `docker compose down -v`。
- 不要关闭 fail2ban 或重新开启密码登录。
- 不要把 Spot VM 当作无中断生产环境。

