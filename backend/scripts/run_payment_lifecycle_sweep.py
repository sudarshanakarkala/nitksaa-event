#!/usr/bin/env python3
"""Operational entry point for the payment/registration expiry sweep.

Calls app.services.payment_lifecycle_service directly, in-process — no
HTTP request, no bearer token, no network hop. This is the scheduled
counterpart to the manual-recovery HTTP endpoints
(POST /api/v1/admin/payments/lifecycle/expire-orders and
.../expire-registration-holds, platform_admin-only, built in the payment
production foundation sprint) — both call the exact same
payment_lifecycle_service functions, so there is no duplicated lifecycle
logic between the manual and automated paths.

No deployment-native scheduler (cron, Cloud Scheduler, Kubernetes CronJob,
CI scheduled workflow, ...) exists in this repository as of this sprint —
confirmed by search. This script is the thing such a scheduler should
invoke; wiring an actual scheduler to it is an infrastructure decision for
whichever platform this is ultimately deployed to, deliberately left to
ops rather than invented here. See
docs/payments/PAYMENT_OPERATIONS_SECURITY_RUNBOOK.md, section F, for the
recommended cadence and example wiring.

Usage (from backend/):
    .venv/bin/python scripts/run_payment_lifecycle_sweep.py

Exit code 0 only if both sweeps (orders and registration holds) succeeded.
Non-zero otherwise — standard cron/systemd/CI failure-detection contract.
Emits exactly one line of structured JSON to stdout per run. Never logs
tokens, secrets, DB credentials, or full order/registration records — only
counts, IDs, and error messages, the same safety bar the rest of this
codebase's audit trail already holds to.

The two sweeps are isolated from each other: a failure in one does not
prevent the other from running, so a bug specific to (say) order expiry
does not also block registration-hold cleanup.
"""
from __future__ import annotations

import asyncio
import json
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict

from dotenv import load_dotenv

load_dotenv(Path(__file__).parent.parent / ".env")

sys.path.insert(0, str(Path(__file__).parent.parent))

SCHEDULER_ACTOR_UID = "system:scheduler"


async def _run_sweep() -> Dict[str, Any]:
    from app.database import close_pool
    from app.services import payment_lifecycle_service

    run_id = str(uuid.uuid4())
    started_at = datetime.now(timezone.utc)
    result: Dict[str, Any] = {
        "run_id": run_id,
        "started_at": started_at.isoformat(),
        "orders_status": "ok",
        "orders_expired_count": 0,
        "orders_error": None,
        "holds_status": "ok",
        "holds_expired_count": 0,
        "holds_error": None,
    }

    try:
        orders_result = await payment_lifecycle_service.expire_stale_payment_orders(SCHEDULER_ACTOR_UID)
        result["orders_expired_count"] = orders_result["expired_count"]
    except Exception as exc:  # noqa: BLE001 - isolate failure, never let it block the hold sweep
        result["orders_status"] = "error"
        result["orders_error"] = str(exc)

    try:
        holds_result = await payment_lifecycle_service.expire_stale_registration_holds(SCHEDULER_ACTOR_UID)
        result["holds_expired_count"] = holds_result["expired_count"]
    except Exception as exc:  # noqa: BLE001 - isolate failure, never let it block the order sweep
        result["holds_status"] = "error"
        result["holds_error"] = str(exc)

    await close_pool()

    finished_at = datetime.now(timezone.utc)
    result["finished_at"] = finished_at.isoformat()
    result["duration_ms"] = round((finished_at - started_at).total_seconds() * 1000, 1)
    result["success"] = result["orders_status"] == "ok" and result["holds_status"] == "ok"
    return result


def main() -> int:
    start = time.monotonic()
    result = asyncio.run(_run_sweep())
    result["wall_clock_ms"] = round((time.monotonic() - start) * 1000, 1)
    print(json.dumps(result, sort_keys=True))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
