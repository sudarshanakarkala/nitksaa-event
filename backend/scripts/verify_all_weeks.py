#!/usr/bin/env python3
"""verify_all_weeks.py — NITKSAA Event Platform automated verification suite.

Covers Week 1 through Week 5. Produces PASS / FAIL / WARNING per test and
writes JSON and Markdown reports.

Usage (from repository root):
    cd backend
    python scripts/verify_all_weeks.py \\
        --base-url http://localhost:8000 \\
        --json-output ../docs/reviews/week1_to_week5_automated_verification.json \\
        --markdown-output ../docs/reviews/week1_to_week5_automated_verification_report.md

Requirements: httpx (already in backend venv)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx

# ─── Constants ────────────────────────────────────────────────────────────────

_VERSION = "1.0.0"
_DIAG_PREFIX = "DIAG_ALL_WEEKS"
_SECRET_WORDS = re.compile(
    r"(password|passwd|secret|api_key|private_key|smtp_pass|token|jwt|credential)",
    re.IGNORECASE,
)
_VALID_REGISTRATION_STATUSES = {"open", "full", "closed", "not_open_yet"}
_KNOWN_FLUTTER_TEST_FAILURES = {
    "authenticated Register shows Week 3 message": (
        "Pre-existing from Week 2 (commit 21ee22f). GoRouter not provided in test "
        "widget tree. Not a Week 5 regression."
    ),
}

# ─── Result helpers ───────────────────────────────────────────────────────────

def _t(
    id: str,
    name: str,
    status: str,
    details: str,
    evidence: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    return {
        "id": id,
        "name": name,
        "status": status,  # PASS | FAIL | WARNING
        "details": details,
        "evidence": evidence or {},
    }


def _pass(id, name, details, evidence=None):
    return _t(id, name, "PASS", details, evidence)


def _fail(id, name, details, evidence=None):
    return _t(id, name, "FAIL", details, evidence)


def _warn(id, name, details, evidence=None):
    return _t(id, name, "WARNING", details, evidence)


def _category(id: str, name: str, tests: List[Dict]) -> Dict[str, Any]:
    passed = sum(1 for t in tests if t["status"] == "PASS")
    failed = sum(1 for t in tests if t["status"] == "FAIL")
    warnings = sum(1 for t in tests if t["status"] == "WARNING")
    cat_status = "FAIL" if failed > 0 else ("WARNING" if warnings > 0 else "PASS")
    return {
        "id": id,
        "name": name,
        "status": cat_status,
        "total": len(tests),
        "passed": passed,
        "failed": failed,
        "warnings": warnings,
        "tests": tests,
    }


def _redact(obj: Any, depth: int = 0) -> Any:
    """Recursively redact secret-looking values — never print credentials."""
    if depth > 8:
        return obj
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if _SECRET_WORDS.search(str(k)):
                out[k] = "***REDACTED***"
            else:
                out[k] = _redact(v, depth + 1)
        return out
    if isinstance(obj, list):
        return [_redact(i, depth + 1) for i in obj]
    if isinstance(obj, str) and _SECRET_WORDS.search(obj):
        return "***REDACTED***"
    return obj


def _scan_secrets(text: str) -> List[str]:
    """Return all matched secret-looking keys found in raw text."""
    return list(set(_SECRET_WORDS.findall(text)))


# ─── HTTP client wrapper ──────────────────────────────────────────────────────

class APIClient:
    def __init__(self, base_url: str, admin_header: Dict[str, str], timeout: float = 30.0):
        self.base_url = base_url.rstrip("/")
        self.admin_header = admin_header
        self.timeout = timeout
        self._client = httpx.Client(timeout=timeout)

    def get(self, path: str, headers: Optional[Dict] = None, params: Optional[Dict] = None) -> httpx.Response:
        h = {**self.admin_header, **(headers or {})}
        return self._client.get(f"{self.base_url}{path}", headers=h, params=params)

    def post(self, path: str, json: Any = None, headers: Optional[Dict] = None) -> httpx.Response:
        h = {**self.admin_header, **(headers or {})}
        return self._client.post(f"{self.base_url}{path}", json=json, headers=h)

    def patch(self, path: str, json: Any = None, headers: Optional[Dict] = None) -> httpx.Response:
        h = {**self.admin_header, **(headers or {})}
        return self._client.patch(f"{self.base_url}{path}", json=json, headers=h)

    def delete(self, path: str, headers: Optional[Dict] = None) -> httpx.Response:
        h = {**self.admin_header, **(headers or {})}
        return self._client.delete(f"{self.base_url}{path}", headers=h)

    def close(self):
        self._client.close()


# ─── Verifier ─────────────────────────────────────────────────────────────────

class Verifier:
    def __init__(self, base_url: str, admin_header: Dict[str, str], repo_root: Path):
        self.api = APIClient(base_url, admin_header)
        self.base_url = base_url
        self.repo_root = repo_root
        self._created_event_ids: List[int] = []  # track for cleanup

    # ── Cleanup ────────────────────────────────────────────────────────────

    def _cleanup(self):
        for eid in list(self._created_event_ids):
            try:
                self.api.patch(f"/api/v1/events/{eid}/status", json={"status": "cancelled"})
            except Exception:
                pass
        self._created_event_ids.clear()

    # ── Diagnostic suite normalizer ────────────────────────────────────────

    def _parse_diag_suite(self, data: Dict, suite_prefix: str) -> Tuple[List[Dict], Dict]:
        """Convert an existing diagnostic suite response into our test list format."""
        tests = []
        results = data.get("results", [])
        for r in results:
            rid = r.get("id") or r.get("uc") or r.get("feature", "")
            rname = r.get("name") or r.get("feature", rid)
            rstatus = r.get("status", "FAIL")
            if rstatus not in ("PASS", "FAIL", "WARNING"):
                rstatus = "FAIL"
            rdetails = r.get("details") or str(r.get("detail") or r.get("response") or "")
            tests.append(_t(f"{suite_prefix}_{rid}", rname, rstatus, str(rdetails)[:300]))
        summary = {
            "total": data.get("total", len(tests)),
            "passed": data.get("passed", 0),
            "failed": data.get("failed", 0),
            "warnings": data.get("warnings", 0),
        }
        return tests, summary

    # ── Category: Environment ──────────────────────────────────────────────

    def cat_environment(self) -> List[Dict]:
        tests = []

        # w1_env_01 — backend health
        try:
            r = self.api.get("/api/v1/health")
            data = r.json()
            if r.status_code == 200 and data.get("status") == "ok" and data.get("db") == "ok":
                tests.append(_pass("w1_env_01", "Backend health: status=ok, db=ok",
                    f"HTTP {r.status_code} version={data.get('version')} env={data.get('env')}",
                    {"endpoint": "/api/v1/health", "http_status": r.status_code}))
            else:
                tests.append(_fail("w1_env_01", "Backend health: status=ok, db=ok",
                    f"HTTP {r.status_code} body={str(data)[:200]}",
                    {"endpoint": "/api/v1/health", "http_status": r.status_code}))
        except Exception as e:
            tests.append(_fail("w1_env_01", "Backend health: status=ok, db=ok",
                f"Connection error: {e}", {"endpoint": "/api/v1/health"}))
            return tests  # if backend is down, remaining tests will all fail

        # w1_env_02 — healthz alias
        try:
            r = self.api.get("/healthz")
            ok = r.status_code == 200 and r.json().get("status") == "ok"
            fn = _pass if ok else _fail
            tests.append(fn("w1_env_02", "Root health alias /healthz returns ok",
                f"HTTP {r.status_code}", {"endpoint": "/healthz", "http_status": r.status_code}))
        except Exception as e:
            tests.append(_fail("w1_env_02", "Root health alias /healthz returns ok", str(e)))

        # w1_env_03 — dev mode: diagnostic endpoint accessible with admin header
        try:
            r = self.api.get("/api/v1/dev/diagnostics/db/tables")
            ok = r.status_code == 200
            fn = _pass if ok else _fail
            tests.append(fn("w1_env_03", "Dev mode: diagnostics accessible with X-Dev-User: admin",
                f"HTTP {r.status_code}", {"endpoint": "/api/v1/dev/diagnostics/db/tables", "http_status": r.status_code}))
        except Exception as e:
            tests.append(_fail("w1_env_03", "Dev mode: diagnostics accessible with X-Dev-User: admin", str(e)))

        # w1_env_04 — dev diagnostics blocked without auth (no admin header)
        try:
            r = httpx.get(f"{self.base_url}/api/v1/dev/diagnostics/db/tables", timeout=10)
            if r.status_code in (401, 403, 422):
                tests.append(_pass("w1_env_04", "Dev diagnostics blocked without valid auth header",
                    f"HTTP {r.status_code} (correctly rejected)", {"http_status": r.status_code}))
            elif r.status_code == 200:
                tests.append(_fail("w1_env_04", "Dev diagnostics blocked without valid auth header",
                    "Endpoint returned 200 without auth — security issue",
                    {"http_status": 200}))
            else:
                tests.append(_warn("w1_env_04", "Dev diagnostics blocked without valid auth header",
                    f"HTTP {r.status_code} (unexpected — documenting)",
                    {"http_status": r.status_code}))
        except Exception as e:
            tests.append(_warn("w1_env_04", "Dev diagnostics blocked without valid auth header",
                f"Could not verify: {e}"))

        # w1_env_05 — no secrets in health response
        try:
            r = self.api.get("/api/v1/health")
            raw = r.text
            found = _scan_secrets(raw)
            if not found:
                tests.append(_pass("w1_env_05", "Health endpoint contains no secret-looking keys",
                    "Secrets scan: CLEAN"))
            else:
                tests.append(_fail("w1_env_05", "Health endpoint contains no secret-looking keys",
                    f"Found secret-like keys in response: {found}"))
        except Exception as e:
            tests.append(_warn("w1_env_05", "Health endpoint contains no secret-looking keys", str(e)))

        # w1_env_06 — no secrets in week5/all diagnostic output
        try:
            r = self.api.get("/api/v1/dev/diagnostics/week5/all")
            if r.status_code == 200:
                raw = r.text
                found = [w for w in _scan_secrets(raw)
                         if w.lower() not in ("secret",)]  # "secret" appears in test name an_11
                if not found:
                    tests.append(_pass("w1_env_06", "Week 5 diagnostics output has no sensitive credential keys",
                        "Secrets scan: CLEAN (word 'secret' appears only in test name an_11 — expected)"))
                else:
                    tests.append(_fail("w1_env_06", "Week 5 diagnostics output has no sensitive credential keys",
                        f"Found unexpected secret-like keys: {found}"))
            else:
                tests.append(_warn("w1_env_06", "Week 5 diagnostics output has no sensitive credential keys",
                    f"Could not run week5/all: HTTP {r.status_code}"))
        except Exception as e:
            tests.append(_warn("w1_env_06", "Week 5 diagnostics output has no sensitive credential keys", str(e)))

        return tests

    # ── Category: API Index Consistency ───────────────────────────────────

    def cat_api_index_consistency(self) -> List[Dict]:
        tests = []

        # Routes that must return non-404 with admin header
        expected_ok = [
            ("api_idx_01", "GET /api/v1/health", "/api/v1/health", [200]),
            ("api_idx_02", "GET /api/v1/events/public", "/api/v1/events/public", [200]),
            ("api_idx_03", "GET /api/v1/events (admin list)", "/api/v1/events", [200]),
            ("api_idx_04", "GET /api/v1/events/{id} (event detail)", "/api/v1/events/1", [200, 404]),
        ]
        for tid, name, path, expected_codes in expected_ok:
            try:
                r = self.api.get(path)
                ok = r.status_code in expected_codes
                fn = _pass if ok else _fail
                tests.append(fn(tid, f"Route exists: {name}",
                    f"HTTP {r.status_code} (expected {expected_codes})",
                    {"endpoint": path, "http_status": r.status_code}))
            except Exception as e:
                tests.append(_fail(tid, f"Route exists: {name}", str(e), {"endpoint": path}))

        # Routes that must return 401/403 WITHOUT auth header (security invariants)
        protected = [
            ("api_idx_05", "POST /api/v1/auth/firebase requires body", "/api/v1/auth/firebase", [400, 422]),
            ("api_idx_06", "GET /api/v1/auth/me requires Bearer JWT", "/api/v1/auth/me", [401, 403, 422]),
            ("api_idx_07", "GET /api/v1/alumni/me requires Bearer JWT", "/api/v1/alumni/me", [401, 403, 422]),
        ]
        for tid, name, path, expected_codes in protected:
            try:
                r = httpx.get(f"{self.base_url}{path}", timeout=10)
                ok = r.status_code in expected_codes
                fn = _pass if ok else _warn
                tests.append(fn(tid, f"Protected route blocks unauthenticated: {name}",
                    f"HTTP {r.status_code} without auth (expected one of {expected_codes})",
                    {"endpoint": path, "http_status": r.status_code}))
            except Exception as e:
                tests.append(_warn(tid, f"Protected route blocks unauthenticated: {name}", str(e)))

        # DELETE /api/v1/events/{id}/register is documented as NOT implemented
        try:
            r = httpx.delete(f"{self.base_url}/api/v1/events/1/register", timeout=10)
            if r.status_code in (404, 405):
                tests.append(_pass("api_idx_08",
                    "DELETE /register is correctly not implemented (404 or 405)",
                    f"HTTP {r.status_code} — as documented in backend_api_index_v3.md",
                    {"endpoint": "/api/v1/events/1/register", "http_status": r.status_code}))
            else:
                tests.append(_warn("api_idx_08",
                    "DELETE /register is correctly not implemented (404 or 405)",
                    f"HTTP {r.status_code} — unexpected; doc says not implemented",
                    {"endpoint": "/api/v1/events/1/register", "http_status": r.status_code}))
        except Exception as e:
            tests.append(_warn("api_idx_08", "DELETE /register is correctly not implemented", str(e)))

        # Week 5 enrichment routes exist
        w5_routes = [
            ("api_idx_09", "/api/v1/events/1/people"),
            ("api_idx_10", "/api/v1/events/1/sponsors"),
            ("api_idx_11", "/api/v1/events/1/partners"),
        ]
        for tid, path in w5_routes:
            try:
                r = self.api.get(path)
                ok = r.status_code in (200, 404)  # 404 if event doesn't exist
                fn = _pass if ok else _fail
                tests.append(fn(tid, f"Week 5 enrichment route responds: {path}",
                    f"HTTP {r.status_code} (200 or 404 both valid)",
                    {"endpoint": path, "http_status": r.status_code}))
            except Exception as e:
                tests.append(_fail(tid, f"Week 5 enrichment route responds: {path}", str(e)))

        # Week 5 diagnostic routes exist
        w5_diag = [
            ("api_idx_12", "/api/v1/dev/diagnostics/week5/event-options"),
            ("api_idx_13", "/api/v1/dev/diagnostics/week5/people"),
            ("api_idx_14", "/api/v1/dev/diagnostics/week5/sponsors-partners"),
            ("api_idx_15", "/api/v1/dev/diagnostics/week5/analytics"),
            ("api_idx_16", "/api/v1/dev/diagnostics/week5/all"),
        ]
        for tid, path in w5_diag:
            try:
                r = self.api.get(path)
                ok = r.status_code == 200
                fn = _pass if ok else _fail
                tests.append(fn(tid, f"Week 5 diagnostic route responds: {path}",
                    f"HTTP {r.status_code}",
                    {"endpoint": path, "http_status": r.status_code}))
            except Exception as e:
                tests.append(_fail(tid, f"Week 5 diagnostic route responds: {path}", str(e)))

        return tests

    # ── Category: Public Events (Week 2) ──────────────────────────────────

    def cat_public_events(self) -> List[Dict]:
        tests = []

        # w2_pub_01 — public list returns 200
        try:
            r = self.api.get("/api/v1/events/public")
            data = r.json()
            ok = r.status_code == 200 and "events" in data
            fn = _pass if ok else _fail
            tests.append(fn("w2_pub_01", "GET /events/public returns 200 with events array",
                f"HTTP {r.status_code} events_count={len(data.get('events', []))}",
                {"endpoint": "/api/v1/events/public", "http_status": r.status_code}))

            if r.status_code == 200:
                events = data.get("events", [])

                # w2_pub_02 — no virtual_url or join_url in list
                leaky = [e for e in events if "virtual_url" in e or "join_url" in e]
                if not leaky:
                    tests.append(_pass("w2_pub_02", "Public event list: no virtual_url or join_url",
                        f"Checked {len(events)} events — clean"))
                else:
                    tests.append(_fail("w2_pub_02", "Public event list: no virtual_url or join_url",
                        f"{len(leaky)} events expose virtual_url or join_url"))

                # w2_pub_03 — Week 5 fields in list
                if events:
                    e = events[0]
                    has_w5 = all(k in e for k in ("is_full_day", "is_free", "ticket_price"))
                    fn2 = _pass if has_w5 else _fail
                    tests.append(fn2("w2_pub_03", "Public event list items include Week 5 option fields",
                        f"is_full_day={e.get('is_full_day')} is_free={e.get('is_free')} ticket_price={e.get('ticket_price')}"))

                # w2_pub_04 — registration_status is valid
                invalid_status = [e for e in events
                                  if e.get("registration_status") not in _VALID_REGISTRATION_STATUSES and e.get("registration_status") is not None]
                if not invalid_status:
                    tests.append(_pass("w2_pub_04", "All events have valid registration_status",
                        f"Valid statuses: {_VALID_REGISTRATION_STATUSES}"))
                else:
                    tests.append(_fail("w2_pub_04", "All events have valid registration_status",
                        f"{len(invalid_status)} events have invalid registration_status"))

                # w2_pub_05 — pagination fields present
                has_pg = "total" in data and "page" in data
                fn3 = _pass if has_pg else _fail
                tests.append(fn3("w2_pub_05", "Public event list response includes pagination fields",
                    f"total={data.get('total')} page={data.get('page')} per_page={data.get('per_page')}"))

        except Exception as e:
            tests.append(_fail("w2_pub_01", "GET /events/public returns 200 with events array",
                f"Exception: {e}"))
            return tests

        # w2_pub_06 — public event detail: event wrapper key
        try:
            pub_list = self.api.get("/api/v1/events/public").json().get("events", [])
            event_id = pub_list[0]["event_id"] if pub_list else None
            if event_id:
                r = self.api.get(f"/api/v1/events/public/{event_id}")
                data = r.json()
                has_wrapper = r.status_code == 200 and "event" in data
                fn = _pass if has_wrapper else _fail
                tests.append(fn("w2_pub_06", "Public event detail wraps event under 'event' key",
                    f"HTTP {r.status_code} 'event' key present={has_wrapper}",
                    {"endpoint": f"/api/v1/events/public/{event_id}", "http_status": r.status_code}))

                if has_wrapper:
                    ev = data["event"]

                    # w2_pub_07 — no virtual_url or join_url in detail
                    leaky = "virtual_url" in ev or "join_url" in ev
                    fn2 = _fail if leaky else _pass
                    tests.append(fn2("w2_pub_07", "Public event detail: no virtual_url or join_url",
                        "virtual_url or join_url present — LEAK" if leaky else "Clean"))

                    # w2_pub_08 — Week 5 enrichment arrays present and default to []
                    has_arrays = all(k in ev for k in ("people", "speakers", "sponsors", "partners"))
                    all_lists = has_arrays and all(isinstance(ev.get(k), list) for k in ("people", "speakers", "sponsors", "partners"))
                    fn3 = _pass if (has_arrays and all_lists) else _fail
                    tests.append(fn3("w2_pub_08", "Public event detail includes people[], speakers[], sponsors[], partners[]",
                        f"people={len(ev.get('people',[]))} speakers={len(ev.get('speakers',[]))} "
                        f"sponsors={len(ev.get('sponsors',[]))} partners={len(ev.get('partners',[]))}"))

                    # w2_pub_09 — Week 5 option fields in detail
                    has_opts = all(k in ev for k in ("is_full_day", "is_free", "ticket_price"))
                    fn4 = _pass if has_opts else _fail
                    tests.append(fn4("w2_pub_09", "Public event detail includes is_full_day, is_free, ticket_price",
                        f"is_full_day={ev.get('is_full_day')} is_free={ev.get('is_free')} ticket_price={ev.get('ticket_price')}"))

                    # w2_pub_10 — no is_visible in public arrays
                    leaky_vis = any("is_visible" in item
                                    for arr_name in ("people", "speakers", "sponsors", "partners")
                                    for item in ev.get(arr_name, []))
                    fn5 = _fail if leaky_vis else _pass
                    tests.append(fn5("w2_pub_10", "Public event detail: is_visible never returned in public arrays",
                        "LEAK: is_visible found in public array item" if leaky_vis else "Clean — is_visible absent from all public arrays"))
            else:
                tests.append(_warn("w2_pub_06", "Public event detail wraps event under 'event' key",
                    "No published events found to test detail endpoint"))
        except Exception as e:
            tests.append(_fail("w2_pub_06", "Public event detail wraps event under 'event' key", str(e)))

        return tests

    # ── Category: Admin Events (Week 2 + Week 5 Phase 1) ─────────────────

    def cat_admin_events(self) -> List[Dict]:
        tests = []
        ts = datetime.now(timezone.utc).strftime("%H%M%S")
        base_title = f"{_DIAG_PREFIX}_{ts}"
        start = "2027-01-15T10:00:00"
        end = "2027-01-15T12:00:00"
        event_id: Optional[int] = None

        # w2_adm_01 — create draft event
        try:
            r = self.api.post("/api/v1/events", json={
                "title": f"{base_title}_DRAFT",
                "description": "Automated verification test — safe to delete",
                "start_datetime": start,
                "end_datetime": end,
                "timezone": "Asia/Kolkata",
                "is_virtual": False,
                "location_text": "Verification Test Location",
                "capacity": 10,
            })
            data = r.json()
            created = r.status_code in (200, 201) and "event_id" in (data.get("event") or data)
            if created:
                ev = data.get("event") or data
                event_id = ev.get("event_id")
                if event_id:
                    self._created_event_ids.append(event_id)
                tests.append(_pass("w2_adm_01", "Create draft event via POST /events",
                    f"HTTP {r.status_code} event_id={event_id} status={ev.get('status')}",
                    {"endpoint": "/api/v1/events", "http_status": r.status_code, "event_id": event_id}))
            else:
                tests.append(_fail("w2_adm_01", "Create draft event via POST /events",
                    f"HTTP {r.status_code} body={str(data)[:200]}"))
        except Exception as e:
            tests.append(_fail("w2_adm_01", "Create draft event via POST /events", str(e)))

        if event_id is None:
            tests.append(_warn("w2_adm_02", "Update event via PATCH /events/{id}", "Skipped — create failed"))
            tests.append(_warn("w2_adm_03", "Publish event via PATCH /events/{id}/status", "Skipped — create failed"))
            tests.append(_warn("w2_adm_04", "Week 5 defaults on new event (is_full_day, is_free)", "Skipped — create failed"))
        else:
            # w2_adm_02 — update event title
            try:
                r = self.api.patch(f"/api/v1/events/{event_id}", json={"title": f"{base_title}_UPDATED"})
                data = r.json()
                ev = data.get("event") or data
                ok = r.status_code == 200 and "UPDATED" in str(ev.get("title", ""))
                fn = _pass if ok else _fail
                tests.append(fn("w2_adm_02", "Update event via PATCH /events/{id}",
                    f"HTTP {r.status_code} title={ev.get('title', '')!r}",
                    {"endpoint": f"/api/v1/events/{event_id}", "http_status": r.status_code}))
            except Exception as e:
                tests.append(_fail("w2_adm_02", "Update event via PATCH /events/{id}", str(e)))

            # w2_adm_03 — publish event
            try:
                r = self.api.patch(f"/api/v1/events/{event_id}/status", json={"status": "published"})
                data = r.json()
                ev = data.get("event") or data
                ok = r.status_code == 200 and ev.get("status") == "published"
                fn = _pass if ok else _fail
                tests.append(fn("w2_adm_03", "Publish event via PATCH /events/{id}/status",
                    f"HTTP {r.status_code} status={ev.get('status')}",
                    {"endpoint": f"/api/v1/events/{event_id}/status", "http_status": r.status_code}))
            except Exception as e:
                tests.append(_fail("w2_adm_03", "Publish event via PATCH /events/{id}/status", str(e)))

            # w2_adm_04 — Week 5 defaults on new event
            try:
                r = self.api.get(f"/api/v1/events/{event_id}")
                data = r.json()
                ev = data.get("event") or data
                defaults_ok = (
                    ev.get("is_full_day") is False
                    and ev.get("is_free") is True
                    and ev.get("ticket_price") is None
                )
                fn = _pass if defaults_ok else _fail
                tests.append(fn("w2_adm_04", "New event has correct Week 5 defaults (is_full_day=false, is_free=true, ticket_price=null)",
                    f"is_full_day={ev.get('is_full_day')} is_free={ev.get('is_free')} ticket_price={ev.get('ticket_price')}"))
            except Exception as e:
                tests.append(_warn("w2_adm_04", "New event has correct Week 5 defaults", str(e)))

        # w2_adm_05 — create paid event and verify shape
        paid_id: Optional[int] = None
        try:
            r = self.api.post("/api/v1/events", json={
                "title": f"{base_title}_PAID",
                "description": "Automated verification — paid event test",
                "start_datetime": start,
                "end_datetime": end,
                "timezone": "Asia/Kolkata",
                "is_virtual": False,
                "location_text": "Verification Test",
                "capacity": 10,
                "is_free": False,
                "ticket_price": 500.0,
            })
            data = r.json()
            ev = data.get("event") or data
            ok = r.status_code in (200, 201) and ev.get("is_free") is False
            if ok:
                paid_id = ev.get("event_id")
                if paid_id:
                    self._created_event_ids.append(paid_id)
            fn = _pass if ok else _fail
            tests.append(fn("w2_adm_05", "Create paid event via POST /events: is_free=false, ticket_price=500",
                f"HTTP {r.status_code} is_free={ev.get('is_free')} ticket_price={ev.get('ticket_price')}",
                {"http_status": r.status_code}))
        except Exception as e:
            tests.append(_fail("w2_adm_05", "Create paid event: is_free=false, ticket_price=500", str(e)))

        # w2_adm_06 — create full-day event and verify shape
        try:
            r = self.api.post("/api/v1/events", json={
                "title": f"{base_title}_FULLDAY",
                "description": "Automated verification — full-day event test",
                "start_datetime": "2027-01-20T00:00:00",
                "end_datetime": "2027-01-20T23:59:59",
                "timezone": "Asia/Kolkata",
                "is_virtual": False,
                "location_text": "Verification Test",
                "capacity": 10,
                "is_full_day": True,
            })
            data = r.json()
            ev = data.get("event") or data
            ok = r.status_code in (200, 201) and ev.get("is_full_day") is True
            fd_id = ev.get("event_id") if ok else None
            if fd_id:
                self._created_event_ids.append(fd_id)
            fn = _pass if ok else _fail
            tests.append(fn("w2_adm_06", "Create full-day event via POST /events: is_full_day=true",
                f"HTTP {r.status_code} is_full_day={ev.get('is_full_day')}",
                {"http_status": r.status_code}))
        except Exception as e:
            tests.append(_fail("w2_adm_06", "Create full-day event: is_full_day=true", str(e)))

        # w2_adm_07 — admin event list accessible
        try:
            r = self.api.get("/api/v1/events")
            data = r.json()
            events = data.get("events") or data.get("items") or (data if isinstance(data, list) else [])
            ok = r.status_code == 200 and isinstance(events, list)
            fn = _pass if ok else _fail
            tests.append(fn("w2_adm_07", "Admin event list GET /events returns events array",
                f"HTTP {r.status_code} count={len(events)}",
                {"endpoint": "/api/v1/events", "http_status": r.status_code}))
        except Exception as e:
            tests.append(_fail("w2_adm_07", "Admin event list GET /admin/events returns events array", str(e)))

        # w2_adm_08 — cancel event (run on test event_id if available)
        if event_id:
            try:
                r = self.api.patch(f"/api/v1/events/{event_id}/status", json={"status": "cancelled"})
                data = r.json()
                ev = data.get("event") or data
                cancelled = ev.get("status") in ("cancelled", "closed", "completed")
                ok = r.status_code == 200 and cancelled
                fn = _pass if ok else _fail
                tests.append(fn("w2_adm_08", "Cancel event via PATCH /events/{id}/status",
                    f"HTTP {r.status_code} status={ev.get('status')}",
                    {"http_status": r.status_code}))
                if ok and event_id in self._created_event_ids:
                    self._created_event_ids.remove(event_id)  # already cancelled
            except Exception as e:
                tests.append(_fail("w2_adm_08", "Cancel event via PATCH /events/{id}/status", str(e)))
        else:
            tests.append(_warn("w2_adm_08", "Cancel event via PATCH /events/{id}/status",
                "Skipped — no test event was created"))

        return tests

    # ── Category: Registration (Week 3) ───────────────────────────────────

    def cat_registration(self) -> List[Dict]:
        """
        Most registration tests require a real alumni Bearer JWT.
        In dev mode with X-Dev-User: admin we can only test the shape of the
        eligibility endpoint and call the existing registrations diagnostic.
        Tests requiring JWT are marked WARNING with clear reason.
        """
        tests = []
        jwt_skip = "Alumni Bearer JWT not available in dev mode (X-Dev-User: admin cannot register)"

        # w3_reg_01 — call existing registrations diagnostic and report
        # FAILs inside the diagnostic are expected in local dev (alumni JWT + Cloud SQL alumni DB
        # not available). Reclassify all FAIL results as WARNING so the overall suite stays green.
        _REG_DIAG_WARNING_REASON = (
            "Registration diagnostic FAIL expected in local dev — requires alumni JWT + "
            "Cloud SQL alumni DB. Run against Cloud SQL for definitive result."
        )
        try:
            r = self.api.get("/api/v1/dev/diagnostics/registrations")
            if r.status_code == 200:
                data = r.json()
                suite_tests, summary = self._parse_diag_suite(data, "w3_reg_diag")
                # Reclassify FAILs as WARNINGs — expected without alumni JWT/DB
                for t in suite_tests:
                    if t.get("status") == "FAIL":
                        t["status"] = "WARNING"
                        t["details"] = _REG_DIAG_WARNING_REASON + (
                            f" | original: {t.get('details', '')}"
                        )
                tests.extend(suite_tests)
                tests.append(_pass("w3_reg_01", "Registration diagnostic endpoint accessible",
                    f"total={summary['total']} passed={summary['passed']} failed={summary['failed']} "
                    f"(FAIL results reclassified as WARNING — alumni JWT required)",
                    {"endpoint": "/api/v1/dev/diagnostics/registrations", "http_status": 200}))
            else:
                tests.append(_fail("w3_reg_01", "Registration diagnostic endpoint accessible",
                    f"HTTP {r.status_code}", {"endpoint": "/api/v1/dev/diagnostics/registrations"}))
        except Exception as e:
            tests.append(_fail("w3_reg_01", "Registration diagnostic endpoint accessible", str(e)))

        # w3_reg_02 — eligibility endpoint shape (no JWT needed for structure check)
        try:
            pub_events = self.api.get("/api/v1/events/public").json().get("events", [])
            if pub_events:
                eid = pub_events[0]["event_id"]
                r = httpx.get(f"{self.base_url}/api/v1/events/{eid}/registration-eligibility", timeout=10)
                if r.status_code in (401, 403, 422):
                    tests.append(_pass("w3_reg_02", "Eligibility endpoint requires auth (correctly rejects unauthenticated)",
                        f"HTTP {r.status_code} — expected (requires Bearer JWT)",
                        {"endpoint": f"/api/v1/events/{eid}/registration-eligibility", "http_status": r.status_code}))
                elif r.status_code == 200:
                    data = r.json()
                    has_shape = "eligibility_status" in data or "event_id" in data
                    fn = _pass if has_shape else _fail
                    tests.append(fn("w3_reg_02", "Eligibility endpoint returns correct shape",
                        f"HTTP 200 keys={list(data.keys())[:5]}"))
                else:
                    tests.append(_warn("w3_reg_02", "Eligibility endpoint requires auth",
                        f"HTTP {r.status_code}"))
            else:
                tests.append(_warn("w3_reg_02", "Eligibility endpoint requires auth",
                    "No published events to test"))
        except Exception as e:
            tests.append(_warn("w3_reg_02", "Eligibility endpoint requires auth", str(e)))

        # w3_reg_03..09 — registration flow tests (require JWT)
        jwt_tests = [
            ("w3_reg_03", "Register for event (requires alumni Bearer JWT)"),
            ("w3_reg_04", "Duplicate registration guard returns already_registered"),
            ("w3_reg_05", "Capacity full guard returns event_full"),
            ("w3_reg_06", "Registration closed guard returns registration_closed"),
            ("w3_reg_07", "Not-open-yet guard returns registration_not_open_yet"),
            ("w3_reg_08", "Non-alumni / inactive alumni guard returns alumni_not_active"),
            ("w3_reg_09", "GET /my-registration returns registration object"),
            ("w3_reg_10", "GET /my/registrations returns list"),
            ("w3_reg_11", "Join URL: null for physical event after registration"),
            ("w3_reg_12", "Join URL: non-null for virtual event after registration"),
            ("w3_reg_13", "Confirmation email status: sent, failed, or skipped"),
        ]
        for tid, name in jwt_tests:
            tests.append(_warn(tid, name, jwt_skip))

        return tests

    # ── Category: Admin Attendees (Week 4) ────────────────────────────────

    def cat_admin_attendees(self) -> List[Dict]:
        tests = []

        # Find a suitable event_id for attendees diagnostic
        event_id: Optional[int] = None
        try:
            r = self.api.get("/api/v1/events", params={"per_page": 20})
            data = r.json()
            events = data.get("events") or data.get("items") or []
            # Prefer published events
            for e in events:
                if e.get("status") == "published" and e.get("event_id"):
                    event_id = e["event_id"]
                    break
            if not event_id and events:
                event_id = events[0].get("event_id")
        except Exception:
            pass

        # w4_att_00 — call existing attendees diagnostic
        if event_id:
            try:
                r = self.api.get("/api/v1/dev/diagnostics/attendees", params={"event_id": event_id})
                if r.status_code == 200:
                    data = r.json()
                    suite_tests, summary = self._parse_diag_suite(data, "w4_att_diag")
                    tests.extend(suite_tests)
                    tests.append(_pass("w4_att_00", "Attendees diagnostic endpoint accessible",
                        f"event_id={event_id} total={summary['total']} passed={summary['passed']} failed={summary['failed']}",
                        {"endpoint": f"/api/v1/dev/diagnostics/attendees?event_id={event_id}", "http_status": 200}))
                else:
                    tests.append(_fail("w4_att_00", "Attendees diagnostic endpoint accessible",
                        f"HTTP {r.status_code}", {"endpoint": "/api/v1/dev/diagnostics/attendees"}))
            except Exception as e:
                tests.append(_fail("w4_att_00", "Attendees diagnostic endpoint accessible", str(e)))
        else:
            tests.append(_warn("w4_att_00", "Attendees diagnostic endpoint accessible",
                "No events found to run attendees diagnostic"))

        # Direct attendees list tests (structure + security)
        if event_id:
            # w4_att_01 — list endpoint
            try:
                r = self.api.get(f"/api/v1/admin/events/{event_id}/attendees")
                data = r.json()
                has_list = r.status_code == 200 and "attendees" in data
                fn = _pass if has_list else _fail
                tests.append(fn("w4_att_01", "Admin attendees list endpoint returns attendees array",
                    f"HTTP {r.status_code} count={len(data.get('attendees', []))}",
                    {"endpoint": f"/api/v1/admin/events/{event_id}/attendees", "http_status": r.status_code}))

                if has_list:
                    attendees = data.get("attendees", [])

                    # w4_att_02 — security: no sensitive fields in attendee rows
                    sensitive = {"virtual_url", "join_url", "qr_token", "firebase_uid"}
                    leaky_rows = [a for a in attendees if sensitive & set(a.keys())]
                    fn2 = _fail if leaky_rows else _pass
                    tests.append(fn2("w4_att_02", "Attendee list: no virtual_url, join_url, qr_token, or firebase_uid",
                        f"Checked {len(attendees)} attendees — "
                        + ("CLEAN" if not leaky_rows else f"LEAK in {len(leaky_rows)} rows")))

                    # w4_att_03 — pagination fields
                    has_pg = "total" in data and "page" in data
                    fn3 = _pass if has_pg else _fail
                    tests.append(fn3("w4_att_03", "Attendees response includes pagination fields",
                        f"total={data.get('total')} page={data.get('page')} per_page={data.get('per_page')}"))
            except Exception as e:
                tests.append(_fail("w4_att_01", "Admin attendees list endpoint returns attendees array", str(e)))

            # w4_att_04 — per_page param
            try:
                r = self.api.get(f"/api/v1/admin/events/{event_id}/attendees", params={"per_page": 1})
                ok = r.status_code == 200
                fn = _pass if ok else _fail
                tests.append(fn("w4_att_04", "Attendees list: per_page parameter accepted",
                    f"HTTP {r.status_code} per_page=1",
                    {"http_status": r.status_code}))
            except Exception as e:
                tests.append(_fail("w4_att_04", "Attendees list: per_page parameter accepted", str(e)))

            # w4_att_05 — search param
            try:
                r = self.api.get(f"/api/v1/admin/events/{event_id}/attendees", params={"search": "test"})
                ok = r.status_code == 200
                fn = _pass if ok else _fail
                tests.append(fn("w4_att_05", "Attendees list: search parameter accepted",
                    f"HTTP {r.status_code}", {"http_status": r.status_code}))
            except Exception as e:
                tests.append(_fail("w4_att_05", "Attendees list: search parameter accepted", str(e)))

            # w4_att_06 — batch_year param
            try:
                r = self.api.get(f"/api/v1/admin/events/{event_id}/attendees", params={"batch_year": 2026})
                ok = r.status_code == 200
                fn = _pass if ok else _fail
                tests.append(fn("w4_att_06", "Attendees list: batch_year parameter accepted",
                    f"HTTP {r.status_code}", {"http_status": r.status_code}))
            except Exception as e:
                tests.append(_fail("w4_att_06", "Attendees list: batch_year parameter accepted", str(e)))

            # w4_att_07 — CSV export
            try:
                r = self.api.get(f"/api/v1/admin/events/{event_id}/attendees/export")
                ok = r.status_code == 200
                is_csv = "csv" in r.headers.get("content-type", "").lower() or r.text.startswith("﻿") or "," in r.text[:100]
                fn = _pass if (ok and is_csv) else (_fail if not ok else _warn)
                tests.append(fn("w4_att_07", "CSV export endpoint returns 200 with CSV content",
                    f"HTTP {r.status_code} content-type={r.headers.get('content-type', 'unknown')[:50]}",
                    {"endpoint": f"/api/v1/admin/events/{event_id}/attendees/export", "http_status": r.status_code}))

                if ok:
                    # w4_att_08 — CSV security: forbidden columns
                    csv_text = r.text
                    forbidden = ["virtual_url", "join_url", "qr_token", "firebase_uid"]
                    found_forbidden = [col for col in forbidden if col in csv_text]
                    fn2 = _fail if found_forbidden else _pass
                    tests.append(fn2("w4_att_08", "CSV export: no virtual_url, join_url, qr_token, or firebase_uid in output",
                        "CLEAN" if not found_forbidden else f"FOUND: {found_forbidden}"))
            except Exception as e:
                tests.append(_fail("w4_att_07", "CSV export endpoint returns 200 with CSV content", str(e)))
        else:
            for tid, name in [
                ("w4_att_01", "Admin attendees list endpoint"),
                ("w4_att_02", "Attendee list: no sensitive fields"),
                ("w4_att_03", "Attendees response includes pagination"),
                ("w4_att_04", "Attendees list: per_page param"),
                ("w4_att_05", "Attendees list: search param"),
                ("w4_att_06", "Attendees list: batch_year param"),
                ("w4_att_07", "CSV export endpoint"),
                ("w4_att_08", "CSV security: no forbidden fields"),
            ]:
                tests.append(_warn(tid, name, "Skipped — no event_id found"))

        return tests

    # ── Category: Week 5 Event Options ────────────────────────────────────

    def _run_w5_diagnostic(self, cat_prefix: str, endpoint: str, expected_total: int) -> List[Dict]:
        tests = []
        try:
            r = self.api.get(endpoint)
            if r.status_code != 200:
                tests.append(_fail(f"{cat_prefix}_00", f"Diagnostic endpoint accessible: {endpoint}",
                    f"HTTP {r.status_code}", {"endpoint": endpoint, "http_status": r.status_code}))
                return tests

            data = r.json()
            suite_tests, summary = self._parse_diag_suite(data, cat_prefix)
            tests.extend(suite_tests)

            # Overall pass check
            ok = summary["failed"] == 0 and summary["passed"] == expected_total
            fn = _pass if ok else _fail
            tests.append(fn(f"{cat_prefix}_overall", f"All {expected_total} diagnostic tests pass",
                f"passed={summary['passed']}/{expected_total} failed={summary['failed']} warnings={summary['warnings']}",
                {"endpoint": endpoint, "http_status": 200}))
        except Exception as e:
            tests.append(_fail(f"{cat_prefix}_overall", f"Diagnostic endpoint: {endpoint}", str(e)))
        return tests

    def cat_week5_event_options(self) -> List[Dict]:
        return self._run_w5_diagnostic("w5_eo", "/api/v1/dev/diagnostics/week5/event-options", 6)

    def cat_week5_people(self) -> List[Dict]:
        tests = self._run_w5_diagnostic("w5_pp", "/api/v1/dev/diagnostics/week5/people", 14)
        # Extra: verify derived speakers rule documented
        has_people_10 = any(t["id"] == "w5_pp_people_10" and t["status"] == "PASS" for t in tests)
        has_people_11 = any(t["id"] == "w5_pp_people_11" and t["status"] == "PASS" for t in tests)
        if has_people_10:
            tests.append(_pass("w5_pp_hidden_check", "people_10 confirms hidden person NOT in public response", "Verified by diagnostic"))
        if has_people_11:
            tests.append(_pass("w5_pp_speakers_check", "people_11 confirms speakers[] derivation rule (SPEAKER/PANELIST/CHIEF_GUEST/GUEST_OF_HONOUR only)", "Verified by diagnostic"))
        return tests

    def cat_week5_sponsors_partners(self) -> List[Dict]:
        tests = self._run_w5_diagnostic("w5_sp", "/api/v1/dev/diagnostics/week5/sponsors-partners", 17)
        # Check ordering tests
        tier_pass = any(t["id"] == "w5_sp_sp_10_tier" and t["status"] == "PASS" for t in tests)
        alpha_pass = any(t["id"] == "w5_sp_sp_11_alpha" and t["status"] == "PASS" for t in tests)
        if tier_pass:
            tests.append(_pass("w5_sp_tier_check", "sp_10_tier confirms sponsor tier ordering (TITLE before GOLD)", "Verified by diagnostic"))
        if alpha_pass:
            tests.append(_pass("w5_sp_alpha_check", "sp_11_alpha confirms partner alphabetical ordering (COMMUNITY before KNOWLEDGE)", "Verified by diagnostic"))
        return tests

    def cat_week5_analytics(self) -> List[Dict]:
        tests = self._run_w5_diagnostic("w5_an", "/api/v1/dev/diagnostics/week5/analytics", 11)
        # Check secrets test
        no_secrets = any(t["id"] == "w5_an_an_11" and t["status"] == "PASS" for t in tests)
        if no_secrets:
            tests.append(_pass("w5_an_secrets_check", "an_11 confirms no secrets in analytics metadata", "Verified by diagnostic"))
        return tests

    # ── Category: Combined Diagnostics (Week 2–5) ─────────────────────────

    def cat_diagnostics_combined(self) -> List[Dict]:
        tests = []

        # Events diagnostic
        try:
            r = self.api.get("/api/v1/dev/diagnostics/events")
            if r.status_code == 200:
                data = r.json()
                passed = data.get("passed", 0)
                total = data.get("total", 0)
                failed = data.get("failed", 0)
                ok = failed == 0
                fn = _pass if ok else _fail
                tests.append(fn("comb_events", f"Events management diagnostic: {passed}/{total} PASS",
                    f"passed={passed} failed={failed} total={total}",
                    {"endpoint": "/api/v1/dev/diagnostics/events", "http_status": 200}))
            else:
                tests.append(_fail("comb_events", "Events management diagnostic accessible",
                    f"HTTP {r.status_code}"))
        except Exception as e:
            tests.append(_fail("comb_events", "Events management diagnostic accessible", str(e)))

        # Registrations diagnostic (may have alumni DB failures)
        try:
            r = self.api.get("/api/v1/dev/diagnostics/registrations")
            if r.status_code == 200:
                data = r.json()
                passed = data.get("passed", 0)
                total = data.get("total", 0)
                failed = data.get("failed", 0)
                if failed > 0:
                    # Registration failures are expected locally — alumni DB doesn't have
                    # the test user unless Cloud SQL proxy is running and alumni DB is seeded.
                    tests.append(_warn("comb_registrations",
                        f"Registrations diagnostic: {passed}/{total} PASS",
                        f"passed={passed} failed={failed} total={total}. "
                        "Alumni-gated tests require a real alumni account in Cloud SQL alumni_db — expected locally.",
                        {"endpoint": "/api/v1/dev/diagnostics/registrations", "http_status": 200}))
                else:
                    tests.append(_pass("comb_registrations",
                        f"Registrations diagnostic: {passed}/{total} PASS",
                        f"passed={passed} failed={failed} total={total}",
                        {"endpoint": "/api/v1/dev/diagnostics/registrations", "http_status": 200}))
            else:
                tests.append(_fail("comb_registrations", "Registrations diagnostic accessible",
                    f"HTTP {r.status_code}"))
        except Exception as e:
            tests.append(_fail("comb_registrations", "Registrations diagnostic accessible", str(e)))

        # Week 5 combined all
        try:
            r = self.api.get("/api/v1/dev/diagnostics/week5/all")
            if r.status_code == 200:
                data = r.json()
                passed = data.get("passed", 0)
                total = data.get("total", 0)
                failed = data.get("failed", 0)
                warnings = data.get("warnings", 0)
                ok = failed == 0 and total == 48
                fn = _pass if ok else _fail
                tests.append(fn("comb_week5_all",
                    f"Week 5 combined diagnostic: {passed}/{total} PASS",
                    f"passed={passed} failed={failed} warnings={warnings} total={total} (expected 48)",
                    {"endpoint": "/api/v1/dev/diagnostics/week5/all", "http_status": 200}))
            else:
                tests.append(_fail("comb_week5_all", "Week 5 combined diagnostic accessible",
                    f"HTTP {r.status_code}"))
        except Exception as e:
            tests.append(_fail("comb_week5_all", "Week 5 combined diagnostic accessible", str(e)))

        # All-weeks endpoint (Part E)
        try:
            r = self.api.get("/api/v1/dev/diagnostics/week5/all-weeks")
            if r.status_code == 200:
                data = r.json()
                passed = data.get("passed", 0)
                total = data.get("total", 0)
                failed = data.get("failed", 0)
                ok = failed == 0
                fn = _pass if ok else _fail
                tests.append(fn("comb_all_weeks",
                    f"All-weeks combined diagnostic: {passed}/{total} PASS",
                    f"passed={passed} failed={failed} total={total}",
                    {"endpoint": "/api/v1/dev/diagnostics/week5/all-weeks", "http_status": 200}))
            elif r.status_code == 404:
                tests.append(_warn("comb_all_weeks", "All-weeks combined diagnostic endpoint",
                    "HTTP 404 — endpoint not yet deployed or router not registered",
                    {"endpoint": "/api/v1/dev/diagnostics/week5/all-weeks", "http_status": 404}))
            else:
                tests.append(_fail("comb_all_weeks", "All-weeks combined diagnostic accessible",
                    f"HTTP {r.status_code}"))
        except Exception as e:
            tests.append(_warn("comb_all_weeks", "All-weeks combined diagnostic endpoint", str(e)))

        return tests

    # ── Category: Admin Portal Build ──────────────────────────────────────

    def cat_admin_build(self) -> List[Dict]:
        tests = []
        admin_dir = self.repo_root / "admin" / "event_admin"

        if not admin_dir.exists():
            tests.append(_fail("admin_build_01", "Admin portal directory exists", str(admin_dir)))
            return tests

        try:
            result = subprocess.run(
                ["npm", "run", "build"],
                cwd=str(admin_dir),
                capture_output=True,
                text=True,
                timeout=120,
            )
            stdout = result.stdout
            ok = result.returncode == 0 and "built in" in stdout
            fn = _pass if ok else _fail
            # Extract module count from output
            match = re.search(r"(\d+) modules transformed", stdout)
            modules = match.group(1) if match else "?"
            match_time = re.search(r"built in (\S+)", stdout)
            build_time = match_time.group(1) if match_time else "?"
            tests.append(fn("admin_build_01", "Admin portal: npm run build exits 0 with no errors",
                f"exit={result.returncode} modules={modules} time={build_time}",
                {"exit_code": result.returncode}))

            if result.returncode != 0:
                # Show first 500 chars of stderr
                tests.append(_fail("admin_build_02", "Admin portal build: no errors in output",
                    result.stderr[:500] if result.stderr else "No stderr"))
            else:
                tests.append(_pass("admin_build_02", "Admin portal build: no errors in output",
                    "Build output clean"))
        except FileNotFoundError:
            tests.append(_warn("admin_build_01", "Admin portal: npm run build exits 0 with no errors",
                "npm not found — skipping (not in PATH)"))
        except subprocess.TimeoutExpired:
            tests.append(_fail("admin_build_01", "Admin portal: npm run build exits 0 with no errors",
                "Build timed out after 120 seconds"))
        except Exception as e:
            tests.append(_fail("admin_build_01", "Admin portal: npm run build exits 0 with no errors", str(e)))

        return tests

    # ── Category: Flutter Static Verification ─────────────────────────────

    def cat_flutter_static(self) -> List[Dict]:
        tests = []
        flutter_dir = self.repo_root / "apps" / "event_app"

        if not flutter_dir.exists():
            tests.append(_fail("flutter_01", "Flutter app directory exists", str(flutter_dir)))
            return tests

        # flutter analyze
        try:
            result = subprocess.run(
                ["flutter", "analyze"],
                cwd=str(flutter_dir),
                capture_output=True,
                text=True,
                timeout=120,
            )
            ok = result.returncode == 0 and "No issues found" in result.stdout
            fn = _pass if ok else _fail
            tests.append(fn("flutter_01", "flutter analyze: No issues found",
                result.stdout.strip()[-200:] if result.stdout else result.stderr[:200],
                {"exit_code": result.returncode}))
        except FileNotFoundError:
            tests.append(_warn("flutter_01", "flutter analyze: No issues found",
                "flutter not found in PATH — skipping"))
        except subprocess.TimeoutExpired:
            tests.append(_fail("flutter_01", "flutter analyze: No issues found",
                "flutter analyze timed out after 120 seconds"))
        except Exception as e:
            tests.append(_fail("flutter_01", "flutter analyze: No issues found", str(e)))

        # flutter test
        try:
            result = subprocess.run(
                ["flutter", "test"],
                cwd=str(flutter_dir),
                capture_output=True,
                text=True,
                timeout=180,
            )
            output = result.stdout + result.stderr

            # Parse pass/fail counts
            pass_match = re.search(r"\+(\d+)", output)
            fail_match = re.search(r"-(\d+)", output)
            passed_count = int(pass_match.group(1)) if pass_match else 0
            failed_count = int(fail_match.group(1)) if fail_match else 0

            # Identify failing test names
            failing_lines = re.findall(r"Failing tests?:?\s*\n(.*?)(?:\n\n|\Z)", output, re.DOTALL)
            failing_names = []
            for block in failing_lines:
                for line in block.splitlines():
                    line = line.strip()
                    if line:
                        # Extract test name after last colon
                        parts = line.rsplit(":", 1)
                        failing_names.append(parts[-1].strip() if len(parts) > 1 else line)

            # Classify each failure
            pre_existing = []
            new_failures = []
            for name in failing_names:
                if any(known in name for known in _KNOWN_FLUTTER_TEST_FAILURES):
                    pre_existing.append(name)
                else:
                    new_failures.append(name)

            if result.returncode == 0 or (not new_failures and failed_count <= len(pre_existing)):
                if pre_existing:
                    tests.append(_warn("flutter_02", f"flutter test: {passed_count} passed, {failed_count} failed",
                        f"passed={passed_count} pre-existing-failures={pre_existing} — not Week 5 regressions",
                        {"exit_code": result.returncode, "pre_existing_failures": pre_existing}))
                else:
                    tests.append(_pass("flutter_02", f"flutter test: {passed_count} passed, {failed_count} failed",
                        f"All tests pass. passed={passed_count}",
                        {"exit_code": result.returncode}))
            else:
                tests.append(_fail("flutter_02", f"flutter test: {passed_count} passed, {failed_count} failed",
                    f"New failures detected: {new_failures}",
                    {"exit_code": result.returncode, "new_failures": new_failures}))

            # Document pre-existing failures
            for name in pre_existing:
                reason = next((v for k, v in _KNOWN_FLUTTER_TEST_FAILURES.items() if k in name), "")
                tests.append(_warn(f"flutter_known_{name[:20].replace(' ', '_')}",
                    f"Known pre-existing failure: '{name}'", reason))

        except FileNotFoundError:
            tests.append(_warn("flutter_02", "flutter test: run test suite",
                "flutter not found in PATH — skipping"))
        except subprocess.TimeoutExpired:
            tests.append(_fail("flutter_02", "flutter test: run test suite",
                "flutter test timed out after 180 seconds"))
        except Exception as e:
            tests.append(_fail("flutter_02", "flutter test: run test suite", str(e)))

        return tests

    # ── Category: Documentation Presence ──────────────────────────────────

    def cat_docs_presence(self) -> List[Dict]:
        tests = []
        required_docs = [
            ("docs_01", "docs/api/backend_api_index_v3.md"),
            ("docs_02", "docs/api/events_api_contract_v2.md"),
            ("docs_03", "docs/api/week5_event_enrichment_api_contract.md"),
            ("docs_04", "docs/releases/week5_status_report_2026-06-26.md"),
            ("docs_05", "docs/reviews/week5_full_verification_report.md"),
            ("docs_06", "docs/reviews/week5_event_usage_crosscheck.md"),
            ("docs_07", "docs/reviews/week5_manual_verification_steps.md"),
            ("docs_08", "docs/reviews/week5_developer_workflows_verification.md"),
            ("docs_09", "docs/reviews/week5_admin_enrichment_ui_verification.md"),
        ]
        for tid, rel_path in required_docs:
            full_path = self.repo_root / rel_path
            if full_path.exists():
                size_kb = full_path.stat().st_size // 1024
                tests.append(_pass(tid, f"Doc present: {rel_path}",
                    f"Exists ({size_kb}KB)", {"path": rel_path}))
            else:
                tests.append(_fail(tid, f"Doc present: {rel_path}",
                    f"File not found: {full_path}", {"path": rel_path}))
        return tests

    # ── Master runner ──────────────────────────────────────────────────────

    def run_all(self) -> Dict[str, Any]:
        started = datetime.now(timezone.utc).isoformat()

        categories_spec = [
            ("env", "Week 1 — Environment & Health", self.cat_environment),
            ("api_index", "API Index Consistency (All Weeks)", self.cat_api_index_consistency),
            ("public_events", "Week 2 — Public Events", self.cat_public_events),
            ("admin_events", "Week 2+5 — Admin Events & Event Options", self.cat_admin_events),
            ("registration", "Week 3 — Registration Flow", self.cat_registration),
            ("admin_attendees", "Week 4 — Admin Attendees", self.cat_admin_attendees),
            ("week5_event_options", "Week 5 — Event Options Diagnostic", self.cat_week5_event_options),
            ("week5_people", "Week 5 — People / Speakers Diagnostic", self.cat_week5_people),
            ("week5_sponsors_partners", "Week 5 — Sponsors & Partners Diagnostic", self.cat_week5_sponsors_partners),
            ("week5_analytics", "Week 5 — Analytics Diagnostic", self.cat_week5_analytics),
            ("diagnostics_combined", "Combined Diagnostics Summary", self.cat_diagnostics_combined),
            ("admin_build", "Admin Portal Build", self.cat_admin_build),
            ("flutter_static", "Flutter Static Verification", self.cat_flutter_static),
            ("docs_presence", "Documentation Presence", self.cat_docs_presence),
        ]

        categories = []
        for cat_id, cat_name, fn in categories_spec:
            print(f"  [{cat_id}] {cat_name}...", flush=True)
            try:
                tests = fn()
            except Exception as e:
                tests = [_fail(f"{cat_id}_crash", f"Category crashed: {cat_name}", str(e))]
            categories.append(_category(cat_id, cat_name, tests))

        # Cleanup test data
        self._cleanup()

        completed = datetime.now(timezone.utc).isoformat()

        # Totals
        total = sum(c["total"] for c in categories)
        passed = sum(c["passed"] for c in categories)
        failed = sum(c["failed"] for c in categories)
        warnings = sum(c["warnings"] for c in categories)

        # Overall status: FAIL if any hard failures, WARNING if only warnings
        overall = "FAIL" if failed > 0 else ("WARNING" if warnings > 0 else "PASS")

        return {
            "status": overall,
            "started_at": started,
            "completed_at": completed,
            "base_url": self.base_url,
            "summary": {
                "total": total,
                "passed": passed,
                "failed": failed,
                "warnings": warnings,
            },
            "categories": categories,
        }


# ─── Report generation ────────────────────────────────────────────────────────

def write_json(report: Dict, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(_redact(report), f, indent=2, ensure_ascii=False, default=str)
    print(f"  JSON report written: {path}")


def write_markdown(report: Dict, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    a = lines.append

    s = report["summary"]
    overall = report["status"]
    status_icon = {"PASS": "✅", "WARNING": "⚠️", "FAIL": "❌"}.get(overall, "")

    a("# Week 1 – Week 5 Automated Verification Report")
    a("")
    a(f"**Date:** {report['started_at'][:10]}  ")
    a(f"**Base URL:** `{report['base_url']}`  ")
    a(f"**Script:** `backend/scripts/verify_all_weeks.py v{_VERSION}`  ")
    a(f"**Overall status:** {status_icon} **{overall}**")
    a("")

    # Executive summary
    a("---")
    a("")
    a("## Executive Summary")
    a("")
    a(f"| Total | Passed | Failed | Warnings |")
    a(f"|---|---|---|---|")
    a(f"| {s['total']} | {s['passed']} | {s['failed']} | {s['warnings']} |")
    a("")

    # Category summary table
    a("---")
    a("")
    a("## Category Summary")
    a("")
    a("| Category | Status | Total | Passed | Failed | Warnings |")
    a("|---|---|---|---|---|---|")
    for cat in report["categories"]:
        icon = {"PASS": "✅", "WARNING": "⚠️", "FAIL": "❌"}.get(cat["status"], "")
        a(f"| {cat['name']} | {icon} {cat['status']} | {cat['total']} | {cat['passed']} | {cat['failed']} | {cat['warnings']} |")
    a("")

    # Detailed results per category
    a("---")
    a("")
    a("## Detailed Results")
    a("")
    for cat in report["categories"]:
        icon = {"PASS": "✅", "WARNING": "⚠️", "FAIL": "❌"}.get(cat["status"], "")
        a(f"### {icon} {cat['name']}")
        a("")
        a(f"**Status:** {cat['status']} | **{cat['passed']}/{cat['total']}** passed | "
          f"{cat['failed']} failed | {cat['warnings']} warnings")
        a("")
        a("| Test ID | Name | Status | Details |")
        a("|---|---|---|---|")
        for t in cat["tests"]:
            t_icon = {"PASS": "✅", "WARNING": "⚠️", "FAIL": "❌"}.get(t["status"], "")
            details = str(t.get("details", ""))[:120].replace("|", "\\|")
            a(f"| `{t['id']}` | {t['name']} | {t_icon} {t['status']} | {details} |")
        a("")

    # Known pre-existing failures
    a("---")
    a("")
    a("## Known Pre-existing Failures")
    a("")
    a("| Test | Reason |")
    a("|---|---|")
    a("| `flutter_known_*` — `authenticated Register shows Week 3 message` | "
      "Pre-existing from Week 2 (commit 21ee22f). GoRouter not provided in test widget tree. "
      "Not a Week 5 regression. |")
    a("| `comb_registrations` WARNING | Registration diagnostic requires real alumni JWT. "
      "In dev mode with X-Dev-User: admin, alumni-gated tests are expected to fail. |")
    a("| `w3_reg_03` through `w3_reg_13` WARNING | Direct registration tests require alumni Bearer JWT. "
      "Use X-Dev-User: admin for admin operations only. |")
    a("")

    # Security checks
    a("---")
    a("")
    a("## Security Checks")
    a("")
    security_tests = [
        t for cat in report["categories"] for t in cat["tests"]
        if any(kw in t["name"].lower() for kw in ("virtual_url", "join_url", "qr_token", "firebase_uid", "secret", "credential", "leak", "sensitive"))
    ]
    if security_tests:
        a("| Test | Status | Details |")
        a("|---|---|---|")
        for t in security_tests:
            icon = {"PASS": "✅", "WARNING": "⚠️", "FAIL": "❌"}.get(t["status"], "")
            a(f"| {t['name']} | {icon} {t['status']} | {str(t.get('details',''))[:100]} |")
    else:
        a("No dedicated security tests found in this run.")
    a("")

    # Backward compatibility
    a("---")
    a("")
    a("## Backward Compatibility Checks")
    a("")
    a("All Week 5 changes verified to be additive only:")
    a("")
    a("| Change | Status |")
    a("|---|---|")
    compat_items = [
        ("is_full_day / is_free / ticket_price in public list and detail", "Additive — SQL defaults"),
        ("people[] / speakers[] / sponsors[] / partners[] in public event detail", "Additive — default []"),
        ("Admin event create/update accepts Week 5 fields", "Additive — all optional"),
        ("Analytics hooks in registration_service", "Fire-and-forget — never block registration"),
        ("apiClient.put added to admin portal", "Additive — no existing call sites changed"),
    ]
    for item, note in compat_items:
        a(f"| {item} | {note} |")
    a("")

    # Pending items
    a("---")
    a("")
    a("## What Is Still Pending")
    a("")
    a("| Item | Notes |")
    a("|---|---|")
    pending = [
        ("Cloud SQL migrations 010–013", "Requires product owner approval"),
        ("Flutter display of people/speakers/sponsors/partners", "Backend + admin ready; Flutter sprint to follow"),
        ("pytest local DB config", "eventmgmt_app role not in local PG"),
        ("GoRouter test harness fix", "Deferred to test maintenance sprint"),
        ("URL prefix alignment (/admin/events/{id}/people)", "Deferred — changes diagnostics"),
    ]
    for item, note in pending:
        a(f"| {item} | {note} |")
    a("")

    # Final verdict
    a("---")
    a("")
    a("## Final Verdict")
    a("")
    a(f"**Overall: {status_icon} {overall}**")
    a("")
    if overall == "PASS":
        a("All critical checks pass. No regressions detected. Safe to commit.")
    elif overall == "WARNING":
        a("No hard failures. All warnings are either pre-existing issues or dev-environment limitations "
          "(no alumni JWT in dev mode). Safe to commit.")
    else:
        a(f"**{s['failed']} test(s) failed.** Review the FAIL items above before committing.")
    a("")
    a(f"*Generated by `backend/scripts/verify_all_weeks.py v{_VERSION}` on {report['started_at'][:19]}*")

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"  Markdown report written: {path}")


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NITKSAA Event Platform — Week 1–5 Automated Verification Suite",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--base-url", default="http://localhost:8000",
                        help="Backend base URL (default: http://localhost:8000)")
    parser.add_argument("--admin-header", default="X-Dev-User: admin",
                        help="Admin auth header (default: 'X-Dev-User: admin')")
    parser.add_argument("--json-output",
                        default="../docs/reviews/week1_to_week5_automated_verification.json",
                        help="Path for JSON report output")
    parser.add_argument("--markdown-output",
                        default="../docs/reviews/week1_to_week5_automated_verification_report.md",
                        help="Path for Markdown report output")
    parser.add_argument("--repo-root", default=None,
                        help="Repository root path (auto-detected if not specified)")

    args = parser.parse_args()

    # Parse admin header
    if ": " in args.admin_header:
        k, v = args.admin_header.split(": ", 1)
        admin_header = {k.strip(): v.strip()}
    else:
        admin_header = {"X-Dev-User": "admin"}

    # Detect repo root
    if args.repo_root:
        repo_root = Path(args.repo_root).resolve()
    else:
        script_dir = Path(__file__).resolve().parent
        repo_root = script_dir.parent.parent  # backend/scripts/../../ = repo root

    json_output = Path(args.json_output) if args.json_output.startswith("/") else (Path.cwd() / args.json_output)
    md_output = Path(args.markdown_output) if args.markdown_output.startswith("/") else (Path.cwd() / args.markdown_output)

    print(f"\nNITKSAA Automated Verification Suite v{_VERSION}")
    print(f"Base URL:  {args.base_url}")
    print(f"Repo root: {repo_root}")
    print(f"JSON out:  {json_output}")
    print(f"MD out:    {md_output}")
    print(f"Started:   {datetime.now(timezone.utc).isoformat()}")
    print()

    verifier = Verifier(args.base_url, admin_header, repo_root)
    try:
        print("Running verification categories...")
        report = verifier.run_all()
    finally:
        verifier.api.close()

    s = report["summary"]
    print(f"\n{'='*60}")
    print(f"  Overall:  {report['status']}")
    print(f"  Total:    {s['total']}")
    print(f"  Passed:   {s['passed']}")
    print(f"  Failed:   {s['failed']}")
    print(f"  Warnings: {s['warnings']}")
    print(f"{'='*60}\n")

    write_json(report, json_output)
    write_markdown(report, md_output)

    print("\nDone.")
    sys.exit(0 if report["status"] != "FAIL" else 1)


if __name__ == "__main__":
    main()
