# NITKSAA Event App — Week 3 Dependency Review

**Date:** 2026-06-18  
**Phase:** 0 — Pre-development review  
**Reviewer:** Claude Code (automated)  
**Sprint:** Week 3 — Registration, Confirmation Email, Protected Join Link

---

## 1. Auth Dependencies

### 1.1 Current JWT Auth (`middleware/auth.py`)

```python
async def get_current_user(credentials) -> Dict[str, Any]:
    payload = decode_access_token(credentials.credentials)
    user = await _fetch_event_user(payload["firebase_uid"])
    if user["is_suspended"]:
        raise HTTPException(status_code=403, detail="account_suspended")
    return {
        "firebase_uid": ...,
        "email": ...,
        "fullname": ...,
        "user_type": ...,     # "alumni" or "other"
        "ref_id": ...,        # alumni_id from alumni_db, or None
        "graduation_year": ...
    }
```

**Status for Week 3:** Ready. All Week 3 registration endpoints must use `get_current_user` from `middleware/auth.py` (not the dev_auth.py header approach used by admin routes).

**Alumni validation from current user:**

```python
if user["user_type"] != "alumni":
    raise HTTPException(status_code=403, detail="alumni_required")
if not user["ref_id"]:
    raise HTTPException(status_code=403, detail="alumni_required")
```

This is the first gate before any alumni_db fetch.

### 1.2 Dev Auth (`middleware/dev_auth.py`)

Admin event routes use `X-Dev-User: admin` header approach. This is development-only and correctly gated by `APP_ENV=development`.

**Week 3 action:** Registration APIs must use real JWT auth (`middleware/auth.py`), not dev_auth. Do not accidentally wire registration routes to dev_auth.

### 1.3 `/auth/firebase` Exchange

Currently works correctly:
1. Verifies Firebase ID token
2. Looks up alumni by email in alumni_db via `find_alumni_by_email()`
3. Upserts event_user with user_type and ref_id
4. Issues backend JWT

**One gap in upsert:** On conflict (existing user), only `email`, `fullname`, `last_login` are updated. `user_type` and `ref_id` are NOT updated. This means:

- If alumni_db lookup failed on first login (alumni returned as 'other'), they will remain 'other' on all subsequent logins even if alumni_db is now reachable.
- If `ref_id` was null on first login, it stays null even after alumni_db is corrected.

**Risk:** LOW but real. Could block alumni who first logged in during an alumni_db outage. Fix in Week 3 migration or upsert logic is recommended but not a blocker.

### 1.4 `/auth/me`

Returns current_user fields. Working in Week 2. No change needed.

---

## 2. Admin Dependencies

### 2.1 Event Admin Routes

`backend/app/api/events.py` uses `get_admin_user` from `middleware/dev_auth.py`.

**Week 3 registration routes:** Must use `get_current_user` from `middleware/auth.py`.

**Admin routes for Week 4** (attendee list, export): Will need a real admin auth dependency replacing `get_admin_user`. Not a Week 3 concern.

### 2.2 Admin Portal

No new admin portal screens in Week 3. The existing event list view shows `registered_count` once the backend computes it correctly (currently 0). That will naturally update once the events_service.py registered_count is fixed.

---

## 3. Event Serializers

### 3.1 Public Event Serializer

**Source:** `backend/app/repositories/events_repository.py`

```python
_PUBLIC_COLUMNS = """
    e.event_id, e.slug, e.title, e.tagline, e.description,
    e.status, e.start_datetime, e.end_datetime, e.timezone,
    e.location_text, e.location_maps_url, e.is_virtual,
    e.thumbnail_url, e.banner_url, e.capacity,
    e.show_attendee_list,
    e.registration_opens_at, e.registration_closes_at,
    e.published_at
"""
```

**Confirmed exclusions:**
- `virtual_url` — NOT included. CORRECT.
- `created_by_firebase_uid` — NOT included. CORRECT.
- `created_by_name` — NOT included. CORRECT.

**Week 3 action:** Add `registered_count` via subquery. This is the only change needed to the public event serializer.

### 3.2 Admin Event Serializer

**Source:** `backend/app/repositories/events_repository.py`, `_SELECT_WITH_CREATOR`

Includes all columns including `virtual_url` and `created_by_name`. Week 3 does not add new admin event endpoints.

### 3.3 registered_count Computation

Currently set to `0` as a hardcoded placeholder in `events_service.py`.

**Location:** `backend/app/services/events_service.py`, lines 44-48 and 50-55.

**Fix required:** Replace with live count from registrations table. Recommended approach:

```python
# In EventsService, add a private helper:
async def _get_registered_count(self, event_id: int) -> int:
    return await self.conn.fetchval(
        "SELECT COUNT(*) FROM registrations WHERE event_id = $1 AND status != 'cancelled'",
        event_id
    )
```

Or add to the SQL query as a subquery:

```sql
SELECT e.*, 
    COALESCE((
        SELECT COUNT(*) FROM registrations r
        WHERE r.event_id = e.event_id AND r.status != 'cancelled'
    ), 0) AS registered_count
FROM events e
```

### 3.4 registration_status Computation

**Source:** `backend/app/services/events_service.py`, `_compute_registration_status()`

```python
def _compute_registration_status(event: Dict[str, Any]) -> str:
    if event.get("status") != "published":
        return "not_applicable"
    now = datetime.now(timezone.utc)
    capacity = event.get("capacity")
    registered = event.get("registered_count", 0)
    if capacity is not None and registered >= capacity:
        return "full"
    opens_at = event.get("registration_opens_at")
    if opens_at and now < opens_at:
        return "not_open_yet"
    closes_at = event.get("registration_closes_at")
    if closes_at and now > closes_at:
        return "closed"
    return "open"
```

**Status:** Correct logic, but currently gets `registered_count=0` always, so `"full"` is never returned. Once registered_count is fixed, this will work correctly. No logic change needed.

---

## 4. alumni_db Access

### 4.1 Connection — Already Exists

`backend/app/database.py` already has:
```python
async def get_alumni_pool() -> asyncpg.Pool:
    ...
    _alumni_pool = await asyncpg.create_pool(dsn=settings.alumni_db_dsn, ...)
```

`backend/app/config.py` already has:
```python
alumni_db_name: str = Field("alumni_db", alias="ALUMNI_DB_NAME")
alumni_db_url: Optional[str] = Field(None, alias="ALUMNI_DB_URL")
```

**Status:** alumni_db connection infrastructure is already in place from Week 1.

### 4.2 Current `find_alumni_by_email()` — Insufficient for Week 3

**Source:** `backend/app/services/alumni_service.py`

```python
async def find_alumni_by_email(email: str) -> Optional[Dict[str, Any]]:
    pool = await get_alumni_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT alumni_id, fullname, graduationyear
            FROM alumni
            WHERE lower(email) = lower($1)
            LIMIT 1
            """,
            email,
        )
    return dict(row) if row else None
```

This function is used only during `/auth/firebase` login to determine user_type and ref_id. It is NOT suitable for Week 3's `/alumni/me` endpoint because:
- Fetches only 3 fields (alumni_id, fullname, graduationyear)
- Missing: branch, phone, registrationstatus, email
- No active alumni validation (registrationstatus check)

### 4.3 alumni_db Table Structure (from portal-v2 review)

**Table name:** `alumni`

**Columns available:**
| Column | Type | Notes |
|---|---|---|
| alumni_id | TEXT (PK) | This is the ref_id stored in event_users |
| fullname | TEXT | Alumni full name |
| graduationyear | INT | Maps to batch_year in API |
| branch | TEXT | Department |
| degree | TEXT | Not needed for Week 3 |
| currentlocation | TEXT | Not needed for Week 3 |
| registrationstatus | TEXT | Active status check |
| linkedin | TEXT | Not needed for Week 3 |
| firebase_uid | TEXT | Stored on first Firebase login |
| email | TEXT | Primary email |
| secondaryemail | TEXT | Not needed for Week 3 |
| phone | TEXT | Mobile phone |
| secondaryphone | TEXT | Not needed for Week 3 |
| gender | TEXT | Not needed for Week 3 |
| dateofbirth | DATE | Not needed for Week 3 |

### 4.4 Active Alumni Validation

From portal-v2 `auth_v1.py`:

Valid statuses for login: `Active`, `Self-Verified`, `Pending`
Blocked: `Blocked`, `Deceased`

For Week 3 registration, the recommended active check:

```python
ACTIVE_STATUSES = ('Active', 'Self-Verified')

def is_active_alumni(registrationstatus: str) -> bool:
    return registrationstatus in ACTIVE_STATUSES
```

`Pending` status: Alumni who self-registered but are not yet approved. Decision required: should Pending alumni be allowed to register for events?

**Recommendation:** Only `Active` and `Self-Verified` should be allowed for Week 3. `Pending` alumni have not been verified. This aligns with the concept of "active alumni" in the beta plan.

### 4.5 Identity Mapping for `/alumni/me`

**Preferred lookup for Week 3:**

```python
# Use ref_id from current JWT (this is alumni.alumni_id)
# Do NOT use email-based lookup for /alumni/me

SELECT alumni_id, fullname, email, phone, graduationyear, branch, registrationstatus
FROM alumni
WHERE alumni_id = $1
```

Using `current_user["ref_id"]` as the key is more reliable than email because:
- Email changes are possible (alumni updates secondary email)
- ref_id = alumni_id is set authoritatively at login time
- Avoids email case/whitespace edge cases

**Fallback:** If ref_id is null (non-alumni user slipped through), return 403 alumni_required.

### 4.6 New Week 3 alumni_service Functions Required

```python
async def get_alumni_by_ref_id(ref_id: str) -> Optional[Dict[str, Any]]:
    """Full profile fetch for /alumni/me — returns all Week 3 fields."""

async def validate_active_alumni(ref_id: str) -> Dict[str, Any]:
    """Fetch + validate active status. Raises 403 if inactive."""
```

These replace and extend the existing `find_alumni_by_email()` which is kept for auth/firebase use only.

### 4.7 fetch_alumni_info() Pattern

The architecture documents reference a `fetch_alumni_info()` pattern from portal-v2. In practice, the portal-v2 backend uses direct psycopg2 queries (synchronous) in its routers. The event app uses asyncpg (async). 

**Confirmed pattern for event app:**
- Use asyncpg pool via `get_alumni_pool()`
- Direct SQL queries (no ORM)
- This is already the pattern used in `find_alumni_by_email()`

**No portal-v2 code can be shared directly.** The event app must implement its own async alumni queries using the confirmed column names from portal-v2 models.py.

---

## 5. Email Service

### 5.1 Current State

**No email service exists in the event app.**

The portal-v2 has an email service (`services/email.py`) but it is synchronous (Flask-style) and uses a different provider setup. It cannot be directly reused.

### 5.2 Required Implementation

New module: `backend/app/services/email_service.py`

Required components:

```python
class EmailMessage:
    to_email: str
    to_name: str
    subject: str
    body_text: str
    body_html: Optional[str]

class EmailService:
    async def send(self, message: EmailMessage) -> EmailResult

class LogEmailProvider(EmailService):
    """Logs email to stdout/application log. Used when EMAIL_MODE=log."""

class SendGridEmailProvider(EmailService):
    """Sends via SendGrid API. Used when EMAIL_MODE=send."""
```

### 5.3 Configuration Gaps

The following environment variables are MISSING from `backend/app/config.py`:

| Variable | Purpose | Required |
|---|---|---|
| EMAIL_MODE | log or send | YES |
| EMAIL_PROVIDER | sendgrid | YES when mode=send |
| SENDGRID_API_KEY | SendGrid API key | YES when mode=send |
| EMAIL_FROM | From address | YES |
| EMAIL_REPLY_TO | Reply-to address | YES |
| APP_PUBLIC_BASE_URL | Base URL for links in emails | YES |

All must be added to `config.py` as optional fields with safe defaults:

```python
email_mode: str = Field("log", alias="EMAIL_MODE")
email_provider: str = Field("sendgrid", alias="EMAIL_PROVIDER")
sendgrid_api_key: Optional[str] = Field(None, alias="SENDGRID_API_KEY")
email_from: str = Field("noreply@nitksaa.com", alias="EMAIL_FROM")
email_reply_to: Optional[str] = Field(None, alias="EMAIL_REPLY_TO")
app_public_base_url: str = Field("http://localhost:8000", alias="APP_PUBLIC_BASE_URL")
```

### 5.4 Email Content — Week 3

Minimum required content for registration confirmation email:

- Subject: "NITKSAA Event Registration Confirmed — {event_title}"
- Greeting: "Dear {fullname_snapshot}"
- Registration number: `{registration_number}`
- Event: title, date/time, timezone
- Physical event: venue/map link
- Virtual event: join instruction (decide whether to include join_url in email — requires NITKSAA approval)
- Reply-to / contact information

### 5.5 Join URL in Email — Decision Needed

The Week 3 architecture review says:

> "For Week 3 staging demo, join link may be included in confirmation email only if NITKSAA approves. If not approved, email should say 'Join link is available inside the app after login.'"

This decision must be made before email service implementation. Default for Week 3: do NOT include join_url in email. Only include it if explicitly approved.

### 5.6 Email Failure Policy

Registration must succeed even if email fails:
1. Insert registration row — commit transaction
2. Attempt email send
3. Update `confirmation_email_status` and related fields
4. Return registration response with email status included

Never roll back a committed registration due to email failure.

---

## 6. Virtual URL Visibility

### 6.1 Current State

Public APIs correctly hide `virtual_url`:

- `events_repository.py` `_PUBLIC_COLUMNS` does not include `virtual_url`
- Week 2 diagnostics verified: no `virtual_url` in public responses
- Week 2 end-to-end report confirmed: virtual_url present: false in public Webinar Demo

### 6.2 Week 3 Requirement

`join_url` (the user-facing alias for `virtual_url`) may only be returned from:

```
GET /api/v1/events/{event_id}/my-registration
GET /api/v1/my/registrations
```

And only when:
```
event.is_virtual == true
registration.status == 'registered'
event.status == 'published'
```

### 6.3 Implementation Rule

In the registration service's join-link reveal:

```python
join_url = None
if event["is_virtual"] and registration["status"] == "registered":
    join_url = event["virtual_url"]
```

The response always uses the field name `join_url`, never `virtual_url`.

---

## 7. Developer Diagnostics

### 7.1 Current State

**Source:** `backend/app/api/dev_diagnostics.py`

Existing diagnostics:
- `GET /api/v1/dev/diagnostics/auth/me` — auth check
- `GET /api/v1/dev/diagnostics/db/tables` — table listing
- `GET /api/v1/dev/diagnostics/db/{table_name}` — table contents
- `GET /api/v1/dev/diagnostics/events` — event management test suite

Auth: JWT-based via `decode_access_token` — same as `get_current_user`. Correct.

Environment guard: `_require_development()` raises 404 in non-development. Correct.

### 7.2 Week 3 Requirements

New endpoints required:
- `GET /api/v1/dev/diagnostics/registrations` — registration diagnostics metadata
- `POST /api/v1/dev/diagnostics/registrations/run` — run specific scenario

### 7.3 Diagnostics Pattern

The existing `_diag_entry()` pattern in dev_diagnostics.py is the correct pattern to follow for new registration diagnostics. Use the same structure:

```python
{
    "feature": str,
    "api": str,
    "method": str,
    "auth_required": bool,
    "request": dict,
    "response": dict,
    "status": "PASS" | "FAIL",
    "duration_ms": int,
    "timestamp": str,
    "error": str | None
}
```

### 7.4 Registration Diagnostics File

New file: `backend/app/api/dev_diagnostics_registrations.py`

Or extend existing `dev_diagnostics.py` with registration-specific endpoints using the existing pattern. The architecture document recommends a separate file.

### 7.5 Flutter Developer Diagnostics

A "Registration Flow" section must be added to the existing Flutter Developer Diagnostics screen. This is not a production screen — it lives inside the existing debug-mode diagnostics UI.

Panels:
1. Alumni Profile Autofill (GET /alumni/me result)
2. Event Eligibility (GET /events/{id}/registration-eligibility result)
3. Register for Event (POST /events/{id}/register interactive)
4. Confirmation Screen Preview (show registration_number, email status)
5. Email Result (sent/failed/log)
6. My Registration Detail (GET /events/{id}/my-registration result)
7. Join Link Reveal (virtual event registered state)
8. Negative states: duplicate, full, closed, non-alumni

---

## 8. nitksaa-portal-v2 Integration Summary

| Question | Answer |
|---|---|
| Alumni table name | `alumni` |
| Alumni primary key | `alumni_id` (TEXT) |
| Firebase UID stored? | YES, in `alumni.firebase_uid` — set on first portal login |
| Lookup method for Week 3 | By `alumni_id` using `event_users.ref_id` as the key |
| Fallback lookup | By email (existing `find_alumni_by_email`) — kept for auth/firebase only |
| Active status field | `registrationstatus` |
| Active values for registration | `Active`, `Self-Verified` |
| Batch year field | `graduationyear` (maps to `batch_year` in API) |
| Branch field | `branch` |
| Phone field | `phone` (nullable) |
| Email field | `email` (primary) |
| Connection type | asyncpg (event app) — portal uses psycopg2 (synchronous) |
| Code sharing possible? | No — different async frameworks |
| fetch_alumni_info() pattern | Implement as new async function in alumni_service.py |

---

## 9. nitksaa-website Integration Summary

Not required for Week 3 core registration.

Optional touchpoints (review only if time allows):
- Email branding/domain: NITKSAA website uses nitksaa.com domain — email FROM should match
- Public event URL format: website may consume event APIs in future — URL structure already stable

No website code changes in Week 3.

---

## 10. Complete Dependency Map for Week 3

```
Week 3 Registration Flow Dependencies

Firebase Auth
  └── POST /auth/firebase [EXISTS]
        └── find_alumni_by_email() [EXISTS, kept for login only]

Backend JWT Auth
  └── get_current_user() [EXISTS in middleware/auth.py]
        └── event_users table [EXISTS]

GET /alumni/me [NEW]
  └── get_current_user()
  └── get_alumni_by_ref_id() [NEW function in alumni_service.py]
        └── alumni_db.alumni table via get_alumni_pool() [EXISTS]

POST /events/{id}/register [NEW — full rewrite]
  └── get_current_user()
  └── validate_active_alumni() [NEW]
        └── alumni_db
  └── RegistrationService.register_for_event() [NEW — full rewrite]
        └── EventsRepository.get_public_event() [EXISTS]
        └── RegistrationRepository.create() [NEW — rewrite]
              └── registrations table [EXISTS, needs migration 008]
        └── EmailService.send() [NEW]
              └── LogEmailProvider [NEW] or SendGridEmailProvider [NEW]

GET /events/{id}/my-registration [NEW]
  └── get_current_user()
  └── RegistrationService.get_my_event_registration() [NEW]
        └── registrations table
        └── events table (for virtual_url reveal)

GET /my/registrations [NEW]
  └── get_current_user()
  └── RegistrationService.list_my_registrations() [NEW]

GET /events/{id}/registration-eligibility [NEW, optional]
  └── get_current_user()
  └── RegistrationService.get_registration_eligibility() [NEW]

GET /dev/diagnostics/registrations [NEW]
  └── decode_access_token() [EXISTS]
  └── _require_development() [EXISTS pattern]

POST /dev/diagnostics/registrations/run [NEW]
  └── same as above
```

---

## 11. Recommended Implementation Order

Based on this dependency review:

| Order | Task | Reason |
|---|---|---|
| 1 | Write migration 008 | Schema must be correct before any service code can work |
| 2 | Update config.py | Add email settings |
| 3 | Rewrite alumni_service.py | Add get_alumni_by_ref_id(), validate_active_alumni() |
| 4 | Update events_service.py | Add real registered_count computation |
| 5 | Write email_service.py | Required by registration service |
| 6 | Write registration_repository.py (new) | New schema-aligned repository |
| 7 | Write registration_service.py (new) | Depends on 3+4+5+6 |
| 8 | Write backend/app/api/alumni.py | GET /alumni/me |
| 9 | Write backend/app/api/registrations.py | All registration endpoints |
| 10 | Write dev_diagnostics_registrations.py | Depends on 8+9 |
| 11 | Flutter: add Registration Flow diagnostics | Depends on 10 |

---

## 12. Risk Summary

| Risk | Severity | Description |
|---|---|---|
| Dual schema conflict | CRITICAL | Old alpha registration service/repo code references wrong column names. Full rewrite required. Do not patch. |
| Migration 008 required | HIGH | Registrations table missing ~12 columns for Week 3 |
| UNIQUE constraint blocks reactivation | HIGH | Hard UNIQUE(event_id, firebase_uid) must be replaced with partial index |
| registered_count hardcoded 0 | HIGH | Event eligibility logic always sees capacity as not-full until fixed |
| Email service missing | HIGH | Full implementation required |
| alumni_service incomplete | HIGH | Only returns 3 fields, no active validation |
| upsert_event_user doesn't update user_type | MEDIUM | Edge case: alumni who first logged in as 'other' stay blocked |
| race condition on capacity | MEDIUM | Concurrent last-seat registrations need row-level lock |
| join_url in email decision | MEDIUM | Awaiting NITKSAA approval before email template is finalized |
| graduation_year naming | LOW | Must map graduationyear → batch_year in all API responses |
| Pending alumni status decision | LOW | Should Pending alumni be allowed to register? Default: NO |
