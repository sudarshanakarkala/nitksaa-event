#!/usr/bin/env python3
"""Seed two published past events for local Flutter verification.

Usage (from backend/):
    .venv/bin/python scripts/seed_past_public_events.py
"""

import asyncio
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

import asyncpg
from dotenv import load_dotenv


load_dotenv(Path(__file__).parent.parent / ".env")

APP_ENV = os.getenv("APP_ENV", "development")
EVENTS_DB_URL = os.getenv(
    "EVENTS_DB_URL",
    "postgresql://ananth@localhost:5432/events_db",
)
SEED_UID = "seed-admin-firebase-uid"


def _events() -> list[dict]:
    now = datetime.now(timezone.utc)
    return [
        {
            "slug": "past-breakfast-meetup",
            "title": "Past Breakfast Meetup",
            "tagline": "A recent alumni breakfast gathering",
            "description": (
                "Local development seed event for verifying the public Past tab."
            ),
            "is_virtual": False,
            "location_text": "Bangalore",
            "virtual_url": None,
            "capacity": 100,
            "thumbnail_url": (
                "https://placehold.co/480x270/f7efe2/47321f"
                "?text=Past+Breakfast"
            ),
            "banner_url": (
                "https://placehold.co/1280x480/f7efe2/47321f"
                "?text=Past+Breakfast+Meetup"
            ),
            "start_datetime": now - timedelta(days=16, hours=2),
            "end_datetime": now - timedelta(days=16),
        },
        {
            "slug": "past-alumni-webinar",
            "title": "Past Alumni Webinar",
            "tagline": "A recent virtual alumni session",
            "description": (
                "Local development seed event for verifying virtual Past cards."
            ),
            "is_virtual": True,
            "location_text": None,
            "virtual_url": "https://meet.google.com/past-alumni-webinar",
            "capacity": 200,
            "thumbnail_url": (
                "https://placehold.co/480x270/e8f0ff/12324a"
                "?text=Past+Webinar"
            ),
            "banner_url": (
                "https://placehold.co/1280x480/e8f0ff/12324a"
                "?text=Past+Alumni+Webinar"
            ),
            "start_datetime": now - timedelta(days=11, hours=2),
            "end_datetime": now - timedelta(days=11),
        },
    ]


async def _upsert(conn: asyncpg.Connection, event: dict) -> asyncpg.Record:
    return await conn.fetchrow(
        """
        INSERT INTO events (
            slug, title, tagline, description, status,
            start_datetime, end_datetime, timezone,
            location_text, is_virtual, virtual_url,
            thumbnail_url, banner_url,
            capacity, registration_closes_at,
            created_by_firebase_uid, published_at
        ) VALUES (
            $1, $2, $3, $4, 'published',
            $5, $6, 'Asia/Kolkata',
            $7, $8, $9,
            $10, $11,
            $12, $6,
            $13, $14
        )
        ON CONFLICT (slug) DO UPDATE SET
            title = EXCLUDED.title,
            tagline = EXCLUDED.tagline,
            description = EXCLUDED.description,
            status = 'published',
            start_datetime = EXCLUDED.start_datetime,
            end_datetime = EXCLUDED.end_datetime,
            timezone = EXCLUDED.timezone,
            location_text = EXCLUDED.location_text,
            is_virtual = EXCLUDED.is_virtual,
            virtual_url = EXCLUDED.virtual_url,
            thumbnail_url = EXCLUDED.thumbnail_url,
            banner_url = EXCLUDED.banner_url,
            capacity = EXCLUDED.capacity,
            registration_closes_at = EXCLUDED.registration_closes_at,
            published_at = EXCLUDED.published_at,
            updated_at = NOW()
        RETURNING event_id, slug, title, status, is_virtual,
                  start_datetime, end_datetime
        """,
        event["slug"],
        event["title"],
        event["tagline"],
        event["description"],
        event["start_datetime"],
        event["end_datetime"],
        event["location_text"],
        event["is_virtual"],
        event["virtual_url"],
        event["thumbnail_url"],
        event["banner_url"],
        event["capacity"],
        SEED_UID,
        event["start_datetime"] - timedelta(days=5),
    )


async def main() -> None:
    if APP_ENV != "development":
        raise RuntimeError(
            "Refusing to seed past public events outside APP_ENV=development."
        )

    conn = await asyncpg.connect(EVENTS_DB_URL)
    try:
        rows = [await _upsert(conn, event) for event in _events()]
    finally:
        await conn.close()

    print("Seeded past public events:")
    for row in rows:
        event_type = "virtual" if row["is_virtual"] else "physical"
        print(
            f"  {row['event_id']}: {row['title']} "
            f"({event_type}, {row['status']}, ends {row['end_datetime']})"
        )


if __name__ == "__main__":
    asyncio.run(main())
