# Developer Diagnostics Cleanup Tool — Design Review

**Version:** 1.0  
**Date:** 2026-06-19  
**Status:** Design Review Only — NOT Approved for Implementation  
**Author:** Claude Code  
**Next Step:** Review and explicitly approve before any implementation begins

> **IMPORTANT:** This document is a design review only. No cleanup API, no delete button,
> no destructive operation, and no database migration has been created. Implementation
> requires explicit approval of this design, a dedicated prompt scoped to the approved
> changes, and a separate review cycle.

---

## Summary

This review covers the design considerations for a development-only cleanup tool within
the Developer Diagnostics screen. The tool would allow developers to reset test state
(registrations, test events) without direct database access during iterative testing.

**Key conclusion:** A cleanup tool can be built safely if it is tightly scoped, dev-only,
JWT-protected, audit-logged, and limited to soft operations (status changes) rather than
hard deletes for most targets.

---

## Why a Cleanup Tool Is Needed

During iterative Week 3 testing, developers frequently hit these blockers:

| Blocker | Current workaround |
|---|---|
| `already_registered` — need to re-test the registration flow | Manually run SQL: `UPDATE registrations SET status='cancelled'` |
| Too many test registrations — `registered_count` pollutes capacity tests | Manually run SQL to cancel or delete rows |
| Test events have stale state (wrong capacity, closed) | Manually update via admin API or direct SQL |
| Audit log has thousands of test entries — hard to find recent events | No cleanup — must filter by timestamp in SQL |
| `week3_manual_verification_guide_v2.md` assumes events 25, 26, 34, 35, 36 exist | Recreate manually via SQL if dropped |

Without a cleanup tool, developers context-switch to a SQL client during every test
cycle. This slows testing and increases the chance of accidentally modifying real data.

---

## Why a Cleanup Tool Is Dangerous

| Risk | Description |
|---|---|
| Accidental production data loss | If the tool is ever accessible in production/staging, test data may not exist — real registrations, real events, real users would be the targets |
| Cascade FK violations | Hard-deleting an event with registrations violates FK constraints and corrupts the database unless all child rows are deleted first |
| Alumni data exposure | `alumni_db` is a separate database — any cleanup operation must never touch it |
| Audit log corruption | Deleting audit records removes the evidence trail for security and compliance reviews |
| Race conditions | A cleanup during a concurrent test run can leave the database in a partially-reset state |
| Non-reversible bulk delete | A bulk delete of registrations by event ID cannot be undone without a database backup |

---

## Table-by-Table Safety Classification

| Table | Suggested Action | Rationale |
|---|---|---|
| `registrations` | Soft-cancel (`status = 'cancelled'`) test rows only | Preserves FK integrity; `registered_count` recalculates; re-registration is supported |
| `events` | Soft-cancel test events only (`status = 'cancelled'`) | No FK violation; event stays visible to admin for audit purposes |
| `event_audit_log` | Filter-delete by `entity_type = 'test'` or by time range — never bulk delete | Audit log is the evidence trail; bulk delete is never safe |
| `notifications` | Delete or soft-delete by linked `event_id` for test events only | Low risk if scoped to test events |
| `check_ins` | Future scope only — do not include in v1 | Not yet used |
| `event_members` / `event_content` | Cascade-safe delete only if the parent test event is also being removed | Only safe as part of event cleanup |
| `event_users` | Do not delete by default | `event_users` is the identity anchor — deleting here breaks auth |
| `alumni_db.alumni` | Never delete under any circumstances | Separate database; alumni records are source of truth |
| `sessions` | Cascade-safe delete only if parent test event is removed | Low risk if scoped |

---

## Recommended Allowed Targets

If the cleanup tool is built, these are the safe, approved targets:

| Operation | Target | Method | Notes |
|---|---|---|---|
| Cancel my test registration | `registrations WHERE firebase_uid = current_user AND status = 'registered'` | Soft-cancel: `SET status = 'cancelled'` | Mimics production cancellation flow |
| Cancel all my test registrations | `registrations WHERE firebase_uid = current_user` | Soft-cancel only | Scoped to current user — no blast radius |
| Cancel a specific test registration | `registrations WHERE registration_id = X AND firebase_uid = current_user` | Soft-cancel | Requires ownership check |
| Reset test event capacity | `events WHERE event_id = X` via existing PATCH status API | Use `PATCH /api/v1/events/{id}` with new capacity | Admin action, not a new delete endpoint |
| Soft-cancel a test event | `events WHERE event_id = X AND title LIKE 'Swagger%' OR 'Dev Test%'` | `SET status = 'cancelled'` | Should require name-prefix guard |

---

## Recommended Blocked Targets

These must never be available through the cleanup tool:

| Blocked Action | Reason |
|---|---|
| Hard-delete any registration row | Breaks audit trail; FK constraint risks |
| Delete any event row | Orphans registrations, sessions, audit log |
| Modify `event_users` rows | Identity anchor — no accidental deletion |
| Touch `alumni_db` in any way | Separate database; alumni data is production-critical |
| Bulk-delete all registrations for an event | Too wide — catches real user data in staging |
| Delete `event_audit_log` entries | Never — compliance and security records |
| Truncate any table | Never — blast radius is unlimited |
| Operations without `APP_ENV = "development"` check | Non-negotiable safety rule |

---

## Proposed API Design

All cleanup endpoints must follow these rules:

1. Backend route defined only when `APP_ENV = "development"` (else raise `404`)
2. Require valid backend JWT (`Depends(get_current_user)`)
3. Optionally require `user_type = "alumni"` or a dev admin flag
4. Accept only explicit, parameterised targets — no arbitrary SQL
5. Write an audit log entry for every cleanup action (even in dev mode)
6. Return a structured summary of what was changed

**Proposed endpoint:**

```text
POST /api/v1/dev/diagnostics/cleanup
Authorization: Bearer <backend_jwt>
```

**Request body:**

```json
{
  "target": "my_registrations",
  "scope": "all",
  "confirm": "DELETE_MY_TEST_REGISTRATIONS"
}
```

**`target` values (v1 — restricted set):**

| Target | Action | Scope |
|---|---|---|
| `my_registrations` | Soft-cancel all registrations for current user | `scope: "all"` or `scope: "event_id:<N>"` |
| `single_registration` | Soft-cancel one registration by ID (must be owned by current user) | `scope: "registration_id:<N>"` |

**`confirm` field:** A required string that must exactly match a predetermined phrase.
If wrong or missing, the request is rejected with `400`. This prevents accidental calls.

**Response:**

```json
{
  "status": "ok",
  "target": "my_registrations",
  "cancelled_count": 3,
  "audit_logged": true,
  "message": "3 registrations soft-cancelled for firebase_uid fxvOA6JInMM2OPKb3vuSV7qJwtI3"
}
```

---

## Proposed Flutter UI Design

Location: New entry in Developer Diagnostics **Registration** category:

```
Title: "Dev Cleanup Tool"
Description: "Reset test registrations for re-testing. Development only."
Icon: Icons.cleaning_services_outlined
```

Detail screen:

1. Warning banner (red): "DESTRUCTIVE ACTIONS — Development environment only"
2. Current user info (shows `firebase_uid` so user knows what will be targeted)
3. Section: "My Registrations"
   - Shows count of active registrations for current user
   - Button: "Cancel All My Registrations" → shows a confirmation dialog
   - Confirmation dialog: user must type the confirmation phrase or tap a confirm button
4. Result card: shows what was cancelled
5. NO buttons for events, audit log, or other users' registrations in v1

---

## Confirmation Rules

Every destructive action must have a two-step confirmation:

1. **Button tap** → opens confirmation dialog — never executes immediately on tap
2. **Confirmation step** (one of the following, not both):
   - Typed confirmation phrase (e.g., "RESET") shown in the dialog
   - An explicit "I understand this cannot be undone" checkbox + confirm button
3. **Server-side `confirm` field** in request body as final check

No cleanup action may execute without all three confirmations.

---

## Production Safety Rules

These are non-negotiable constraints:

1. Backend route raises `404` when `APP_ENV != "development"`
2. Flutter screen is inside `kDebugMode` guard — not compiled in release builds
3. No cleanup endpoint in the EventAdmin portal — only in Developer Diagnostics
4. No cleanup endpoint documented in public API docs — excluded from `backend_api_index_v2.md`
5. Cleanup endpoint is excluded from FastAPI's Swagger UI in production (achieved by the `APP_ENV` guard)
6. Every cleanup action writes to `event_audit_log` with `event_type = "dev_cleanup"` so the action is traceable
7. All operations are scoped to `firebase_uid = current_user.firebase_uid` — no cleanup can affect other users' data

---

## Rollback Strategy

Since soft-cancel is used (not hard-delete):

| Operation | Rollback method |
|---|---|
| Cancelled registration | `UPDATE registrations SET status='registered', cancelled_at=NULL WHERE registration_id=N` — via SQL or a future "restore" endpoint |
| Cancelled test event | `PATCH /api/v1/events/{id}/status` with `{"status": "published"}` — existing admin API |
| Accidental cancel of wrong registration | Restore from `event_audit_log` — the `entity_id` is the `registration_id` |

Because no rows are hard-deleted, all accidental actions are recoverable via SQL.

---

## Recommendation

### Should the cleanup tool be built?

**Yes, with strict scope.**

The frequency of test-state resets during development justifies building this tool.
Without it, developers spend significant time in SQL clients during each test cycle.

### Should implementation proceed now?

**No — not yet.**

Week 4 priorities are:
- Production Flutter registration UI
- Admin attendee management
- Beta readiness

The cleanup tool is a developer ergonomics feature, not a user-facing feature.
It should be scoped for a Week 4 or post-Week 4 implementation slot when the
registration flows are stable.

### Minimum scope for v1 implementation

If approved, the v1 implementation should be limited to:

1. `POST /api/v1/dev/diagnostics/cleanup` — backend endpoint, `my_registrations` target only
2. Flutter "Dev Cleanup Tool" diagnostic entry — soft-cancel my registrations only
3. Confirmation dialog with typed phrase
4. Audit log entry per cleanup action

Everything else (event cleanup, audit log cleanup, bulk operations) is deferred to v2.

---

## Implementation Should / Should Not Proceed

| Item | Status |
|---|---|
| Design review | Complete |
| Safety classification | Complete |
| Proposed API design | Complete |
| Proposed Flutter UI design | Complete |
| Confirmation rules documented | Complete |
| Production safety rules documented | Complete |
| Rollback strategy documented | Complete |
| **Implementation approval** | **Pending — not yet approved** |
| **Backend code change** | **Not started — do not start without approval** |
| **Flutter code change** | **Not started — do not start without approval** |
| **Database migration** | **Not required — soft-cancel uses existing schema** |
