# Engagement Rewards — Architecture v1

**Date:** 2026-06-22
**Status:** ARCHITECTURE DOCUMENT — do not implement in Week 4 under any circumstances
**Depends on:** event_analytics_architecture_v1.md, QR check-in (not yet built)
**Related decisions:** `week4_feedback_architecture_decisions.md` Decision 10

---

## Concept

Engagement rewards give alumni points for participating in NITKSAA events. Points accumulate
across events and can be used to recognize active alumni, unlock privileges, or be displayed
as a badge on their alumni profile.

The reward system turns event attendance into a measurable record of alumni engagement with
the NITKSAA community — useful for:
- Recognizing the most active alumni
- Encouraging early registration
- Incentivizing check-in rather than no-show
- Creating a long-term alumni engagement metric visible on the alumni portal

---

## Dependency Chain

Engagement rewards cannot be implemented until both of the following are live:

1. **`event_activity_log`** (from `event_analytics_architecture_v1.md`) — required to track
   reward-qualifying actions such as `registration_completed`, `attendance_checked_in`,
   `add_to_calendar_clicked`.

2. **QR check-in** — required to confirm physical attendance. Awarding `attend_event` points
   requires verified presence, not just registration. Without QR check-in, attendance cannot
   be confirmed.

Implementing rewards before these dependencies are live would require either:
- Awarding points on registration (not attendance — gameable), or
- Implementing a separate attendance confirmation mechanism

Neither is acceptable. Rewards implementation is blocked until analytics + check-in are both live.

---

## Rewardable Actions

| Action type | Trigger | Example points |
|---|---|---|
| `register_for_event` | Successful registration | 10 |
| `attend_event` | QR check-in confirmed | 50 |
| `attend_multiple_events` | Nth event attendance (e.g., 5th event) | 100 bonus |
| `check_in_on_time` | Check-in before event start | 20 |
| `volunteer` | Assigned as volunteer for an event | 30 |
| `refer_alumni` | New alumni registers via referral link | 25 |
| `provide_feedback` | Submits post-event feedback | 15 |
| `ask_question` | Question submitted during Q&A | 5 |

The specific point values are a product decision. These are illustrative only. The `engagement_rules`
table makes them configurable without a code deploy.

---

## Proposed Schema

### Table: `engagement_rules`

Configurable rules table. An admin can adjust point values and activation status without a code
deploy.

```sql
CREATE TABLE engagement_rules (
    rule_id        SERIAL        PRIMARY KEY,
    action_type    TEXT          NOT NULL UNIQUE,
    points         INT           NOT NULL,
    active         BOOLEAN       NOT NULL DEFAULT true,
    max_per_event  INT,          -- NULL = unlimited per event per user
    max_per_user   INT,          -- NULL = unlimited lifetime per user
    description    TEXT,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ
);
```

Example seed data:
```
action_type              points  active  max_per_event  max_per_user
register_for_event       10      true    1              NULL
attend_event             50      true    1              NULL
attend_multiple_events   100     false   NULL           NULL
check_in_on_time         20      true    1              NULL
volunteer                30      true    NULL           NULL
provide_feedback         15      true    1              NULL
```

### Table: `engagement_ledger`

Append-only log of every points transaction. One row per earning event. Never updated — only
inserted. Negative `points_delta` is used for deductions (e.g., reversal on registration
cancellation).

```sql
CREATE TABLE engagement_ledger (
    ledger_id           BIGSERIAL     PRIMARY KEY,
    firebase_uid        VARCHAR(128)  NOT NULL,
    alumni_ref_id       VARCHAR(128), -- nullable for non-alumni
    event_id            INT           REFERENCES events(event_id) ON DELETE SET NULL,
    action_type         TEXT          NOT NULL,
    points_delta        INT           NOT NULL,  -- positive = earned, negative = deducted
    reason              TEXT,                    -- human-readable explanation
    source_activity_id  BIGINT
                        REFERENCES event_activity_log(activity_id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX idx_ledger_firebase_uid ON engagement_ledger(firebase_uid);
CREATE INDEX idx_ledger_event_id     ON engagement_ledger(event_id)
                                     WHERE event_id IS NOT NULL;
CREATE INDEX idx_ledger_action_type  ON engagement_ledger(action_type, created_at);
```

### Table: `user_engagement_summary`

Materialised summary per user — updated by a trigger or background job when new ledger rows
are inserted. Avoids re-aggregating the full ledger on every profile view.

```sql
CREATE TABLE user_engagement_summary (
    firebase_uid           VARCHAR(128)  PRIMARY KEY,
    alumni_ref_id          VARCHAR(128), -- nullable
    total_points           INT           NOT NULL DEFAULT 0,
    events_attended_count  INT           NOT NULL DEFAULT 0,
    last_activity_at       TIMESTAMPTZ,
    updated_at             TIMESTAMPTZ   NOT NULL DEFAULT now()
);
```

Update strategy options (decide at implementation time):
- PostgreSQL trigger on `engagement_ledger` INSERT — synchronous, simple
- Background job (Celery or asyncpg LISTEN/NOTIFY) — async, scales better
- Recompute on-demand for display — no separate table needed; slower at scale

---

## Earning Flow (when implemented)

```
User action (e.g., attend_event via QR check-in)
    │
    ▼
event_activity_log INSERT (action_type='attendance_checked_in')
    │
    ▼
Reward engine: look up engagement_rules WHERE action_type='attend_event' AND active=true
    │
    ├── max_per_event check: has this user earned attend_event for this event already?
    │   (check engagement_ledger WHERE firebase_uid=$uid AND event_id=$eid AND action_type='attend_event')
    │
    └── if eligible:
        INSERT INTO engagement_ledger (firebase_uid, event_id, action_type, points_delta=50, ...)
            │
            └── UPDATE user_engagement_summary (total_points += 50, events_attended_count += 1)
```

Cancellation reversal: if a registration is cancelled, deduct the `register_for_event` points:
```sql
INSERT INTO engagement_ledger (firebase_uid, event_id, action_type, points_delta=-10,
                                reason='Registration cancelled')
```

---

## Integration with Alumni Portal

When the alumni portal (`nitksaa-portal-v2`) displays alumni profiles, it can call the Event
App API to retrieve the `total_points` and `events_attended_count` for a given `alumni_ref_id`.

This is a future cross-app integration. The `user_engagement_summary` table provides the data.
The endpoint would be:

```
GET /api/v1/alumni/{ref_id}/engagement-summary
→ { "total_points": 285, "events_attended_count": 4, "last_activity_at": "..." }
```

This endpoint is authenticated (not public). The portal calls it server-side.

---

## Implementation Recommendation

**Do not implement in Week 4. Do not implement until both dependencies are live.**

Blocking dependencies:
1. `event_activity_log` (Decision 9 in feedback architecture decisions) must be implemented first
2. QR check-in must be live — without it, physical attendance cannot be confirmed

Engagement rewards are a post-Alpha feature. They should not appear in the Jun 30 beta demo.
Document the architecture now. Revisit at the first post-Alpha architecture review.
