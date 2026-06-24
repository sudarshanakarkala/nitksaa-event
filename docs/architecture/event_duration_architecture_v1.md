# Event Duration — Architecture v1

**Date:** 2026-06-22
**Status:** ARCHITECTURE DOCUMENT — full-day and multi-day support not required for Jun 30 Alpha
**Depends on:** migrations 001–009 (existing), events table
**Related decisions:** `week4_feedback_architecture_decisions.md` Decision 4

---

## Problem Statement

The current `events` table uses `start_datetime` and `end_datetime` (both TIMESTAMPTZ) to define
when an event occurs. This works for a single timed event (e.g., a webinar from 10:00 to 11:30).

It does not adequately represent:

1. **Full-day events** — An event that runs "all day" on a given date has no meaningful start/end
   time. Setting `start_datetime = 09:00` and `end_datetime = 18:00` is an approximation that
   leaks implementation into product. The Flutter UI cannot display "All Day" correctly.

2. **Multi-day events** — A conference spanning 3 days is a single logical event with many
   sessions. The current schema can store a date range via `start_datetime` and `end_datetime`,
   but the UI has no signal to render it as a date range rather than a timed block.

3. **Timezone ambiguity for full-day events** — A full-day event in IST must not shift by a day
   when displayed in UTC. Storing `2026-07-15 00:00:00+05:30` as the start is fragile.

---

## Current Schema State

```sql
CREATE TABLE events (
    event_id         SERIAL        PRIMARY KEY,
    ...
    start_datetime   TIMESTAMPTZ   NOT NULL,
    end_datetime     TIMESTAMPTZ   NOT NULL,
    ...
);
```

Both columns are `TIMESTAMPTZ`. The timezone-aware storage is correct for timed events. No
`is_full_day` signal exists. The API returns both timestamps to Flutter, which renders them as
start/end times regardless of whether the event is actually "all day."

---

## Proposed Schema Changes

These columns are added in a future migration. No migration is created in Week 4.

```sql
ALTER TABLE events
  ADD COLUMN is_full_day   BOOLEAN   NOT NULL DEFAULT false,
  ADD COLUMN event_date    DATE,
             -- Populated when is_full_day = true; the canonical event date (no time)
             -- NULL for timed events; the event_date lives in a timezone-neutral DATE type
  ADD COLUMN end_date      DATE;
             -- Populated when is_full_day = true AND the event spans multiple days
             -- NULL for single-day full-day events and all timed events
```

### Column semantics

| `is_full_day` | `event_date` | `end_date` | Meaning |
|---|---|---|---|
| `false` | NULL | NULL | Normal timed event (current behavior) |
| `true` | 2026-07-15 | NULL | Full-day event on a single date |
| `true` | 2026-07-15 | 2026-07-17 | Multi-day event spanning Jul 15–17 |

When `is_full_day = true`:
- `start_datetime` and `end_datetime` remain in the schema for backward compatibility
- They are set to the start and end of the day in IST (`00:00:00+05:30` to `23:59:59+05:30`)
  so that existing duration and calendar logic still works
- The `event_date` column is the authoritative single date for full-day events

---

## API Response Shape

When `is_full_day` is added to the schema, the public event detail response gains:

```json
{
  "event_id": 3,
  "title": "NITKonnect Annual Meetup",
  "is_full_day": true,
  "event_date": "2026-07-15",
  "end_date": "2026-07-17",
  "start_datetime": "2026-07-15T00:00:00+05:30",
  "end_datetime": "2026-07-17T23:59:59+05:30"
}
```

For timed events (`is_full_day = false`):
```json
{
  "event_id": 4,
  "title": "Monthly Webinar",
  "is_full_day": false,
  "event_date": null,
  "end_date": null,
  "start_datetime": "2026-07-22T18:00:00+05:30",
  "end_datetime": "2026-07-22T19:30:00+05:30"
}
```

The fields are additive — existing consumers ignoring `is_full_day` continue to work.

---

## Flutter Display Rules

| Scenario | Display |
|---|---|
| `is_full_day = false` | "22 Jul 2026, 6:00 PM – 7:30 PM IST" |
| `is_full_day = true`, no `end_date` | "15 Jul 2026 · All Day" |
| `is_full_day = true`, with `end_date` | "15–17 Jul 2026 · All Day" |

The Flutter `EventDetailScreen` checks `is_full_day` before formatting the date/time string.
When `is_full_day` is true, the time portion is suppressed.

---

## Admin UI Impact

The admin event creation form (`EventFormPage.jsx`) adds:
- "Full Day Event" checkbox
- When checked: time pickers are hidden; a date picker replaces them
- When multi-day: an "End Date" date picker appears
- The form sets `is_full_day = true`, `event_date`, and `end_date` on submit

---

## Validation Rules

Applied at the API layer (`EventCreate` schema validator):

1. When `is_full_day = true`:
   - `event_date` must be provided
   - `end_date`, if provided, must be >= `event_date`
   - `start_datetime` is computed from `event_date` (`00:00:00+05:30`)
   - `end_datetime` is computed from `end_date ?? event_date` (`23:59:59+05:30`)

2. When `is_full_day = false`:
   - `event_date` must be null
   - `end_date` must be null
   - `start_datetime` and `end_datetime` are provided directly as before
   - `end_datetime` must be after `start_datetime`

---

## Alpha Decision

**All Alpha and Jun 30 beta events are timed events. `is_full_day = false` is the only value
in use.** The NITKonnect Breakfast Club and the monthly webinars are timed events with explicit
start/end times. No full-day events are planned for the Alpha period.

The schema change is additive. Implement when the first genuinely full-day event (e.g., an
annual conference) is being created. Do not implement in Week 4.

---

## Implementation Recommendation

**Do not implement in Week 4.** Write this document. Confirm the column design with the product
owner. Implement as a standalone migration when the first full-day event is scheduled.

The migration is low-risk: additive columns with safe defaults (`is_full_day DEFAULT false`,
`event_date` nullable). No existing rows are affected.
