# Event Analytics / Activity Log — Architecture v1

**Date:** 2026-06-22
**Status:** ARCHITECTURE DOCUMENT — do not implement without product owner approval
**Depends on:** migrations 001–009 (existing), events, sessions, registrations tables
**Related decisions:** `week4_feedback_architecture_decisions.md` Decision 9

---

## Audit Log vs. Analytics Log

The existing `event_audit_log` table (migration 006, migration 009) is a **security and
compliance trace**. It records state changes performed by admin or system actors. It answers:
"Who changed what, and when?"

An analytics or activity log is different in purpose, volume, and consumer.

| Dimension | Audit log (`event_audit_log`) | Analytics log (`event_activity_log`) |
|---|---|---|
| Purpose | Security / compliance / admin trace | Product behaviour / statistics / funnel |
| Who writes it | Backend services only (on state transitions) | Flutter, admin portal, website (on user interactions) |
| Typical consumers | Admin audit page, compliance review | Admin stats, product team |
| Volume | Low — significant state changes only | High — every screen view and interaction |
| PII exposure risk | Minimal — context column has no PII | Moderate — `firebase_uid` may be stored |
| Noise level | Low | High by design |
| Must never lose rows | Yes — audit integrity | No — analytics can tolerate minor loss |

These are different concerns and must not share a table. The audit log must remain reliable and
low-volume. The analytics log is intentionally noisy.

---

## Required Action Types

These are the analytics events the product team confirmed are needed:

| Action type | Triggered by | Source app |
|---|---|---|
| `event_viewed` | Event card appears on list screen | flutter, website |
| `event_detail_opened` | Event detail screen opens | flutter, website |
| `register_clicked` | Register CTA tapped / clicked | flutter, website |
| `registration_completed` | Successful `POST /register` response | flutter (via backend callback) |
| `registration_failed` | Failed `POST /register` response (any error) | flutter (via backend callback) |
| `join_link_clicked` | Virtual join link tapped | flutter |
| `add_to_calendar_clicked` | "Add to calendar" tapped | flutter |
| `venue_map_clicked` | Venue map link tapped | flutter |
| `email_sent` | Confirmation email delivered (`status='sent'`) | backend (event app) |
| `email_failed` | Confirmation email failed (`status='failed'`) | backend (event app) |
| `event_shared` | Share action used | flutter |
| `attendance_checked_in` | QR check-in completed successfully | flutter / admin (future) |

Future additions (not required for Alpha):
- `session_detail_opened`
- `speaker_profile_tapped`
- `sponsor_link_clicked`
- `feedback_submitted`

---

## Proposed Schema

### Table: `event_activity_log`

```sql
CREATE TABLE event_activity_log (
    activity_id    BIGSERIAL     PRIMARY KEY,
    event_id       INT           REFERENCES events(event_id) ON DELETE SET NULL,
    firebase_uid   VARCHAR(128), -- nullable: anonymous views are valid
    alumni_ref_id  VARCHAR(128), -- nullable: non-alumni users have no ref_id
    session_id     INT           REFERENCES sessions(session_id) ON DELETE SET NULL,
    action_type    TEXT          NOT NULL,
    source_app     VARCHAR(20)   NOT NULL
                   CHECK (source_app IN ('flutter', 'admin', 'website')),
    metadata_json  JSONB,        -- action-specific detail; no PII
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    ip_hash        TEXT,         -- optional; SHA-256 of client IP, not raw IP
    user_agent     TEXT          -- optional
);

CREATE INDEX idx_activity_log_event_id    ON event_activity_log(event_id);
CREATE INDEX idx_activity_log_action_type ON event_activity_log(action_type, created_at);
CREATE INDEX idx_activity_log_uid         ON event_activity_log(firebase_uid)
                                          WHERE firebase_uid IS NOT NULL;
CREATE INDEX idx_activity_log_created_at  ON event_activity_log(created_at);
```

### Column notes

- `activity_id` — BIGSERIAL (not SERIAL) — analytics tables accumulate rows quickly; INT range
  (2 billion) is theoretically reachable over the lifetime of the platform.
- `event_id` — `ON DELETE SET NULL`, not CASCADE. If an event is cancelled (soft-deleted to
  `cancelled` status), its activity history must not disappear. `event_id` becomes NULL but the
  row is retained.
- `session_id` — only populated for session-level actions; NULL for event-level actions.
- `firebase_uid` — nullable. Anonymous event views (unauthenticated users on the website)
  produce activity rows with no `firebase_uid`.
- `alumni_ref_id` — nullable. Non-alumni Firebase users have no `ref_id`.
- `metadata_json` — structured payload per action type. See examples below. Must not contain
  PII (no names, emails, phone numbers).
- `ip_hash` — if stored, must be a hash (SHA-256 or SHA-3), not the raw IP address.
- `user_agent` — optional; useful for distinguishing mobile vs. web traffic.

### Example `metadata_json` payloads

```json
// event_viewed
{ "list_position": 2, "tab": "upcoming" }

// registration_failed
{ "error_code": "event_full", "capacity": 30, "registered_count": 30 }

// email_sent
{ "registration_number": "NITKSAA-2026-000042" }

// email_failed
{ "error": "Connection refused", "registration_number": "NITKSAA-2026-000042" }

// join_link_clicked
{ "is_virtual": true }
```

No alumni names, emails, or phone numbers appear in `metadata_json`.

---

## Privacy Rules

1. **Do not store email addresses, full names, or phone numbers** in `event_activity_log`.
2. **`firebase_uid` is not directly PII** but can be correlated with a user record. Store it
   only when the user is authenticated and the action is user-attributed.
3. **Do not expose analytics data publicly** via any API endpoint. Analytics are admin-only.
4. **`ip_hash` only** — never store raw IP addresses. Hash before storing.
5. **Separate from `event_audit_log`** — do not write analytics events to the audit table.
   The audit table has different retention and access rules.
6. **No analytics data in registration or alumni tables** — keep the analytics log isolated.

---

## Source App Values

| `source_app` | Who writes it | How |
|---|---|---|
| `flutter` | Flutter event app client | Client-side call to a new `POST /api/v1/analytics/event` endpoint (fire-and-forget, 202 response) |
| `admin` | React admin portal | Same endpoint; admin auth token |
| `website` | NITKSAA website backend | Same endpoint; server-side, or direct DB write via shared connection |

Backend-generated events (`email_sent`, `email_failed`, `registration_completed`) are written
directly by the FastAPI backend — no client call required.

---

## Admin Reporting Examples

These are examples of queries the admin statistics page can run against `event_activity_log`:

**Registration funnel for one event:**
```sql
SELECT action_type, COUNT(*) AS count
FROM event_activity_log
WHERE event_id = $1
  AND action_type IN (
    'event_detail_opened', 'register_clicked',
    'registration_completed', 'registration_failed'
  )
GROUP BY action_type;
```

**Registrations per day for one event:**
```sql
SELECT DATE(created_at AT TIME ZONE 'Asia/Kolkata') AS day,
       COUNT(*) AS registrations
FROM event_activity_log
WHERE event_id = $1
  AND action_type = 'registration_completed'
GROUP BY day
ORDER BY day;
```

**Email delivery success rate:**
```sql
SELECT
  SUM(CASE WHEN action_type = 'email_sent' THEN 1 ELSE 0 END) AS sent,
  SUM(CASE WHEN action_type = 'email_failed' THEN 1 ELSE 0 END) AS failed
FROM event_activity_log
WHERE event_id = $1;
```

---

## Flutter Integration Pattern

When implemented, Flutter writes analytics events fire-and-forget:

```dart
// Fire and forget — never awaited, never shown to user
unawaited(
  _analyticsService.track(
    eventId: event.eventId,
    actionType: 'register_clicked',
    sourceApp: 'flutter',
  ),
);
```

The analytics API endpoint returns `202 Accepted` immediately. The Flutter app does not wait
for confirmation and does not show errors if the call fails. Analytics failures must never affect
user-facing flows.

---

## Implementation Recommendation

**Do not implement in Week 4.** Write this document. Implementation depends on:

1. A new `POST /api/v1/analytics/event` endpoint (or equivalent)
2. Flutter `AnalyticsService` class
3. The backend writing `email_sent`/`email_failed`/`registration_completed` events directly

These are independent additions that do not affect any Week 4 deliverable. The `registered_count`
correlated subquery is sufficient for the Jun 30 beta demo. Analytics are a post-Alpha addition.
