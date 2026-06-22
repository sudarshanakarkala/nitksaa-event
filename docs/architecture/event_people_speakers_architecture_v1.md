# Event People and Speakers — Architecture v1

**Date:** 2026-06-22
**Status:** ARCHITECTURE DOCUMENT — do not implement without product owner approval
**Depends on:** migrations 001–009 (existing), sessions table (migration 002)
**Related decisions:** `week4_feedback_architecture_decisions.md` Decision 5

---

## Problem Statement

The public event detail API currently returns `sessions` and `speakers` as empty arrays or
hard-coded placeholders. The `sessions` table exists in the database (migration 002) and contains
the correct schema, but the session data is not properly wired through the API to the response.

Separately, the current speaker model is architecturally incomplete:

1. **One speaker per session** — `sessions.speaker_name`, `sessions.speaker_bio`,
   `sessions.speaker_photo_url` support exactly one speaker per session. A panel discussion
   with four panelists cannot be represented.

2. **No event-level people model** — The event itself has no host, moderator, chief guest,
   or guest of honour. These roles exist in real events but have no place in the schema.

3. **Speaker is one role, not the only role** — Treating "speaker" as the complete model
   excludes: hosts who run the event, moderators who facilitate discussion, panelists on multi-speaker
   sessions, chief guests, guests of honour, and public organizers.

This document defines the schema and API changes required to address these gaps.

---

## Current Code State

### Database (migration 002)

```sql
CREATE TABLE sessions (
    session_id        SERIAL        PRIMARY KEY,
    event_id          INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    track             TEXT,
    title             TEXT          NOT NULL,
    description       TEXT,
    start_datetime    TIMESTAMPTZ   NOT NULL,
    end_datetime      TIMESTAMPTZ   NOT NULL,
    location_text     TEXT,
    speaker_name      TEXT,         -- single speaker only
    speaker_bio       TEXT,
    speaker_photo_url TEXT,
    sort_order        INT           NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT now()
);
```

### API Response (current)

`GET /api/v1/events/public/{event_id}` returns:
```json
{
  "sessions": [],
  "speakers": []
}
```

Both fields are empty. The sessions table is not queried. The speakers field is a placeholder.

### Flutter and Admin Portal

No speaker display exists in the Flutter event detail screen. The admin portal event form
does not have a people management section.

---

## Why Sessions and People Must Be Designed Together

Sessions and people are linked. A session can have one or more speakers. A speaker may appear
across multiple sessions. The `session_people` join table (defined below) is the link.

If `event_people` is designed without `session_people`, the admin must manually re-enter the
same speaker for every session they appear in. If `session_people` is designed without
`event_people`, speaker data duplicates across sessions with no central record to update.

The two tables must be designed and implemented together.

---

## Proposed Schema

### Table: `event_people`

One row per person per event. Represents all people publicly associated with the event,
regardless of whether they are linked to a specific session.

```sql
CREATE TABLE event_people (
    person_id      SERIAL        PRIMARY KEY,
    event_id       INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    full_name      TEXT          NOT NULL,
    designation    TEXT,                          -- job title / role at organization
    organization   TEXT,                          -- employer or institution
    bio            TEXT,                          -- markdown supported
    photo_url      TEXT,
    linkedin_url   TEXT,
    role           VARCHAR(30)   NOT NULL
                   CHECK (role IN (
                       'HOST',
                       'MODERATOR',
                       'SPEAKER',
                       'PANELIST',
                       'CHIEF_GUEST',
                       'GUEST_OF_HONOUR',
                       'ORGANIZER'
                   )),
    sort_order     INT           NOT NULL DEFAULT 0,
    is_visible     BOOLEAN       NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ
);

CREATE INDEX idx_event_people_event_id ON event_people(event_id);
CREATE INDEX idx_event_people_role     ON event_people(event_id, role);
CREATE INDEX idx_event_people_visible  ON event_people(event_id, is_visible);
```

### Table: `session_people`

Maps people to specific sessions. A person can appear in multiple sessions. A session can have
multiple people. The `role` here may differ from their event-level role (e.g., someone registered
as an event HOST may be a PANELIST in one session).

```sql
CREATE TABLE session_people (
    session_id     INT           NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    person_id      INT           NOT NULL REFERENCES event_people(person_id) ON DELETE CASCADE,
    role           VARCHAR(30)   NOT NULL
                   CHECK (role IN ('SPEAKER','PANELIST','MODERATOR','HOST')),
    sort_order     INT           NOT NULL DEFAULT 0,
    PRIMARY KEY    (session_id, person_id)
);

CREATE INDEX idx_session_people_session_id ON session_people(session_id);
CREATE INDEX idx_session_people_person_id  ON session_people(person_id);
```

### Existing `sessions` table — no changes

The three per-session speaker columns (`speaker_name`, `speaker_bio`, `speaker_photo_url`) are
retained. They are not dropped. When `session_people` is implemented:

- New sessions use `session_people` for speaker data.
- The old columns are soft-deprecated: still readable, not written by new API.
- A future migration can drop them once all sessions use `session_people`.

This preserves backward compatibility during the transition.

---

## Role Enum

| Role | Description |
|---|---|
| `HOST` | Runs the overall event. Usually one per event. |
| `MODERATOR` | Facilitates discussion. May be session-scoped. |
| `SPEAKER` | Gives a talk. Session-level or event-level keynote. |
| `PANELIST` | Participates in a panel discussion. Session-scoped. |
| `CHIEF_GUEST` | Distinguished guest with ceremonial role. Event-level. |
| `GUEST_OF_HONOUR` | Distinguished honoured guest. Event-level. |
| `ORGANIZER` | Publicly visible organizer. Event-level. |

---

## API Response Shape

### Public event detail response additions

`GET /api/v1/events/public/{event_id}` or `GET /api/v1/events/{slug}`

```json
{
  "event_id": 3,
  "title": "NITKonnect Breakfast Club",
  "people": [
    {
      "person_id": 1,
      "full_name": "Ravi Kumar",
      "designation": "VP Engineering",
      "organization": "Acme Corp",
      "bio": "Ravi graduated from NITK in 2001...",
      "photo_url": "https://storage.googleapis.com/...",
      "linkedin_url": "https://linkedin.com/in/ravikumar",
      "role": "HOST",
      "sort_order": 0
    }
  ],
  "speakers": [
    {
      "person_id": 2,
      "full_name": "Priya Nair",
      "designation": "CTO",
      "organization": "TechStartup",
      "bio": "...",
      "photo_url": "...",
      "linkedin_url": "...",
      "role": "SPEAKER",
      "sort_order": 0
    }
  ],
  "sessions": [
    {
      "session_id": 10,
      "title": "AI in Alumni Networks",
      "start_datetime": "2026-07-05T10:00:00+05:30",
      "end_datetime": "2026-07-05T11:00:00+05:30",
      "speakers": [
        {
          "person_id": 2,
          "full_name": "Priya Nair",
          "role": "SPEAKER",
          "sort_order": 0
        }
      ]
    }
  ]
}
```

### Backward compatibility rule

The `speakers` field is a **derived subset** of `people`:
```python
speakers = [p for p in people if p["role"] in (
    "SPEAKER", "PANELIST", "CHIEF_GUEST", "GUEST_OF_HONOUR"
)]
```

This field must be retained even after `event_people` is implemented, so existing Flutter and
website consumers do not break.

### Admin API additions (future)

```
POST   /api/v1/admin/events/{event_id}/people           — add a person
PATCH  /api/v1/admin/events/{event_id}/people/{person_id} — update a person
DELETE /api/v1/admin/events/{event_id}/people/{person_id} — remove a person
POST   /api/v1/admin/sessions/{session_id}/people       — assign a person to a session
DELETE /api/v1/admin/sessions/{session_id}/people/{person_id} — remove from session
```

---

## Admin UI Future Needs

The admin portal event form (`EventFormPage.jsx`) needs a new "People" section:

- Add person form: full_name, designation, organization, bio, photo_url, linkedin_url, role, sort_order
- Person list for the event (grouped by role)
- Per-session speaker assignment (dropdown from the event's `event_people` list)
- Reorder by sort_order (drag or up/down buttons)
- Toggle `is_visible` per person

This is a Week 5+ admin portal addition.

---

## Flutter / Public Website Impact

### Flutter event detail screen

A new "People" section on the event detail screen:
- Grouped by role: Hosts, Speakers, Panelists, etc.
- Avatar, name, designation, organization
- Tap for bio modal

Currently: no people display exists. The screen shows event description and sessions only.

### Website integration

The website eventually surfaces event listings by calling the Event App's public API directly
(per the integration note). When `people`, `speakers`, `sponsors`, `partners` are added to the
public event detail response, the website will display them without a new API contract negotiation
— the shape is additive.

---

## Migration Plan

When implementation is approved, the migration sequence is:

1. New migration: create `event_people` table (no FK changes to existing tables)
2. New migration: create `session_people` join table
3. Backend: new admin endpoints for people management
4. Backend: wire `event_people` and `session_people` into public event detail response
5. Backend: populate `speakers` derived field from `event_people`
6. Admin portal: add People section to EventFormPage
7. Flutter: add People section to EventDetailScreen
8. Future migration (separate): drop `speaker_name`, `speaker_bio`, `speaker_photo_url` from
   sessions once all sessions use `session_people`

---

## Implementation Recommendation

**Do not implement in Week 4.** Write this document. Confirm the schema design with the product
owner. Implement in Week 5 or later.

The API shape (empty `speakers: []` and `sessions: []`) is acceptable for the Jun 30 Alpha demo.
The architecture gap is acknowledged. Implementation follows when the first real multi-speaker
or multi-role event is being created.
