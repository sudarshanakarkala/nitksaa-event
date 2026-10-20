"""Reads an event sheet's tabs from Google Sheets (B7).

The server signs in as its own Cloud Run service account (Google's default
credentials; no keys) with read-only access. Organisers share their sheet
with that account as Viewer; nothing else can be read.

Two calls: the sheet's tab names, then the wanted tabs' cells in one
batchGet, as UNFORMATTED_VALUE with SERIAL_NUMBER dates (what
sheet_parser expects).
"""
from __future__ import annotations

import asyncio
import re
from typing import Any, Dict, List, Optional

import httpx

from app.config import get_settings

SCOPE = "https://www.googleapis.com/auth/spreadsheets.readonly"
API = "https://sheets.googleapis.com/v4/spreadsheets"
TABS = ("event", "sessions", "speakers", "sponsors")
_ID = re.compile(r"/spreadsheets/d/([A-Za-z0-9_-]{20,})")
_BARE_ID = re.compile(r"^[A-Za-z0-9_-]{30,}$")

_credentials = None


class SheetAccessError(Exception):
    """The sheet couldn't be read. `code` for the app, `message` for people."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def spreadsheet_id(link: str) -> Optional[str]:
    """The sheet's id from a link (or a bare id); None if it isn't one."""
    link = (link or "").strip()
    m = _ID.search(link)
    if m:
        return m.group(1)
    return link if _BARE_ID.match(link) else None


def canonical_link(sheet_id: str) -> str:
    return f"https://docs.google.com/spreadsheets/d/{sheet_id}/edit"


def _share_hint() -> str:
    return f"Share it as Viewer with {get_settings().sheets_reader_email}."


def _token_sync() -> str:
    global _credentials
    import google.auth
    from google.auth.transport.requests import Request

    if _credentials is None:
        _credentials, _ = google.auth.default(scopes=[SCOPE])
    if not _credentials.valid:
        _credentials.refresh(Request())
    return _credentials.token


async def _token() -> str:
    try:
        return await asyncio.to_thread(_token_sync)
    except Exception as exc:  # noqa: BLE001 — no credentials on this machine, metadata server down…
        raise SheetAccessError(
            "sheets_unavailable",
            "The app can't reach Google Sheets right now. Try again in a minute.",
        ) from exc


def _problem(response: httpx.Response) -> SheetAccessError:
    try:
        error = response.json().get("error", {})
    except ValueError:
        error = {}
    status = error.get("status", "")
    text = str(error.get("message", ""))
    if response.status_code == 403 and ("SERVICE_DISABLED" in str(error) or "has not been used" in text or "is disabled" in text):
        return SheetAccessError("sheets_api_disabled", "Google Sheets isn't switched on for the app yet (an administrator setting).")
    if response.status_code in (403, 401) or status == "PERMISSION_DENIED":
        return SheetAccessError("sheet_not_shared", "The app can't open this sheet. " + _share_hint())
    if response.status_code == 404:
        return SheetAccessError("sheet_not_found", "There's no sheet at this link. Copy the link from the sheet's address bar.")
    if response.status_code == 400 and "not supported for this document" in text:
        return SheetAccessError("sheet_not_google", "This is an Excel file in Drive, not a Google Sheet. Open it and use File → Save as Google Sheets, then share that.")
    if response.status_code == 429:
        return SheetAccessError("sheets_busy", "Google Sheets is busy. Try again in a minute.")
    return SheetAccessError("sheets_unavailable", "The app can't read Google Sheets right now. Try again in a minute.")


async def read_tabs(sheet_id: str) -> Dict[str, List[List[Any]]]:
    """{tab name: rows of cell values} for the Event, Sessions, Speakers and
    Sponsors tabs the sheet has (missing tabs are left out)."""
    token = await _token()
    headers = {"Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(timeout=20.0) as client:
        try:
            meta = await client.get(
                f"{API}/{sheet_id}",
                params={"fields": "sheets.properties.title"},
                headers=headers,
            )
            if meta.status_code != 200:
                raise _problem(meta)
            titles = [s["properties"]["title"] for s in meta.json().get("sheets", [])]
            wanted = [t for t in titles if t.strip().casefold() in TABS]
            if not wanted:
                raise SheetAccessError(
                    "sheet_no_tabs",
                    "This sheet has none of the tabs Event, Sessions, Speakers or Sponsors. Make it from the template.",
                )
            values = await client.get(
                f"{API}/{sheet_id}/values:batchGet",
                params=[("ranges", f"'{t}'!A1:Z{1 + 600}") for t in wanted]
                + [
                    ("valueRenderOption", "UNFORMATTED_VALUE"),
                    ("dateTimeRenderOption", "SERIAL_NUMBER"),
                    ("majorDimension", "ROWS"),
                ],
                headers=headers,
            )
            if values.status_code != 200:
                raise _problem(values)
        except httpx.HTTPError as exc:
            raise SheetAccessError("sheets_unavailable", "The app can't reach Google Sheets right now. Try again in a minute.") from exc
    ranges = values.json().get("valueRanges", [])
    return {t: (r.get("values") or []) for t, r in zip(wanted, ranges)}
