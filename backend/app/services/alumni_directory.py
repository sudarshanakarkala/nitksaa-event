"""Fills speakers' details from the NITKSAA alumni directory.

The Partner API's `directory:profile` scope, batch lookup by email:
  POST {base}/alumni/profile/lookup  {"emails": [...]}  (up to 100; one request)
  -> {"results": [{"query": email, "matches": [record, ...]}, ...]}
Records carry alumni_id, graduationyear, branch, email, phone,
secondaryphone, linkedin, … A speaker gets only what the sheet left blank:
the sheet always wins.

Off when NITKSAA_PARTNER_API_KEY isn't set. A lookup never stops a Refresh:
problems come back as warnings.
"""
from __future__ import annotations

import re
from typing import Any, Dict, List

import httpx

from app.config import get_settings

BATCH = 100


def _batch_text(record: Dict[str, Any]) -> str | None:
    branch = (record.get("branch") or "").strip()
    year = record.get("graduationyear")
    if branch and year:
        return f"{branch}, {year}"
    return branch or (str(year) if year else None)


def _phone(record: Dict[str, Any]) -> str | None:
    phone = (record.get("phone") or "").strip()
    if phone:
        return phone
    for part in re.split(r"[,;/]", record.get("secondaryphone") or ""):
        if part.strip():
            return part.strip()
    return None


def _link(url: str | None) -> str | None:
    url = (url or "").strip()
    if not url:
        return None
    if not url.lower().startswith(("http://", "https://")):
        url = "https://" + url
    return "https://" + url[len("http://"):] if url.lower().startswith("http://") else url


async def fill_speakers(speakers: List[Dict[str, Any]]) -> List[str]:
    """Fills blanks in `speakers` (sheet_parser's dicts) in place. Returns warnings."""
    settings = get_settings()
    key = (settings.nitksaa_partner_api_key or "").strip()
    emails = sorted({s["email"] for s in speakers if s.get("email")})
    if not key or not emails:
        return []
    found: Dict[str, List[Dict[str, Any]]] = {}
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            for i in range(0, len(emails), BATCH):
                r = await client.post(
                    f"{settings.alumni_directory_api_base.rstrip('/')}/alumni/profile/lookup",
                    json={"emails": emails[i:i + BATCH]},
                    headers={"X-API-Key": key},
                )
                if r.status_code != 200:
                    return [f"The alumni directory didn't answer (error {r.status_code}); batch and LinkedIn weren't filled in."]
                for entry in r.json().get("results", []):
                    found[str(entry.get("query", "")).strip().lower()] = entry.get("matches") or []
    except (httpx.HTTPError, ValueError):
        return ["The alumni directory couldn't be reached; batch and LinkedIn weren't filled in."]

    warnings: List[str] = []
    for s in speakers:
        matches = found.get(s.get("email") or "", [])
        if len(matches) > 1:
            warnings.append(f"Speakers, row {s['row']}: {s['email']} is on {len(matches)} alumni records, so none was used.")
            continue
        if not matches:
            continue
        record = matches[0]
        s["alumni_id"] = record.get("alumni_id") or None
        if not s.get("batch"):
            s["batch"] = _batch_text(record)
        if not s.get("linkedin_url"):
            s["linkedin_url"] = _link(record.get("linkedin"))
        if not s.get("phone"):
            s["phone"] = _phone(record)
    return warnings
