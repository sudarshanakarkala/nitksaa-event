# Week 3 — Phase 2 Backend Foundation Report

**Date:** 2026-06-18  
**Branch:** main  
**Status:** COMPLETE — all 10 implementation tasks finished, app loads cleanly

---

## Summary

Phase 2 backend foundation is fully implemented. All 8 new/rewritten source files are in place, two existing files are fixed, and the FastAPI app registers 37 routes with zero import errors.

Alumni can now:
- `GET /api/v1/alumni/me` — fetch their own profile from alumni_db
- `POST /api/v1/events/{event_id}/register` — register for an event (201)
- `GET /api/v1/events/{event_id}/my-registration` — fetch their own registration
- `GET /api/v1/my/registrations` — list all their registrations across events
- `GET /api/v1/events/{event_id}/registration-eligibility` — check eligibility

---

## Files Created / Modified

### Created (new)

| File | Lines | Purpose |
|---|---|---|
| `app/services/audit_service.py` | 36 | `emit()` adapter for `event_audit_log`; never raises |
| `app/services/email_service.py` | 78 | `EmailResult` dataclass; log/send modes; never raises |
| `app/api/alumni.py` | 31 | `GET /api/v1/alumni/me` |
| `app/api/registrations.py` | 53 | 4 registration endpoints |

### Rewritten (replaced broken alpha code)

| File | Previous State | New State |
|---|---|---|
| `app/repositories/registration_repository.py` | Alpha-era, referenced missing tables (`attendees`), wrong columns | Clean 7-method class targeting 21-column migration 008 schema |
| `app/services/registration_service.py` | Class-based, referenced `RegistrationService`, `generate_qr_token`, `attendees` table | Module-level functions with transaction safety and email-after-commit policy |
| `app/schemas/registrations.py` | Alpha-era schemas with `AttendeeResponse`, wrong field names | 6 clean Pydantic models for Week 3 contract |

### Modified (extended)

| File | Change |
|---|---|
| `app/config.py` | Added 8 email settings (`EMAIL_MODE`, `EMAIL_FROM`, `SMTP_*`, etc.) |
| `app/services/alumni_service.py` | Added `ACTIVE_ALUMNI_STATUSES`, `is_alumni_active()`, `get_alumni_profile_by_ref_id()` |
| `app/repositories/events_repository.py` | Added correlated subquery for `registered_count` to `_SELECT_WITH_CREATOR` and `_PUBLIC_COLUMNS` |
| `app/services/events_service.py` | Replaced `d["registered_count"] = 0` with `d.setdefault("registered_count", 0)` in both `_enrich()` and `_with_public_card_metadata()` |
| `app/main.py` | Registered `alumni.router` and `registrations.router` |

### Side-fix

| File | Change |
|---|---|
| `app/api/admin_events.py` | Removed broken `RegistrationService` and `AttendeeResponse` imports; stubbed admin registration/attendee list endpoints with `501 Not Implemented` |

---

## Implementation Details

### Registration Repository (`registration_repository.py`)

7 methods targeting the 21-column schema (migration 008):

| Method | Purpose |
|---|---|
| `count_active(event_id)` | Count `status='registered'` rows for capacity enforcement |
| `get_active_for_user(event_id, firebase_uid)` | Duplicate registration check |
| `insert(...)` | INSERT with asyncpg `$N` params; `RETURNING registration_id` |
| `set_registration_number(registration_id, registration_number)` | UPDATE after INSERT |
| `update_email_status(registration_id, status, sent_at, error)` | Non-transactional post-commit update |
| `get_by_id_with_event(registration_id)` | Fetch full row with JOIN to events |
| `get_latest_for_user_event(event_id, firebase_uid)` | Any-status lookup for my-registration endpoint |
| `list_for_user(firebase_uid)` | All registrations across events for a user |

Column aliasing in `_REG_WITH_EVENT` SELECT clause:
- `r.email AS email_snapshot`
- `r.phone AS phone_snapshot`
- `r.notes AS attendee_note`
- `e.virtual_url` fetched but never returned directly (resolved via `_resolve_join_url`)

### Audit Service (`audit_service.py`)

Single `emit()` function. Wrapped in `try/except Exception` — all failures logged with `[audit]` prefix, never re-raised. Uses `json.dumps(context)` + `::jsonb` cast for the context column.

Security: caller documentation states context must not contain firebase_uid, email, phone, join URLs, or tokens.

### Email Service (`email_service.py`)

`EmailResult(status, sent_at, error)` dataclass.

`send_confirmation_email()` dispatch table:

| `EMAIL_MODE` | Behaviour |
|---|---|
| `log` (default) | Writes to Python logger; returns `status="sent"` with current timestamp |
| `send` | Uses `smtplib.SMTP` with `starttls()` and login; returns `status="sent"` or `status="failed"` |
| other | Logs warning; returns `status="skipped"` |

Never raises in any mode. All SMTP exceptions caught and returned as `EmailResult(status="failed", ...)`.

### Registration Service (`registration_service.py`)

Module-level async functions (not a class). Key design decisions:

**Transaction scope for `register_for_event`:**
```
1. alumni_service.get_alumni_profile_by_ref_id()  ← separate pool, before transaction
2. async with pool.acquire() as conn:
3.   async with conn.transaction():
4.     SELECT events ... FOR UPDATE            ← locks event row
5.     Check status, window, duplicate, capacity
6.     INSERT registration RETURNING id
7.     UPDATE registration_number              ← within same transaction
8.   # COMMIT
9.   get_by_id_with_event()                   ← same conn, no transaction
10. # release conn
11. send_confirmation_email()                  ← after commit, never rollback
12. async with pool.acquire() as conn2:
13.   update_email_status()                   ← non-transactional
14. audit_service.emit()                       ← must never raise
```

**`_resolve_join_url(row)` — join_url reveal logic:**
```python
if status == "registered" and is_virtual and event_status == "published":
    return virtual_url
return None
```
`virtual_url` is fetched by the repository JOIN but only exposed through this function — it never appears directly in the response dict.

**Registration number format:** `NITKSAA-{year}-{registration_id:06d}`  
Example: `NITKSAA-2026-000042`

### Alumni API (`api/alumni.py`)

Single endpoint `GET /api/v1/alumni/me`. Guards: `user_type == "alumni"` AND `ref_id is not None`. Calls `get_alumni_profile_by_ref_id(ref_id)` — alumni_db is authoritative. Maps `alumni_id → ref_id`, `graduationyear → batch_year`.

### Registrations API (`api/registrations.py`)

| Method | Path | Auth | Status |
|---|---|---|---|
| `POST` | `/api/v1/events/{event_id}/register` | Required | `201` |
| `GET` | `/api/v1/events/{event_id}/my-registration` | Required | `200` / `404` |
| `GET` | `/api/v1/my/registrations` | Required | `200` |
| `GET` | `/api/v1/events/{event_id}/registration-eligibility` | Required | `200` |

### registered_count Fix

`events_repository.py` — both `_SELECT_WITH_CREATOR` and `_PUBLIC_COLUMNS` now include:
```sql
(SELECT COUNT(*) FROM registrations r
 WHERE r.event_id = e.event_id AND r.status = 'registered') AS registered_count
```

`events_service.py` — `_enrich()` and `_with_public_card_metadata()` changed from:
```python
d["registered_count"] = 0  # hardcoded placeholder
```
to:
```python
d.setdefault("registered_count", 0)  # use query result, default 0 if absent
```

This means all event list/detail endpoints now return live registered counts instead of the Week 2 hardcoded zero.

---

## Validation

### Compilation

```
python -m compileall -f app
```

**Result:** 40 files compiled — 0 errors, 0 warnings.

### Import check

```
python -c "from app.services import audit_service, email_service, registration_service, alumni_service; from app.api import alumni, registrations; ..."
```

**Result:** `all imports OK`

### App load and route listing

```
python -c "from app.main import app; ..."
```

**Result:** `main app loaded OK` — 37 routes registered.

**New routes confirmed:**

| Method | Path |
|---|---|
| `GET` | `/api/v1/alumni/me` |
| `POST` | `/api/v1/events/{event_id}/register` |
| `GET` | `/api/v1/events/{event_id}/my-registration` |
| `GET` | `/api/v1/my/registrations` |
| `GET` | `/api/v1/events/{event_id}/registration-eligibility` |

---

## Error Codes Reference

| Code | Endpoint | Meaning |
|---|---|---|
| `403 alumni_only` | POST /register | user_type ≠ 'alumni' or ref_id is None |
| `403 alumni_not_found` | POST /register | ref_id not in alumni_db |
| `403 alumni_not_active` | POST /register | registrationstatus not in {Active, Self-Verified} |
| `404 event_not_found` | POST /register | event_id does not exist |
| `409 event_not_published` | POST /register | event.status ≠ 'published' |
| `409 registration_not_open_yet` | POST /register | now < registration_opens_at |
| `409 registration_closed` | POST /register | now > registration_closes_at |
| `409 already_registered` | POST /register | active registration exists (partial unique index hit) |
| `409 event_full` | POST /register | COUNT(status='registered') ≥ capacity |
| `404 registration_not_found` | GET /my-registration | no registration row for user+event |
| `403 alumni_only` | GET /alumni/me | user_type ≠ 'alumni' |
| `404 alumni_profile_not_found` | GET /alumni/me | ref_id not in alumni_db |

---

## Security Invariants Maintained

| Invariant | Implementation |
|---|---|
| `virtual_url` never in public APIs | `_PUBLIC_COLUMNS` excludes it; `_resolve_join_url()` is only called in registration service |
| `join_url` only in authenticated registration endpoints | Only appears in `RegistrationResponse`, returned only by registration service |
| Email failure never rollbacks registration | Email sent after `conn.transaction()` exits; `update_email_status` uses separate connection |
| `emit()` never raises | Wrapped in `try/except Exception` with `[audit]` log prefix |
| alumni_db as source of truth | `get_alumni_profile_by_ref_id()` queries alumni_db; event_users not used for profile data |

---

## Out of Scope (not implemented)

Per Phase 2 constraints:

- Flutter diagnostics registration category (Phase 3)
- Production Flutter registration UI (Phase 3)
- Admin registration management UI
- Attendance, QR scan, waitlist, payment

---

## Next Steps (Phase 3)

1. Extend `dev_diagnostics.py` with registration category (5 tests)
2. Implement Flutter `_register()` in `event_detail_screen.dart`
3. Implement Flutter `developer_diagnostics_screen.dart` registration items
4. End-to-end smoke test with a real alumni account against a published event
