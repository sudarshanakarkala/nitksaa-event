# NITKSAA Event App — Integration & Architecture Alignment Note
**Version:** 2.0 · **Date:** May 2026  
**Author:** Padmanand Warrier  
**Audience:** Event App development team  
**Status:** Please read this before writing any backend code. Deviations from the patterns described here are fine if there is a good reason — but it would be worth discussing them first. Undiscussed deviations discovered later will likely require rework, because the website will be built against the contracts described here.

---

## Why This Document Exists

The Event App is a standalone application. At the same time, it shares identity infrastructure with the NITKSAA Website and Admin Portal, and the website will eventually surface event listings by calling the Event App's API directly. Some decisions made now — particularly around auth, schema naming, and API response shape — have consequences for the other apps.

This document is in three parts. Read Part 1 first for context (~10 minutes). Then follow Part 2 step by step when you start building. Use Part 3 as a reference while you work.

The goal is to make the eventual integration straightforward rather than a complete rework.

---

# Part 1 — Context (Read First)

## 1. The Mental Model — An Event Is a Group

Every significant entity on the NITKSAA platform has the same shape: a **lead** (a verified alumnus) who owns and manages it, and **members** (who may or may not be alumni) who participate. This pattern exists four times already on the website:

| Entity | Lead | Members |
|---|---|---|
| Community (chapter / batch / SIG) | Community admin | Any registered user |
| Startup | Founding alumnus | Co-founders |
| Giving project | Primary sponsor | Participants |
| Mentorship | Mentor | Mentee |

An event is the fifth instance of this pattern. The event coordinator is a verified alumnus who owns the event. Volunteers are members of that event's operational group — they can be non-alumni (students, staff) as long as they have a Firebase account. Attendees are a third membership class on the same event.

This framing directly influences the schema and role model in Part 2, and it is how the website will eventually treat events when the integration is built.

---

## 2. The Shared Code Model — Clone, Adapt, Honour the Contract

Five files from the website repo can serve as your starting point. The model is:

- **Clone** the relevant files into your own repo. You own your copy — modify it freely to suit the Event App's needs.
- **Avoid modifying the originals** in the website repo without discussion. Some of these files (particularly `notify.py`) are candidates for eventual extraction into a shared service. Unilateral changes in one repo make that harder.
- **The website team makes the same commitment in return.** The files listed below will not be changed in the website repo without discussion with the Event App team. If a change is needed in a shared-pattern file, both teams agree on it before either implements it.

The mutual no-change commitment applies specifically to the **pattern and interface** of these files — function signatures, JWT claim names, the `emit()` call signature. Implementation improvements within a file are fine; interface changes need discussion.

---

## 3. Things Worth Avoiding (and Why)

| Approach to avoid | Why it causes problems |
|---|---|
| Storing alumni profile fields (name, branch, year) in `event_users` or `registrations` | `alumni_db` is the source of truth. Data duplicated here goes stale when alumni update their profiles. Use `fetch_alumni_info()` instead — see Step 1. |
| Creating a separate Firebase project or auth system | Identity is shared across all three NITKSAA apps via the same Firebase project. A separate auth system means alumni need a separate account for events, which defeats the integration entirely. |
| Adding a global `is_volunteer` flag to `event_users` | Volunteer status is event-scoped, not platform-wide. A global flag has no expiry and no event context — a volunteer for NITKonnect 2027 should not have elevated access in 2029. The `event_members.role` column handles this correctly. |
| Calling the mail service directly from route handlers | All notifications should go through `emit()`. This ensures audit records are always written even when email delivery fails, and prevents a failed email from rolling back a successful registration. See Step 4. |

---

# Part 2 — Step by Step

## Step 1 — Clone the Shared Files

Clone the website repo locally and copy these five files into your backend. Each one is adapted slightly — the table shows you what to change.

| File in website repo | What it does | What to change |
|---|---|---|
| `backend/src/middleware/firebase.py` | Firebase token verification, internal JWT minting, `get_current_user` dependency, suspension enforcement | Change the DB table reference from `website_users` to `event_users`. Everything else can stay the same. |
| `backend/src/services/notify.py` | The `emit()` notification function — audit, in-app, and email delivery | Add your event types to `_TEMPLATES` (see Step 4). Leave the existing ones in place. |
| `backend/src/services/db.py` | Database connection pool (`get_db()`) | Point it at `events_db`. |
| `backend/src/services/alumni.py` | `fetch_alumni_info()` — fetches an alumni profile from `alumni_db` by `ref_id` | No changes needed. Use this whenever you need alumni name, branch, or year — never store that data locally. |
| `backend/src/config/settings.py` | Environment variable loading | Add your own vars: `EVENTS_DB_HOST`, `EVENTS_DB_NAME`, `EVENTS_DB_USER`, `EVENTS_DB_PASSWORD`, `SECRET_KEY`. |

---

## Step 2 — Create `events_db` and Run the Migrations

`events_db` lives on the same Cloud SQL instance as `website_db` and `alumni_db`. If the database shell has not been created yet, create it first:

```sql
CREATE DATABASE events_db;
```

Then run the six migrations below **in order**. The order matters because later migrations reference tables created by earlier ones — for example, `event_members` (migration 003) has a foreign key to `events` (migration 001), so 001 must run first.

### Migration 001 — events

The core events table. `slug` is the public identifier used in URLs — generate it from the title on create and treat it as immutable once the event is published, because external links will break if it changes.

```sql
CREATE TABLE events (
    event_id                SERIAL        PRIMARY KEY,
    slug                    TEXT          UNIQUE NOT NULL,
    title                   TEXT          NOT NULL,
    tagline                 TEXT,
    description             TEXT,                           -- Markdown
    status                  VARCHAR(20)   NOT NULL DEFAULT 'draft',
                                                            -- draft | published | cancelled | completed
    start_datetime          TIMESTAMPTZ   NOT NULL,
    end_datetime            TIMESTAMPTZ   NOT NULL,
    timezone                VARCHAR(60)   NOT NULL DEFAULT 'Asia/Kolkata',
    location_text           TEXT,
    location_maps_url       TEXT,
    is_virtual              BOOLEAN       NOT NULL DEFAULT false,
    virtual_url             TEXT,
    thumbnail_url           TEXT,
    banner_url              TEXT,
    capacity                INT,                            -- NULL = unlimited
    registration_opens_at   TIMESTAMPTZ,
    registration_closes_at  TIMESTAMPTZ,
    created_by_firebase_uid VARCHAR(128)  NOT NULL,
    created_at              TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ,
    published_at            TIMESTAMPTZ,
    cancelled_at            TIMESTAMPTZ,
    cancelled_reason        TEXT
);

CREATE INDEX idx_events_status         ON events(status);
CREATE INDEX idx_events_start_datetime ON events(start_datetime);
```

Note: `created_by_firebase_uid` does not have a foreign key here because `event_users` does not exist yet. Migration 003 will establish the user table.

### Migration 002 — sessions

Sessions belong to an event. `track` is nullable — a null track means a plenary or untracked session. `sort_order` controls display order within a track.

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
    speaker_name      TEXT,
    speaker_bio       TEXT,
    speaker_photo_url TEXT,
    sort_order        INT           NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_sessions_event_id ON sessions(event_id);
CREATE INDEX idx_sessions_sort     ON sessions(event_id, sort_order);
```

### Migration 003 — event_users and event_members

`event_users` is your equivalent of the website's `website_users` — one row per person who has ever logged in, whether or not they are an alumnus. `event_members` links users to specific events with a role. These two tables together are the foundation of the entire role and access model.

`ref_id` in `event_users` is a value reference to `alumni_db.alumni.alumni_id` — not a foreign key, because PostgreSQL cannot enforce foreign keys across databases. Treat it as a read-only pointer and never store alumni profile data alongside it.

```sql
CREATE TABLE event_users (
    firebase_uid     VARCHAR(128)  PRIMARY KEY,
    email            VARCHAR(255),
    fullname         VARCHAR(255),
    user_type        VARCHAR(50)   NOT NULL DEFAULT 'other',  -- 'alumni' | 'other'
    ref_id           VARCHAR(128),   -- points to alumni_db.alumni.alumni_id; NULL for non-alumni
    graduation_year  SMALLINT,
    is_suspended     BOOLEAN        NOT NULL DEFAULT false,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    last_login       TIMESTAMPTZ
);

CREATE TABLE event_members (
    event_id      INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    firebase_uid  VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid) ON DELETE CASCADE,
    role          VARCHAR(50)   NOT NULL CHECK (role IN ('coordinator', 'volunteer', 'attendee')),
    status        VARCHAR(20)   NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'pending', 'cancelled')),
    joined_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, firebase_uid)
);

CREATE INDEX idx_event_members_firebase_uid ON event_members(firebase_uid);
CREATE INDEX idx_event_members_role         ON event_members(event_id, role);
```

### Migration 004 — registrations and check_ins

A registration is created when a member signs up for an event. `qrtoken` is generated on insert and is the credential used for check-in scanning — it lives in `check_ins.registration_id` when scanned. The unique constraint on `(event_id, firebase_uid)` prevents double registration at the database level.

`check_ins` records every scan attempt, including duplicates and invalid tokens — this is intentional for audit purposes.

```sql
CREATE TABLE registrations (
    registration_id         SERIAL        PRIMARY KEY,
    event_id                INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    firebase_uid            VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid),
    ref_id                  VARCHAR(128),
    badge_name              TEXT          NOT NULL,
    email                   TEXT          NOT NULL,
    phone                   TEXT,
    attendee_type           VARCHAR(50),                    -- alumni | student | guest
    status                  VARCHAR(20)   NOT NULL DEFAULT 'confirmed',
                                                            -- confirmed | cancelled | waitlisted
    qrtoken                 TEXT          UNIQUE NOT NULL,
    confirmation_email_sent BOOLEAN       NOT NULL DEFAULT false,
    notes                   TEXT,
    registered_at           TIMESTAMPTZ   NOT NULL DEFAULT now(),
    cancelled_at            TIMESTAMPTZ,
    UNIQUE (event_id, firebase_uid)
);

CREATE INDEX idx_registrations_event_id     ON registrations(event_id);
CREATE INDEX idx_registrations_firebase_uid ON registrations(firebase_uid);
CREATE INDEX idx_registrations_qrtoken      ON registrations(qrtoken);
CREATE INDEX idx_registrations_status       ON registrations(event_id, status);

CREATE TABLE check_ins (
    checkin_id       SERIAL        PRIMARY KEY,
    registration_id  INT           NOT NULL REFERENCES registrations(registration_id),
    event_id         INT           NOT NULL REFERENCES events(event_id),
    scanned_by       VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid),
    scanned_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    session_id       INT           REFERENCES sessions(session_id),  -- NULL = general check-in
    result           VARCHAR(20)   NOT NULL CHECK (result IN ('success', 'duplicate', 'invalid'))
);

CREATE INDEX idx_checkins_registration_id ON check_ins(registration_id);
CREATE INDEX idx_checkins_event_id        ON check_ins(event_id);
```

### Migration 005 — post-event content

Simple link storage for recording and gallery URLs added after an event concludes. No media is hosted here — these are external URLs only.

```sql
CREATE TABLE event_content (
    content_id    SERIAL        PRIMARY KEY,
    event_id      INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    content_type  VARCHAR(20)   NOT NULL CHECK (content_type IN ('recording', 'gallery')),
    label         TEXT          NOT NULL,
    url           TEXT          NOT NULL,
    sort_order    INT           NOT NULL DEFAULT 0,
    added_by      VARCHAR(128)  NOT NULL REFERENCES event_users(firebase_uid),
    added_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_event_content_event_id ON event_content(event_id);
```

### Migration 006 — audit and notifications

Three tables that underpin the notification and audit system.

`event_audit_log` records every significant action — it is append-only by design. Grant the app DB user `INSERT` only on this table, no `UPDATE` or `DELETE`. This is intentional: audit records must be immutable.

`notifications` holds in-app notifications shown in the Flutter app's notification bell.

`notification_preferences` lets users opt out of push delivery per event type. No row means push is enabled — users opt out, they are not opted in.

All three are written to by `emit()` automatically. There is no need to write to them directly from route handlers.

```sql
CREATE TABLE event_audit_log (
    log_id      BIGSERIAL    PRIMARY KEY,
    actor_uid   VARCHAR(128),
    event_type  TEXT         NOT NULL,
    entity_type TEXT         NOT NULL,
    entity_id   INTEGER,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
    notification_id  BIGSERIAL    PRIMARY KEY,
    firebase_uid     VARCHAR(128) NOT NULL,
    event_type       TEXT         NOT NULL,
    entity_type      TEXT,
    entity_id        INTEGER,
    is_read          BOOLEAN      NOT NULL DEFAULT false,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE notification_preferences (
    firebase_uid  VARCHAR(128) NOT NULL,
    event_type    TEXT         NOT NULL,
    push_enabled  BOOLEAN      NOT NULL DEFAULT true,
    PRIMARY KEY (firebase_uid, event_type)
);
```

---

## Step 3 — Wire Authentication

Implement `POST /api/v1/auth/firebase` using the cloned `firebase.py`. The flow is:

```
Flutter app gets Firebase ID token from Google
        │
        ▼
POST /api/v1/auth/firebase  { "firebase_token": "..." }
        │  Backend calls Firebase once, gets firebase_uid + email
        │  Upserts row in event_users
        │  Mints a fast internal JWT
        ▼
Returns { "token": "<internal JWT>" }
        │
        ▼
Flutter stores token, sends as  Authorization: Bearer <token>
on every subsequent API call — no more Firebase calls per request
```

The reason for this two-step pattern is performance. Verifying a Firebase token requires a round trip to Google's servers. Doing that on every API request would make the app noticeably slow. The internal JWT is verified locally in milliseconds.

The JWT must use these exact field names. The website's frontend and a planned unified JWT migration both depend on consistent naming across apps. Using different names now would mean a find-and-replace across every route guard later.

```python
{
    "firebase_uid":    "abc123",        # always present — stable Firebase identifier
    "user_type":       "alumni",        # "alumni" or "other" — never null
    "ref_id":          "ALUMNI-001234", # null for non-alumni users
    "graduation_year": 2005,            # null for non-alumni users
    "exp":             1234567890       # standard JWT expiry
}
```

On first login, the upsert in `firebase.py` fills in `email`, `fullname`, and `last_login`. It should not overwrite `user_type` or `ref_id` if they are already set — the cloned upsert logic handles this correctly.

---

## Step 4 — Wire Notifications

Add your event types to `_TEMPLATES` in the cloned `notify.py`. The minimum set for Alpha:

```python
"registration_confirmed":  ("Registration confirmed",  "You are registered for {event_name}."),
"registration_cancelled":  ("Registration cancelled",  "Your registration for {event_name} has been cancelled."),
"checkin_completed":       ("Checked in",              "You have been checked in to {event_name}."),
"event_published":         ("New event",               "{event_name} is now open for registration."),
"event_cancelled":         ("Event cancelled",         "{event_name} has been cancelled."),
"volunteer_assigned":      ("Volunteer assignment",    "You have been assigned as a volunteer for {event_name}."),
```

Then call `emit()` from route handlers after every significant state change:

```python
await emit(
    event_type    = "registration_confirmed",
    actor_uid     = current_user["firebase_uid"],
    recipient_uid = registration["firebase_uid"],
    entity_type   = "registration",
    entity_id     = registration["registration_id"],
    db            = cur
)
```

`emit()` handles audit, in-app notification, and email in one call. If email delivery fails, the audit record and notification are still written — a failed email never causes a user-facing error.

### Three things that have tripped me up — explaining them fully

**1. psycopg2 `cur.execute()` returns None, not a result**

When you call `cur.execute("SELECT ...")`, the return value is `None`. The actual results come from calling `cur.fetchone()` or `cur.fetchall()` as a separate line. This is different from many other database libraries. Chaining them on one line will crash:

```python
# This will crash with AttributeError: 'NoneType' has no attribute 'fetchone'
row = cur.execute("SELECT fullname FROM event_users WHERE firebase_uid = %s", (uid,)).fetchone()

# Correct
cur.execute("SELECT fullname FROM event_users WHERE firebase_uid = %s", (uid,))
row = cur.fetchone()
```

**2. `fullname` can be None — always provide a fallback**

When a user logs in for the first time, `fullname` may not yet be populated — it comes from Firebase and can be absent for some sign-in methods. Using `user["fullname"]` directly in an email or notification body will occasionally produce emails addressed to `None`. Always use:

```python
display_name = user["fullname"] or user["email"]
```

This is already done in the website's `notify.py` templates — your cloned copy will have it. Just keep it in mind when writing new templates.

**3. `emit()` must never raise an exception**

`emit()` is called after a successful DB write — for example, after a registration is saved. If `emit()` raises, the exception propagates up and the route handler returns a 500 error, even though the registration was actually saved. The user sees an error but is registered, which leads to confusion and duplicate attempts.

`emit()` wraps all delivery logic in `try/except` internally and logs failures rather than raising them. When you clone `notify.py`, this is already in place. Avoid adding code inside `emit()` that raises without catching. Failures appear in the backend logs prefixed with `[notify]`.

---

## Step 5 — Implement the Role Model

Volunteer and coordinator access is per-event, not platform-wide. The `event_members` table (created in migration 003) is the source of truth.

The three roles are:

| Role | Who can hold it | What they can do |
|---|---|---|
| `coordinator` | Verified alumni only (`user_type = 'alumni'`) | Create and edit event, assign volunteers, view all attendees, export CSV, all operations screens |
| `volunteer` | Any Firebase user — alumni or non-alumni | Scan QR codes, check in attendees, view attendee list for their event |
| `attendee` | Any Firebase user | View their own QR badge, view their own registration status |

Add this dependency to your backend to enforce role checks on protected routes:

```python
def require_event_role(event_id: int, required_roles: list[str]):
    """
    Returns a FastAPI dependency that checks the caller has one of
    the required roles for this specific event. Raises 403 if not.
    """
    async def _check(current_user=Depends(get_current_user), db=Depends(get_db)):
        with db as cur:
            cur.execute("""
                SELECT role FROM event_members
                WHERE event_id = %s AND firebase_uid = %s AND status = 'active'
            """, (event_id, current_user["firebase_uid"]))
            row = cur.fetchone()
            if not row or row["role"] not in required_roles:
                raise HTTPException(403, "You do not have permission for this action")
        return current_user
    return _check
```

Usage:

```python
# Only coordinators can publish an event
@router.post("/events/{event_id}/publish")
async def publish_event(event_id: int, user=Depends(require_event_role(event_id, ["coordinator"]))):
    ...

# Coordinators and volunteers can check in attendees
@router.post("/events/{event_id}/checkin")
async def check_in(event_id: int, user=Depends(require_event_role(event_id, ["coordinator", "volunteer"]))):
    ...
```

When assigning a coordinator, enforce the alumni constraint at the API layer — not just in the Flutter UI, since UI checks can be bypassed:

```python
if role == "coordinator" and current_user["user_type"] != "alumni":
    raise HTTPException(400, "Event coordinators must be verified NITKSAA alumni")
```

---

## Step 6 — Build the Two Public API Endpoints

These two endpoints are a contract with the website team. The website will call them directly when it surfaces event listings. Please avoid changing field names or removing fields without discussion — the website frontend will be built against this shape.

### `GET /api/v1/events`

No authentication required. Returns published events only, paginated.

```json
{
  "events": [
    {
      "event_id":            1,
      "slug":                "nitksaa-nitconnect-2027",
      "title":               "NITKonnect 2027",
      "tagline":             "The annual NITK alumni homecoming",
      "status":              "published",
      "start_datetime":      "2027-01-15T09:00:00+05:30",
      "end_datetime":        "2027-01-16T18:00:00+05:30",
      "timezone":            "Asia/Kolkata",
      "location_text":       "NITK Surathkal, Mangalore",
      "is_virtual":          false,
      "virtual_url":         null,
      "thumbnail_url":       "https://storage.googleapis.com/...",
      "capacity":            500,
      "registration_status": "open",
      "registered_count":    134,
      "coordinator": {
        "firebase_uid":      "abc123",
        "fullname":          "Padmanand Warrier",
        "ref_id":            "ALUMNI-001234",
        "graduation_year":   1999
      },
      "published_at":        "2026-11-01T10:00:00+05:30"
    }
  ],
  "total":    12,
  "page":     1,
  "per_page": 20
}
```

Key fields:

- `registration_status` — a computed string derived on the backend from `status`, `registration_opens_at`, `registration_closes_at`, and current capacity. Values: `"open"` | `"closed"` | `"full"` | `"not_open_yet"` | `"not_applicable"`. The website displays this directly without re-deriving it — keeping the logic in one place avoids the two apps getting out of sync.
- `registered_count` — confirmed registrations only (`status = 'confirmed'`).
- `coordinator.fullname` — fall back to `coordinator.email` if fullname is not set. Avoid returning null here.
- All datetimes — ISO 8601 with timezone offset. Returning naive (timezone-unaware) datetimes will cause display bugs in the website frontend.

### `GET /api/v1/events/{slug}`

Full event detail. The URL uses `slug`, not `event_id` — slugs are stable public identifiers that can appear in links and bookmarks.

```json
{
  "event_id":               1,
  "slug":                   "nitksaa-nitconnect-2027",
  "title":                  "NITKonnect 2027",
  "tagline":                "The annual NITK alumni homecoming",
  "description":            "Full markdown description...",
  "status":                 "published",
  "start_datetime":         "2027-01-15T09:00:00+05:30",
  "end_datetime":           "2027-01-16T18:00:00+05:30",
  "timezone":               "Asia/Kolkata",
  "location_text":          "NITK Surathkal, Mangalore",
  "location_maps_url":      "https://maps.google.com/?q=...",
  "is_virtual":             false,
  "virtual_url":            null,
  "thumbnail_url":          "https://storage.googleapis.com/...",
  "banner_url":             null,
  "capacity":               500,
  "registration_status":    "open",
  "registration_opens_at":  "2026-11-01T00:00:00+05:30",
  "registration_closes_at": "2027-01-10T23:59:59+05:30",
  "registered_count":       134,
  "coordinator": {
    "firebase_uid":         "abc123",
    "fullname":             "Padmanand Warrier",
    "ref_id":               "ALUMNI-001234",
    "graduation_year":      1999
  },
  "sessions": [
    {
      "session_id":         10,
      "track":              "Technology",
      "title":              "AI in Alumni Networks",
      "start_datetime":     "2027-01-15T10:00:00+05:30",
      "end_datetime":       "2027-01-15T11:00:00+05:30",
      "location_text":      "Auditorium A",
      "speaker_name":       "Dr. Ravi Kumar",
      "speaker_bio":        "...",
      "sort_order":         1
    }
  ],
  "post_event": {
    "available":       false,
    "recording_links": [],
    "gallery_links":   []
  },
  "published_at": "2026-11-01T10:00:00+05:30"
}
```

- `description` — store and return as Markdown. The website renders Markdown already (used for Stories) and will use the same renderer here.
- `sessions` — always return an array, even if empty. Returning null here will cause the website frontend to crash.
- `post_event.available` — set to `true` when any recording or gallery links exist. The website uses this as a badge indicator without having to inspect the arrays.

---

## Step 7 — Pre-Review Checklist

Before sharing the backend for a first review, it would help to confirm:

- [ ] Five files cloned from website repo and adapted
- [ ] `events_db` created on the shared Cloud SQL instance
- [ ] All six migrations run in order (001 → 006)
- [ ] `POST /api/v1/auth/firebase` working — JWT issued with claim names `firebase_uid`, `user_type`, `ref_id`, `graduation_year`
- [ ] `emit()` wired to at least `registration_confirmed` and `checkin_completed`
- [ ] `event_audit_log`, `notifications`, `notification_preferences` tables created and receiving writes from `emit()`
- [ ] Coordinator assignment enforces `user_type = 'alumni'` at the API layer
- [ ] `GET /api/v1/events` returns `registration_status` as a computed string
- [ ] All datetime fields in API responses are ISO 8601 with timezone offset
- [ ] `GET /api/v1/events/{slug}` uses slug in the URL, not event_id
- [ ] No alumni profile data stored in `events_db`

---

# Part 3 — Important Considerations

These are infrastructure and architecture decisions that the team should be aware of before starting.

| Topic | Detail |
|---|---|
| Gmail SMTP credentials | Share the website's existing Gmail app password. Reference the same Secret Manager secret — check with Padmanand for the secret name. |
| Cloud SQL instance | `events_db` goes on the same Cloud SQL instance as `website_db` and `alumni_db`. Create it as a new database on that instance, not a new instance. |
| Firebase project | Use the same Firebase project as the website and admin portal. Confirm the project ID with Padmanand before initialising Firebase in the app — creating a separate project by accident is a painful thing to undo. |
| JWT signing secret | Use a separate secret from the website. Name it `nitksaa-events-secret-key` in Secret Manager. A separate secret means the two apps can rotate independently. |
| Website integration | When the website eventually surfaces event listings, it will call the Event App's public API directly. There is no data sync or duplication planned. This is why the public API contract in Step 6 matters. |
