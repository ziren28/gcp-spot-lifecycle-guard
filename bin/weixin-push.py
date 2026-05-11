#!/usr/bin/env python3
"""Send spot lifecycle alerts to the current Weixin home chat via Hermes' Weixin adapter."""
from __future__ import annotations

import asyncio
import json
import os
import sys
from pathlib import Path

HERMES_REPO = Path("/opt/hermes-agent")
HERMES_HOME = Path("/var/lib/hermes")
DEFAULT_CHAT_ID = "YOUR_WEIXIN_CHAT_ID"

sys.path.insert(0, str(HERMES_REPO))
os.environ.setdefault("HERMES_HOME", str(HERMES_HOME))

from gateway.platforms.weixin import send_weixin_direct  # noqa: E402


def load_account() -> tuple[str, str, str]:
    account_dir = HERMES_HOME / "weixin" / "accounts"
    accounts = sorted(p for p in account_dir.glob("*.json") if "context-tokens" not in p.name)
    if not accounts:
        raise RuntimeError(f"No Weixin account file found under {account_dir}")
    # Prefer the newest account file.
    account_path = max(accounts, key=lambda p: p.stat().st_mtime)
    data = json.loads(account_path.read_text(encoding="utf-8"))
    token = str(data.get("token") or "").strip()
    account_id = account_path.name[:-5]
    base_url = str(data.get("base_url") or "https://ilinkai.weixin.qq.com").strip()
    if not token:
        raise RuntimeError(f"Weixin token missing in {account_path}")
    return account_id, token, base_url


async def main() -> int:
    msg = " ".join(sys.argv[1:]).strip() or sys.stdin.read().strip()
    if not msg:
        msg = "spot lifecycle event"
    chat_id = os.getenv("WEIXIN_HOME_CHANNEL", DEFAULT_CHAT_ID).strip() or DEFAULT_CHAT_ID
    account_id, token, base_url = load_account()
    result = await send_weixin_direct(
        extra={"account_id": account_id, "base_url": base_url},
        token=token,
        chat_id=chat_id,
        message=msg,
        media_files=[],
    )
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("success") else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
