#!/usr/bin/env python3
"""
Week 2 test-event seeder.

Creates 10 realistic events covering all supported statuses, both event types,
and a spread of past / current-month / future dates.

NOTE: The seed plan referenced 'registration_open' and 'archived' statuses.
      The actual schema supports only: draft | published | cancelled | completed
      Events 5-6 (plan: registration_open) → published
      Events 9-10 (plan: archived)         → completed

Usage (from repo root):
    cd backend
    python scripts/seed_week2_events.py
"""

import asyncio
import os
import re
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone
from pathlib import Path

import asyncpg
from dotenv import load_dotenv

# Load .env from backend directory
load_dotenv(Path(__file__).parent.parent / ".env")

EVENTS_DB_URL = os.getenv("EVENTS_DB_URL", "postgresql://ananth@localhost:5432/events_db")
SEED_UID      = "seed-admin-firebase-uid"  # dev placeholder — no real Firebase user needed

_now = datetime.now(timezone.utc)


def _slug(title: str) -> str:
    s = title.lower()
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"\s+", "-", s.strip())
    return re.sub(r"-+", "-", s)


async def _unique_slug(conn: asyncpg.Connection, base: str) -> str:
    slug, n = base, 2
    while await conn.fetchval("SELECT 1 FROM events WHERE slug = $1", slug):
        slug = f"{base}-{n}"
        n += 1
    return slug


# ── Event definitions ────────────────────────────────────────────────────────
#
# start_days: offset from now (+future / -past)
# hours:      event duration in hours
# published:  whether to back-fill published_at (used only when status=published/completed)

EVENTS = [
    # ── 1  published | physical ──────────────────────────────────────────────
    {
        "title":         "Breakfast Club Bangalore",
        "tagline":       "Morning networking for NITK alumni",
        "description":   "Join fellow NITK alumni for a relaxed breakfast and networking in Bangalore.",
        "status":        "published",
        "is_virtual":    False,
        "location_text": "The Leela Palace, Bangalore",
        "capacity":      30,
        "start_days":    15,
        "hours":         3,
    },
    # ── 2  published | virtual ───────────────────────────────────────────────
    {
        "title":       "Webinar on AI",
        "tagline":     "Exploring the frontiers of artificial intelligence",
        "description": "Deep-dive on the latest AI/ML trends, featuring NITK alumni researchers.",
        "status":      "published",
        "is_virtual":  True,
        "virtual_url": "https://meet.google.com/nitk-ai-webinar",
        "capacity":    100,
        "start_days":  20,
        "hours":       2,
    },
    # ── 3  draft | physical ──────────────────────────────────────────────────
    {
        "title":         "NITK Startup Meetup",
        "tagline":       "Connect with alumni-led startups",
        "description":   "A meetup for NITK alumni entrepreneurs and startup enthusiasts.",
        "status":        "draft",
        "is_virtual":    False,
        "location_text": "NASSCOM 10000 Startups Hub, Bangalore",
        "capacity":      50,
        "start_days":    30,
        "hours":         4,
    },
    # ── 4  draft | virtual ───────────────────────────────────────────────────
    {
        "title":       "Global Alumni Connect",
        "tagline":     "Bridging NITK alumni across continents",
        "description": "A virtual gathering for NITK alumni worldwide to reconnect and collaborate.",
        "status":      "draft",
        "is_virtual":  True,
        "virtual_url": "https://meet.google.com/nitk-global-connect",
        "capacity":    500,
        "start_days":  45,
        "hours":       2,
    },
    # ── 5  published | physical  (plan: registration_open → published) ───────
    {
        "title":         "EV Innovation Summit",
        "tagline":       "Electric vehicles and the road ahead",
        "description":   "Summit on EV innovation featuring NITK alumni from the automotive industry.",
        "status":        "published",
        "is_virtual":    False,
        "location_text": "ITC Grand Chola, Chennai",
        "capacity":      200,
        "start_days":    10,
        "hours":         8,
    },
    # ── 6  published | virtual  (plan: registration_open → published) ────────
    {
        "title":       "Women in Engineering",
        "tagline":     "Celebrating and empowering women engineers",
        "description": "Virtual symposium celebrating NITK alumni women engineers and their achievements.",
        "status":      "published",
        "is_virtual":  True,
        "virtual_url": "https://meet.google.com/nitk-women-eng",
        "capacity":    150,
        "start_days":  25,
        "hours":       3,
    },
    # ── 7  cancelled | physical ──────────────────────────────────────────────
    {
        "title":            "Sports Meet 2026",
        "tagline":          "Reviving the NITK sporting spirit",
        "description":      "Annual sports meet for NITK alumni across Karnataka.",
        "status":           "cancelled",
        "is_virtual":       False,
        "location_text":    "NITK Surathkal Campus",
        "capacity":         300,
        "start_days":       60,
        "hours":            8,
        "cancelled_reason": "Venue unavailable",
    },
    # ── 8  cancelled | virtual ───────────────────────────────────────────────
    {
        "title":            "Tech Leadership Forum",
        "tagline":          "Leadership lessons from NITK alumni in tech",
        "description":      "Virtual forum with senior NITK alumni discussing technology leadership.",
        "status":           "cancelled",
        "is_virtual":       True,
        "virtual_url":      "https://meet.google.com/nitk-tech-leadership",
        "capacity":         75,
        "start_days":       35,
        "hours":            2,
        "cancelled_reason": "Speaker unavailable",
    },
    # ── 9  completed | physical  (plan: archived → completed) ────────────────
    {
        "title":         "NITKonnect 2025",
        "tagline":       "The grand alumni reunion",
        "description":   "Annual NITK alumni reunion — the biggest gathering of the year.",
        "status":        "completed",
        "is_virtual":    False,
        "location_text": "NITK Surathkal Campus, Mangalore",
        "capacity":      1000,
        "start_days":    -90,   # past event
        "hours":         16,
    },
    # ── 10 completed | virtual  (plan: archived → completed) ─────────────────
    {
        "title":       "Entrepreneurship Workshop",
        "tagline":     "From ideas to impact",
        "description": "Hands-on virtual workshop on building and scaling startups.",
        "status":      "completed",
        "is_virtual":  True,
        "virtual_url": "https://meet.google.com/nitk-entrepreneur",
        "capacity":    200,
        "start_days":  -30,   # past event
        "hours":       6,
    },
]


async def _insert(conn: asyncpg.Connection, ev: dict) -> dict:
    slug  = await _unique_slug(conn, _slug(ev["title"]))
    start = _now + timedelta(days=ev["start_days"])
    end   = start + timedelta(hours=ev["hours"])

    published_at     = (start - timedelta(days=5)) if ev["status"] in ("published", "completed") else None
    cancelled_at     = (_now - timedelta(hours=1)) if ev["status"] == "cancelled" else None
    cancelled_reason = ev.get("cancelled_reason")

    row = await conn.fetchrow(
        """
        INSERT INTO events (
            slug, title, tagline, description, status,
            start_datetime, end_datetime, timezone,
            location_text, is_virtual, virtual_url,
            capacity, created_by_firebase_uid,
            published_at, cancelled_at, cancelled_reason
        ) VALUES (
            $1,  $2,  $3,  $4,  $5,
            $6,  $7,  $8,
            $9,  $10, $11,
            $12, $13,
            $14, $15, $16
        )
        RETURNING event_id, slug, title, status, is_virtual, capacity,
                  start_datetime
        """,
        slug, ev["title"], ev.get("tagline"), ev.get("description"), ev["status"],
        start, end, "Asia/Kolkata",
        ev.get("location_text"), ev["is_virtual"], ev.get("virtual_url"),
        ev.get("capacity"), SEED_UID,
        published_at, cancelled_at, cancelled_reason,
    )
    return dict(row)


async def main() -> None:
    db_display = EVENTS_DB_URL.split("@")[-1] if "@" in EVENTS_DB_URL else EVENTS_DB_URL
    print(f"DB : {db_display}")

    conn = await asyncpg.connect(EVENTS_DB_URL)
    try:
        print(f"\nInserting {len(EVENTS)} events...\n")
        print(f"  {'ID':>4}  {'Status':<12}  {'Type':<8}  {'Cap':>4}  Slug")
        print(f"  {'─'*4}  {'─'*12}  {'─'*8}  {'─'*4}  {'─'*36}")

        created = []
        for ev in EVENTS:
            row = await _insert(conn, ev)
            created.append(row)
            typ = "Virtual" if row["is_virtual"] else "Physical"
            cap = str(row["capacity"]) if row["capacity"] else "∞"
            print(f"  {row['event_id']:>4}  {row['status']:<12}  {typ:<8}  {cap:>4}  {row['slug']}")

        # ── Summary ──────────────────────────────────────────────────────────
        statuses = Counter(r["status"]    for r in created)
        types    = Counter("Virtual" if r["is_virtual"] else "Physical" for r in created)
        ids      = [r["event_id"] for r in created]

        print(f"\n{'─'*56}")
        print(f"  Inserted  : {len(created)} events")
        print(f"  Event IDs : {ids}")
        print(f"\n  Status distribution:")
        for s in ("published", "draft", "cancelled", "completed"):
            print(f"    {s:<20} {statuses.get(s, 0)}")
        print(f"\n  Type distribution:")
        for t in ("Physical", "Virtual"):
            print(f"    {t:<20} {types.get(t, 0)}")
        print(f"{'─'*56}")
        print("\nDone. Refresh Admin Portal → Events to see all records.")

    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())
