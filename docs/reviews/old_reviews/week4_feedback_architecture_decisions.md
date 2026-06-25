# Week 4 — Feedback Architecture Decisions

**Date:** 2026-06-22 (revised 2026-06-22)
**Reviewer:** CAR SOFTWARE SYSTEMS
**Status:** PROPOSED — each decision requires explicit sign-off before implementation begins

---

## How to use this document

Each section below describes an architecture gap identified in the Week 4 review. For each:
- **Current state** in the codebase is documented.
- **Options** are listed.
- A **recommendation** is made.
- **Architecture status** is one of:
  - `ARCH REQUIRED — Week 4` — a design document must be written in Week 4 regardless of implementation timeline
  - `ARCH DOCUMENTED` — decision is made; document exists or is written this week
  - `IMPLEMENT APPROVED` — explicitly approved for Week 4 implementation
  - `DEFERRED` — do not implement; document the architecture only

Mark each decision at the Phase 0 review meeting. Write the deciding person's name and date.

**Decisions 1–3 must be decided before implementation begins.**
**Decisions 4–11 default to architecture-required + implementation-deferred unless the product owner
explicitly approves otherwise.**

---

## Decision 1 — Real Email Delivery

**Architecture status: IMPLEMENT APPROVED (Week 4)**

### Current State

`EMAIL_MODE=log` is the default. The email service (`app/services/email_service.py`) uses raw
`smtplib.SMTP` — synchronous inside an async function. No email has been sent in staging or
production. The architecture doc comparison:

| Platform | Email implementation |
|---|---|
| nitksaa-website (`notify.py`) | Gmail SMTP, background threading, 3-layer: audit + in-app + email |
| nitksaa-portal-v2 (`services/email.py`) | Provider class (gmail/sendgrid/none), BackgroundTasks, plain+HTML |
| Event App (`services/email_service.py`) | Gmail SMTP via smtplib, log/send mode, HTML only, sync inside async |

### Recommendation

**Gmail SMTP (same pattern as website and portal-v2).**

1. Set `EMAIL_MODE=send` in staging environment.
2. Set `SMTP_USER` and `SMTP_PASSWORD` from Secret Manager.
3. Fix: wrap `smtplib.SMTP` call in `asyncio.to_thread()` to avoid blocking the event loop.
4. Add plain text fallback (portal-v2 pattern: both `text/plain` and `text/html` parts).

### Decision

**[ ] DECIDED: __________________ Date: __________**

---

## Decision 2 — Alumni DB: Local Dev vs. Staging

**Architecture status: IMPLEMENT APPROVED (Week 4)**

### Current State

`ALUMNI_DB_URL` must be set in `.env` for all alumni-gated flows. No README documents the setup.
Any developer on a new machine will fail alumni flows until they create `alumni_db` locally or
point at staging.

### Recommendation

1. Add `ALUMNI_DB_URL` setup steps to a developer setup guide.
2. Provide a minimal seed SQL script: one active alumni test account with known `ref_id`.
3. Local dev uses a local `alumni_db`. Never point local dev at production `alumni_db`.
4. Integration testing may use staging `alumni_db` read-only.

### Decision

**[ ] DECIDED: __________________ Date: __________**

---

## Decision 3 — Login Message Cleanup

**Architecture status: IMPLEMENT APPROVED (Week 4)**

### Current State

Two categories of technical messages are shown to users in `login_screen.dart`:

**Status messages:**
- `'Signing in with Firebase...'` — "Firebase" is an internal infrastructure term
- `'Backend session validated. Opening diagnostics...'` — leaks internal routing
- `'Backend session validated. Opening home...'` — "Backend session validated" is technical

**Error catch-all** (`auth_controller.dart:187–188`):
```dart
_ => error.message ?? 'Firebase authentication failed.',
```
This exposes raw Firebase SDK messages for unmapped codes.

Currently mapped: `invalid-email`, `user-disabled`, `user-not-found`, `wrong-password`,
`invalid-credential`.

### Recommendation

Replace status messages with user-facing language. Add unmapped codes with friendly messages.
Change the catch-all to a non-technical fallback.

### Decision

**[ ] DECIDED: __________________ Date: __________**

---

## Decision 4 — Full Day / All Day Event

**Architecture status: ARCH REQUIRED — Week 4 | Implementation: DEFERRED**

Architecture document: `docs/architecture/` (full_day / event_duration — to be created if approved)

### Current State

The events table has `start_datetime` and `end_datetime` only (both `TIMESTAMPTZ NOT NULL`).
`EventCreate` schema requires both. There is no duration type concept.

A full-day event (NITKonnect annual reunion, multi-day convention) spans entire days. Forcing
`09:00–17:00` on it is arbitrary. The Flutter event detail screen and admin form have no
"all day" concept.

### Recommended Architecture

Prefer an enum over multiple booleans.

```
event_duration_type:
  TIMED      — specific start and end time; show date + time in UI
  FULL_DAY   — full working/event day; internal schedule may exist; show date + "Full day"
  ALL_DAY    — calendar-style all-day; hide exact times in UI
```

**Schema change required:**
```sql
ALTER TABLE events
  ADD COLUMN event_duration_type VARCHAR(20) NOT NULL DEFAULT 'TIMED'
  CHECK (event_duration_type IN ('TIMED', 'FULL_DAY', 'ALL_DAY'));
```

**Impact areas:**
- Backend: `EventCreate` validation — `end_datetime` optional when `FULL_DAY` or `ALL_DAY`
- Admin form: duration type selector hides/shows time pickers
- Public event API: return `event_duration_type`; frontend derives display format
- Flutter: `EventDetailScreen` date/time formatting
- "Add to calendar" behaviour: iCal all-day flag
- Registration deadline: if `FULL_DAY`, deadline defaults to end of day in event timezone

### Decision

**[ ] ARCH DOCUMENT WRITTEN**
**[ ] IMPLEMENT APPROVED: __________________ Date: __________**
**[x] DEFERRED (default — implementation not required for Jun 30 beta)**

---

## Decision 5 — Event People: Speakers, Hosts, Moderators, Panelists

**Architecture status: ARCH REQUIRED — Week 4 | Implementation: DEFERRED**

Architecture document: `docs/architecture/event_people_speakers_architecture_v1.md`

### Current State

**This is an architecture gap, not a future feature.**

The `sessions` table (migration 002) has three per-session speaker columns: `speaker_name`,
`speaker_bio`, `speaker_photo_url`. These fields cover one speaker per session only.

The current public event detail API returns `sessions` and `speakers` as **empty arrays** or
hard-coded values — the sessions table data is not properly wired to the API response.

There is no concept of event-level people. A speaker is not the only type of person associated
with an event. The following roles need the same data model:
- HOST — person who runs the event
- MODERATOR — person who facilitates discussion
- SPEAKER — gives a talk (session-level or event-level)
- PANELIST — sits on a panel (session-level)
- CHIEF_GUEST — distinguished attendee with ceremonial role
- GUEST_OF_HONOUR — distinguished attendee, honoured rather than speaking
- ORGANIZER — event organizer shown publicly

### Recommended Architecture

**`event_people` table** — event-level people (all roles):
```sql
CREATE TABLE event_people (
    person_id      SERIAL        PRIMARY KEY,
    event_id       INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    full_name      TEXT          NOT NULL,
    designation    TEXT,
    organization   TEXT,
    bio            TEXT,
    photo_url      TEXT,
    linkedin_url   TEXT,
    role           VARCHAR(30)   NOT NULL
                   CHECK (role IN ('HOST','MODERATOR','SPEAKER','PANELIST',
                                   'CHIEF_GUEST','GUEST_OF_HONOUR','ORGANIZER')),
    sort_order     INT           NOT NULL DEFAULT 0,
    is_visible     BOOLEAN       NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ
);

CREATE INDEX idx_event_people_event_id ON event_people(event_id);
CREATE INDEX idx_event_people_role     ON event_people(event_id, role);
```

**`session_people` join table** — session-specific speakers and panelists:
```sql
CREATE TABLE session_people (
    session_id     INT           NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    person_id      INT           NOT NULL REFERENCES event_people(person_id) ON DELETE CASCADE,
    role           VARCHAR(30)   NOT NULL
                   CHECK (role IN ('SPEAKER','PANELIST','MODERATOR','HOST')),
    sort_order     INT           NOT NULL DEFAULT 0,
    PRIMARY KEY (session_id, person_id)
);
```

**Backward compatibility rule:**
The `speakers` field in the public event detail API must remain. When `event_people` is implemented,
`speakers` is derived as all `event_people` rows where `role IN ('SPEAKER','PANELIST',
'CHIEF_GUEST','GUEST_OF_HONOUR')`. This avoids breaking existing Flutter or website consumers.

**Future public event detail response shape:**
```json
{
  "event_id": 3,
  "people": [
    { "person_id": 1, "full_name": "Ravi Kumar", "role": "HOST", "designation": "...", "bio": "..." }
  ],
  "speakers": [
    { "person_id": 2, "full_name": "Priya Nair", "role": "SPEAKER", "designation": "...", "bio": "..." }
  ],
  "sessions": [
    {
      "session_id": 10,
      "title": "AI in Alumni Networks",
      "speakers": [
        { "person_id": 2, "full_name": "Priya Nair", "role": "SPEAKER" }
      ]
    }
  ]
}
```

### Decision

**[ ] ARCH DOCUMENT WRITTEN** (`event_people_speakers_architecture_v1.md`)
**[ ] IMPLEMENT APPROVED: __________________ Date: __________**
**[x] DEFERRED (default — architecture documentation only in Week 4)**

---

## Decision 6 — Sponsors

**Architecture status: ARCH REQUIRED — Week 4 | Implementation: DEFERRED**

Architecture document: `docs/architecture/event_sponsors_partners_architecture_v1.md`

### Current State

No sponsors table exists in any migration. The integration note and requirements documents do not
mention sponsors. This is a separate concept from partners and must be treated separately.

**Sponsors** provide financial or brand support. They have a tier hierarchy (Title, Gold, Silver,
Bronze, Associate). Their logo and link appear in prominent positions in event materials.

### Recommended Architecture

**`event_sponsors` table:**
```sql
CREATE TABLE event_sponsors (
    sponsor_id     SERIAL        PRIMARY KEY,
    event_id       INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    name           TEXT          NOT NULL,
    logo_url       TEXT,
    website_url    TEXT,
    sponsor_type   VARCHAR(30)   NOT NULL
                   CHECK (sponsor_type IN ('TITLE_SPONSOR','GOLD_SPONSOR','SILVER_SPONSOR',
                                           'BRONZE_SPONSOR','ASSOCIATE_SPONSOR')),
    description    TEXT,
    sort_order     INT           NOT NULL DEFAULT 0,
    is_visible     BOOLEAN       NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ
);
```

`sponsor_type` enum:
- `TITLE_SPONSOR` — primary/naming sponsor
- `GOLD_SPONSOR`
- `SILVER_SPONSOR`
- `BRONZE_SPONSOR`
- `ASSOCIATE_SPONSOR` — smaller supporting sponsor

### Decision

**[ ] ARCH DOCUMENT WRITTEN** (`event_sponsors_partners_architecture_v1.md`)
**[ ] IMPLEMENT APPROVED: __________________ Date: __________**
**[x] DEFERRED (default — architecture documentation only in Week 4)**

---

## Decision 7 — Partners

**Architecture status: ARCH REQUIRED — Week 4 | Implementation: DEFERRED**

Architecture document: `docs/architecture/event_sponsors_partners_architecture_v1.md`

### Current State

No partners table exists. Partners must **not** be merged with sponsors. They are a different
concept with a different type taxonomy and different display treatment.

**Partners** provide collaboration support: knowledge, media, community, venue, technology,
ecosystem, or hiring. They do not pay for placement in the same way sponsors do. The relationship
is one of collaboration, not sponsorship.

### Recommended Architecture

**`event_partners` table:**
```sql
CREATE TABLE event_partners (
    partner_id     SERIAL        PRIMARY KEY,
    event_id       INT           NOT NULL REFERENCES events(event_id) ON DELETE CASCADE,
    name           TEXT          NOT NULL,
    logo_url       TEXT,
    website_url    TEXT,
    partner_type   VARCHAR(30)   NOT NULL
                   CHECK (partner_type IN ('COMMUNITY_PARTNER','KNOWLEDGE_PARTNER',
                                           'MEDIA_PARTNER','VENUE_PARTNER',
                                           'TECHNOLOGY_PARTNER','ECOSYSTEM_PARTNER',
                                           'HIRING_PARTNER')),
    description    TEXT,
    sort_order     INT           NOT NULL DEFAULT 0,
    is_visible     BOOLEAN       NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ
);
```

`partner_type` enum:
- `COMMUNITY_PARTNER` — alumni associations, student groups
- `KNOWLEDGE_PARTNER` — research institutions, publications
- `MEDIA_PARTNER` — press, content platforms
- `VENUE_PARTNER` — venue provider
- `TECHNOLOGY_PARTNER` — tech platform or tool provider
- `ECOSYSTEM_PARTNER` — startup ecosystem, incubators
- `HIRING_PARTNER` — companies recruiting at the event

**Performance note:** Sponsors and partners are fetched in separate queries and returned as two
separate arrays in the public event detail response. Join complexity is minimal (one additional
query per table). Caching the full event detail response can be added later if needed.

### Decision

**[ ] ARCH DOCUMENT WRITTEN** (`event_sponsors_partners_architecture_v1.md`)
**[ ] IMPLEMENT APPROVED: __________________ Date: __________**
**[x] DEFERRED (default — architecture documentation only in Week 4)**

---

## Decision 8 — Meeting Link Generation

**Architecture status: ARCH DOCUMENTED — manual URL is permanent Alpha decision**

Architecture document: not required (decision is already closed for Alpha)

### Current State

`virtual_url` is a static `TEXT` column. The admin pastes the meeting URL when creating the event.
No OAuth integration with any meeting provider exists.

### Recommended Architecture (future)

If meeting provider integration is ever required:

```sql
ALTER TABLE events
  ADD COLUMN meeting_provider VARCHAR(20) DEFAULT 'MANUAL'
             CHECK (meeting_provider IN ('MANUAL','ZOOM','GOOGLE_MEET','TEAMS')),
  ADD COLUMN meeting_provider_id TEXT,
  ADD COLUMN meeting_provider_metadata JSONB;
```

Open questions that must be answered before implementation:
- Which provider first?
- Whose OAuth account creates the meeting — per-admin or one NITKSAA service account?
- Where to store refresh tokens securely?
- How to handle meeting creation failure gracefully?
- Can admin override a provider-generated link with a manual URL?

### Alpha Decision

**Static `virtual_url` only. Do not implement OAuth. Do not implement auto meeting generation.**
This is a permanent decision for Alpha and likely for all of 2026.

### Decision

**[x] DECIDED: Manual virtual_url — OAuth deferred indefinitely**

---

## Decision 9 — Analytics / Event Activity Log

**Architecture status: ARCH REQUIRED — Week 4 | Implementation: DEFERRED**

Architecture document: `docs/architecture/event_analytics_architecture_v1.md`

### Current State

`registered_count` is a correlated subquery. The existing `event_audit_log` is a security and
compliance trace — it records state changes by admin or system actors. It is not a product
analytics log.

**Audit log and analytics log are not the same:**

| | Audit log (`event_audit_log`) | Analytics log (`event_activity_log`) |
|---|---|---|
| Purpose | Security / compliance / admin trace | Product behaviour / statistics |
| Who writes | Backend services only | Flutter, admin portal, website |
| Consumers | Admin audit page, compliance | Admin statistics, product team |
| Noise level | Low — significant actions only | High — every user interaction |
| PII policy | Minimal context, no PII | No direct PII; may store `firebase_uid` |

### Recommended Architecture

**`event_activity_log` table:**
```sql
CREATE TABLE event_activity_log (
    activity_id    BIGSERIAL     PRIMARY KEY,
    event_id       INT           REFERENCES events(event_id) ON DELETE SET NULL,
    firebase_uid   VARCHAR(128), -- nullable: anonymous views allowed
    alumni_ref_id  VARCHAR(128), -- nullable
    session_id     INT           REFERENCES sessions(session_id) ON DELETE SET NULL,
    action_type    TEXT          NOT NULL,
    source_app     VARCHAR(20)   NOT NULL
                   CHECK (source_app IN ('flutter','admin','website')),
    metadata_json  JSONB,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    ip_hash        TEXT,         -- optional; store hash not raw IP
    user_agent     TEXT          -- optional
);

CREATE INDEX idx_activity_log_event_id    ON event_activity_log(event_id);
CREATE INDEX idx_activity_log_action_type ON event_activity_log(action_type, created_at);
CREATE INDEX idx_activity_log_uid         ON event_activity_log(firebase_uid)
                                          WHERE firebase_uid IS NOT NULL;
```

**Required action types:**
- `event_viewed` — event card seen in list
- `event_detail_opened` — event detail screen opened
- `register_clicked` — register CTA tapped
- `registration_completed` — successful registration
- `registration_failed` — registration attempt failed (with reason in metadata)
- `join_link_clicked` — virtual join link tapped
- `add_to_calendar_clicked`
- `venue_map_clicked`
- `email_sent` — confirmation email delivered
- `email_failed` — confirmation email failed (with error in metadata)
- `event_shared`
- `attendance_checked_in` — future, depends on QR check-in

**Privacy rules:**
1. Do not store email addresses, phone numbers, or names in the activity log.
2. Do not expose analytics data publicly.
3. Do not mix `event_activity_log` with `event_audit_log`.
4. `firebase_uid` may be stored; it is not directly PII but can be correlated.

### Decision

**[ ] ARCH DOCUMENT WRITTEN** (`event_analytics_architecture_v1.md`)
**[ ] IMPLEMENT APPROVED: __________________ Date: __________**
**[x] DEFERRED (default — architecture documentation only in Week 4)**

---

## Decision 10 — Engagement Rewards

**Architecture status: ARCH REQUIRED — Week 4 | Implementation: DEFERRED — do not implement**

Architecture document: `docs/architecture/engagement_rewards_architecture_v1.md`

### Current State

No engagement rewards, points, or gamification exists in any schema.

**Engagement rewards have a hard dependency chain:**
- Requires `event_activity_log` (Decision 9) to track reward-qualifying actions
- Requires QR check-in to confirm physical attendance (not yet built)
- Requires product definition: what actions earn points, how points are redeemed, whether they
  carry across events

### Recommended Architecture

**`engagement_rules` table:**
```sql
CREATE TABLE engagement_rules (
    rule_id        SERIAL        PRIMARY KEY,
    action_type    TEXT          NOT NULL,
    points         INT           NOT NULL,
    active         BOOLEAN       NOT NULL DEFAULT true,
    max_per_event  INT,          -- NULL = unlimited per event
    max_per_user   INT,          -- NULL = unlimited per user
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);
```

**`engagement_ledger` table** — one row per earned points event:
```sql
CREATE TABLE engagement_ledger (
    ledger_id          BIGSERIAL     PRIMARY KEY,
    firebase_uid       VARCHAR(128)  NOT NULL,
    alumni_ref_id      VARCHAR(128),
    event_id           INT           REFERENCES events(event_id) ON DELETE SET NULL,
    action_type        TEXT          NOT NULL,
    points_delta       INT           NOT NULL, -- positive = earned, negative = deducted
    reason             TEXT,
    source_activity_id BIGINT        REFERENCES event_activity_log(activity_id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);
```

**`user_engagement_summary` table** — materialised view of per-user totals:
```sql
CREATE TABLE user_engagement_summary (
    firebase_uid           VARCHAR(128)  PRIMARY KEY,
    alumni_ref_id          VARCHAR(128),
    total_points           INT           NOT NULL DEFAULT 0,
    events_attended_count  INT           NOT NULL DEFAULT 0,
    last_activity_at       TIMESTAMPTZ
);
```

### Decision

**[ ] ARCH DOCUMENT WRITTEN** (`engagement_rewards_architecture_v1.md`)
**[x] DEFERRED — do not implement in Week 4 under any circumstances**
**Dependencies not met: analytics log + QR check-in must be live first**

---

## Decision 11 — Registration Fee / Paid Events

**Architecture status: ARCH REQUIRED — Week 4 | Implementation: DEFERRED — free only for Alpha**

Architecture document: `docs/architecture/paid_events_architecture_v1.md`

### Current State

No payment fields in the events or registrations table. The integration note explicitly states:
do not implement payment. All Alpha events are free.

### Recommended Architecture

**Events table additions (schema change, deferred):**
```sql
ALTER TABLE events
  ADD COLUMN registration_fee_type VARCHAR(10) NOT NULL DEFAULT 'FREE'
             CHECK (registration_fee_type IN ('FREE','PAID')),
  ADD COLUMN registration_fee_amount NUMERIC(10,2),
  ADD COLUMN registration_fee_currency VARCHAR(3) DEFAULT 'INR',
  ADD COLUMN payment_required BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN payment_provider VARCHAR(30);  -- RAZORPAY | STRIPE | null
```

**Future `event_payments` table:**
```sql
CREATE TABLE event_payments (
    payment_id           SERIAL        PRIMARY KEY,
    registration_id      INT           NOT NULL REFERENCES registrations(registration_id),
    event_id             INT           NOT NULL REFERENCES events(event_id),
    firebase_uid         VARCHAR(128)  NOT NULL,
    amount               NUMERIC(10,2) NOT NULL,
    currency             VARCHAR(3)    NOT NULL DEFAULT 'INR',
    provider             VARCHAR(30)   NOT NULL,
    provider_payment_id  TEXT,
    provider_order_id    TEXT,
    status               VARCHAR(20)   NOT NULL
                         CHECK (status IN ('pending','completed','failed','refunded')),
    paid_at              TIMESTAMPTZ,
    created_at           TIMESTAMPTZ   NOT NULL DEFAULT now()
);
```

### Alpha Decision

All Alpha events are free. `registration_fee_type = 'FREE'` is the default and the only value
used in Alpha. The "Free" label on event detail screens is derived from this field (or assumed
when the field does not yet exist).

**Do not implement payment gateway. Do not collect payment. Do not integrate Razorpay or Stripe.**

### Decision

**[ ] ARCH DOCUMENT WRITTEN** (`paid_events_architecture_v1.md`)
**[x] DEFERRED — free events only for Alpha; no payment implementation**

---

## Summary Table

| # | Decision | Architecture Status | Implementation |
|---|---|---|---|
| 1 | Real email delivery | IMPLEMENT APPROVED | Gmail SMTP, `EMAIL_MODE=send` |
| 2 | Alumni DB local dev | IMPLEMENT APPROVED | Local db + seed script + README |
| 3 | Login message cleanup | IMPLEMENT APPROVED | Flutter polish, no backend change |
| 4 | Full day / all day event | ARCH REQUIRED — Week 4 | Deferred — needs migration |
| 5 | People / speakers / hosts | ARCH REQUIRED — Week 4 | Deferred — new tables |
| 6 | Sponsors | ARCH REQUIRED — Week 4 | Deferred — new table |
| 7 | Partners (separate from sponsors) | ARCH REQUIRED — Week 4 | Deferred — new table |
| 8 | Meeting link generation | DECIDED — manual URL | OAuth deferred indefinitely |
| 9 | Analytics / event activity log | ARCH REQUIRED — Week 4 | Deferred — new table |
| 10 | Engagement rewards | ARCH REQUIRED — Week 4 | Deferred — do not implement |
| 11 | Registration fee / paid events | ARCH REQUIRED — Week 4 | Deferred — free only |

**Decisions 1–3: resolve before implementation begins.**
**Decisions 4–11: write architecture document in Week 4; implementation only if product owner approves.**
