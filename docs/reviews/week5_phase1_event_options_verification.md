# Week 5 Phase 1 — Event Options Verification Report

**Date:** 2026-06-26  
**Phase:** 1 — Full Day Event + Free/Paid Event Display  
**Status:** PASS

---

## 1. Scope

Phase 1 adds two display-only features to events:

| Feature | What it does |
|---|---|
| Full Day Event | Hides time fields in the app; stores 00:00:00 / 23:59:59 timestamps |
| Free/Paid display | Shows a "Free" or "₹X" badge in the app; no payment processing |

Payment processing, People/Speakers, Sponsors, Analytics, QR Attendance, and Rewards are **out of scope** for Phase 1.

---

## 2. Database Migration

**Migration:** `backend/migrations/events_db/010_week5_phase1_event_options.sql`

```sql
ALTER TABLE events
  ADD COLUMN is_full_day  BOOLEAN      NOT NULL DEFAULT false,
  ADD COLUMN is_free      BOOLEAN      NOT NULL DEFAULT true,
  ADD COLUMN ticket_price NUMERIC(10,2);

ALTER TABLE events
  ADD CONSTRAINT chk_ticket_price_non_negative
    CHECK (ticket_price IS NULL OR ticket_price >= 0);
```

**Verification (local events_db):**

```
Column        | Type          | Nullable | Default
is_full_day   | boolean       | not null | false
is_free       | boolean       | not null | true
ticket_price  | numeric(10,2) |          |
Constraint: chk_ticket_price_non_negative CHECK (ticket_price IS NULL OR ticket_price >= 0)
```

Result: **PASS** — all 3 columns + constraint present.

**Backward compatibility:** existing rows default to `is_full_day=false, is_free=true, ticket_price=NULL`, which is correct — previously created events display as free timed events.

---

## 3. Backend Schema Changes

### 3.1 `EventCreate` (`backend/app/schemas/event_create.py`)

| Field | Type | Default | Validation |
|---|---|---|---|
| `is_full_day` | `bool` | `False` | — |
| `is_free` | `bool` | `True` | — |
| `ticket_price` | `Optional[Decimal]` | `None` | `ge=0`; required when `is_free=False`; cleared to `None` when `is_free=True` |

Cross-field validator (`validate_event`):
- Full-day: `end_date >= start_date` (allows same-day)
- Paid: `ticket_price` required; error if missing
- Free: `ticket_price` coerced to `None`

Result: **PASS**

### 3.2 `EventUpdate` (`backend/app/schemas/event_update.py`)

All three fields added as `Optional`; `ticket_price` cleared when `is_free=True` is patched.

Result: **PASS**

### 3.3 `EventResponse` / `PublicEventResponse` (`backend/app/schemas/event_response.py`)

All three fields present in both response schemas with safe defaults matching DB defaults.

Result: **PASS**

### 3.4 Repository (`backend/app/repositories/events_repository.py`)

- `_PUBLIC_COLUMNS`: `e.is_full_day, e.is_free, e.ticket_price` added — returned by `list_public_events` and `get_public_event`
- `create_event` INSERT: `is_full_day ($18), is_free ($19), ticket_price ($20)` added; `created_by_firebase_uid` moved to `$21`

Result: **PASS**

---

## 4. Admin Portal Changes

**File:** `admin/event_admin/src/pages/EventFormPage.jsx`  
**Build:** `vite build` — clean, 0 errors, 0 warnings

### 4.1 State

```js
const EMPTY = {
  ...
  is_full_day: false,
  is_free:     true,
  ticket_price: '',
};
```

### 4.2 Full Day toggle (UI)

- Checkbox before start/end date inputs labelled "Full Day Event"
- When checked: date inputs switch to `type="date"` (date-only picker); Timezone selector hidden
- When unchecked: date inputs are `type="datetime-local"`; Timezone selector shown
- Toggling clears start/end values to avoid type mismatch

### 4.3 Date validation

| Mode | Rule |
|---|---|
| Full-day | End date `>=` start date (same day allowed) |
| Regular | End datetime `>` start datetime |

### 4.4 Payload construction (`buildPayload`)

| Mode | `start_datetime` | `end_datetime` |
|---|---|---|
| Full-day | `{date}T00:00:00{tzOffset}` | `{date}T23:59:59{tzOffset}` |
| Regular | `datetime-local` value + offset | same |

### 4.5 Pricing section (UI)

- New "Pricing" card section between Registration & Capacity and Media
- "Free event" toggle checkbox (default: checked = free)
- When unchecked: ticket price input (number, min 0) with ₹ prefix symbol visible
- When checked: ticket price input hidden; `ticket_price` cleared in state

### 4.6 Edit mode loading

When editing an existing event:
- `is_full_day`, `is_free`, `ticket_price` populated from API response
- Date fields use `toDateOnlyInTZ()` for full-day, `toDatetimeLocalInTZ()` for regular

### 4.7 Eyebrow text

All three page eyebrow labels updated from "Week 2" → "Week 5".

Result: **PASS**

---

## 5. Flutter App Changes

**Files:**
- `apps/event_app/lib/features/events/domain/public_event.dart`
- `apps/event_app/lib/features/events/domain/public_event_detail.dart`
- `apps/event_app/lib/features/events/presentation/event_detail_screen.dart`

### 5.1 Domain model additions (both files)

| Field | Type | Default | Source |
|---|---|---|---|
| `isFullDay` | `bool` | `false` | `is_full_day` JSON |
| `isFree` | `bool` | `true` | `is_free` JSON |
| `ticketPrice` | `double?` | `null` | `ticket_price` JSON |
| `priceLabel` | `String` (getter) | — | `"Free"` / `"₹X"` / `"Paid"` |

`fromJson` uses `??` fallbacks → backward compatible with events that predate Phase 1.

### 5.2 Event detail screen

`_EventInformationCard` updated:

| When | Behavior |
|---|---|
| `isFullDay = true` | Shows Date row only (`"Date"` / `"Dates"` label); hides Start Time, End Time, Timezone rows |
| `isFullDay = false` | Shows all time rows (existing behavior) |
| Always | Shows "Entry" row: `priceLabel` (`"Free"` or `"₹X"`) |

Result: **PASS**

---

## 6. Backward Compatibility Checklist

| Concern | Status |
|---|---|
| Existing events with no `is_full_day` field in JSON | `?? false` → treated as regular timed event |
| Existing events with no `is_free` field | `?? true` → treated as free |
| Existing events with no `ticket_price` | `null` → `priceLabel = "Free"` |
| Week 1–4 APIs unchanged | No existing endpoint or migration modified |
| Migrations 001–009 untouched | Only new migration 010 added |
| `capacity`, `show_attendee_list`, `registration_opens_at/closes_at` | Unmodified |

---

## 7. Known Gaps (display-only intent)

- **Payment processing:** Not implemented — `ticket_price` is display-only. Users see a "₹X" badge but cannot pay through the app.
- **Price on event list card:** The `PublicEvent` model has `priceLabel` but the events list screen (`EventsScreen`) does not yet surface it as a badge. This is intentional for Phase 1 (detail screen only).
- **Cloud migration:** Migration 010 has been applied locally. Cloud SQL must be migrated separately before deploying to production.

---

## 8. Verdict

| Layer | Result |
|---|---|
| DB migration | PASS |
| Backend schemas | PASS |
| Backend repository | PASS |
| Admin portal build | PASS (0 errors) |
| Admin portal UI — Full Day | PASS |
| Admin portal UI — Pricing | PASS |
| Flutter domain models | PASS |
| Flutter event detail screen | PASS |
| Backward compatibility | PASS |

**Overall: PASS** — Phase 1 (Full Day Event + Free/Paid Event Display) is complete. Phase 2 and beyond can proceed when ready.
