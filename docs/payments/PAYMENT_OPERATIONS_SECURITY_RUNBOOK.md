# Payment Operations & Security Runbook
### `nitksaa-event` backend — Phase 0 sandbox payment domain

This document is written to be usable without reading the implementation
code. Where a capability does not exist yet, that is stated explicitly
rather than implied. It reflects the state of the backend after two
sprints: **Payment Production Foundation** (config lifecycle, RBAC
primitives, webhook freshness, expiry services) and **Payment Operational
Readiness** (admin RBAC unification, scheduler, this document).

---

## A. Architecture and Ownership

```
Attendee (Flutter / any HTTP client)
    |
    v
Attendee APIs                     app/api/payments.py
  pricing, orders, attempts,      (Firebase-JWT identity, ownership-checked)
  timeline, verify, webhook
    |
    v
Payment services                  app/services/payment_service.py
  pricing, orders, webhooks,      app/services/pricing_service.py
  timelines, verification         app/services/payment_config_service.py
                                   app/services/payment_lifecycle_service.py
    |
    v
Deterministic sandbox gateway     app/gateways/deterministic_sandbox.py
  (no real money; signed,         Phase 0 only — no real gateway integrated
   timestamped webhook payloads)
    |
    v
PostgreSQL (events_db)            payment_configurations, payment_orders,
                                   payment_attempts, payment_webhook_events,
                                   payment_exceptions, payment_platform_roles,
                                   event_members, event_audit_log
```

```
Platform/event operator
    |
    v
Production Admin APIs             app/api/admin_payments.py   (config, roles, expiry triggers)
  Firebase-JWT + RBAC             app/api/admin_events.py     (event CRUD, attendees, check-ins)
  app/middleware/admin_auth.py    app/api/events.py           (admin routes only — public routes below)
                                   app/api/people.py           (event people CRUD)
                                   app/api/sponsors_partners.py (event sponsors/partners CRUD)
    |
    v
Same services/DB as above, plus   app/repositories/payment_role_repository.py
event_members / payment_platform_roles

Public/unauthenticated APIs       app/api/events.py           (GET /events/public, /events/public/{id})
  No auth at all, by design       — published events only; no admin fields, no PII

Developer Diagnostics             app/api/dev_diagnostics.py
  APP_ENV=development ONLY        (config import shortcut, technical timeline,
  app/middleware/dev_auth.py      exceptions list, pending-attempt resolve,
  (X-Dev-User header)             full scenario runner)
  NEVER production-reachable

Scheduled/automated operations    scripts/run_payment_lifecycle_sweep.py
  no HTTP, no token — in-process  -> app/services/payment_lifecycle_service.py
  call to the lifecycle service      (same functions the manual HTTP
                                       endpoints call — no duplicated logic)
```

**Ownership boundaries — what each surface is, and is not, for:**

| Surface | Identity | Use for | Never use for |
|---|---|---|---|
| Attendee APIs | Real Firebase JWT, ownership-checked | Attendee's own payment flow | Admin actions, other users' data |
| Production Admin APIs | Real Firebase JWT + RBAC (`admin_auth.py`) | Config publish, role grants, event/people/sponsor/partner management, manual expiry recovery | Anything not backed by a verified role |
| Public event APIs | None (by design) | Published-event discovery only (`events.py`'s `/events/public*` routes) | Anything mutating state, anything returning unpublished events or admin-only fields |
| Developer Diagnostics | Dev-only header, `APP_ENV=development` gated | Local dev/demo/scenario testing | Anything in a deployed, non-development environment — the gate 404s automatically outside `development`, but never rely on that alone; never point a real gateway or real users at it |
| Scheduled sweep script | None (in-process, no network hop) | Automated periodic expiry | Anything requiring attendee-specific authorization — it only ever calls the two lifecycle functions, nothing else |

---

## B. Environment Configuration

None of the values below are secrets except where marked. Never paste
actual secret values into this document, tickets, chat, or logs.

| Setting | Required? | Default | Secret? | Production expectation |
|---|---|---|---|---|
| `APP_ENV` | required | `development` | no | Must be set to a non-`development` value in any real deployment — this is what gates `dev_auth`/`dev_diagnostics` closed |
| `SECRET_KEY` | required | dev placeholder | **yes** | Real random value in production; signs the internal access token issued after Firebase verification |
| `FIREBASE_PROJECT_ID` | required | placeholder | no | Real Firebase project ID |
| `EVENTS_DB_URL` | required | local default | **yes** (contains credentials) | Real managed Postgres connection string |
| `ALUMNI_DB_URL` | required | local default | **yes** | Real managed Postgres connection string |
| `PAYMENT_GATEWAY_MODE` | required | `deterministic_sandbox` | no | Stays `deterministic_sandbox` until a real gateway is integrated (not yet built) |
| `PAYMENT_SANDBOX_SIGNING_SECRET` | required | dev placeholder | **yes** | Real random secret; HMAC-signs every sandbox webhook payload |
| `PAYMENT_WEBHOOK_MAX_AGE_SECONDS` | optional | `300` | no | How stale a webhook `issued_at` may be before rejection |
| `PAYMENT_WEBHOOK_MAX_FUTURE_SKEW_SECONDS` | optional | `30` | no | How far in the future a webhook `issued_at` may be before rejection |
| `PAYMENT_DIAGNOSTICS_ENABLED` | optional | `true` | no | Independent kill switch for `/dev/diagnostics/payments/*`, on top of the `APP_ENV` gate — set `false` to disable diagnostics without touching `APP_ENV` |
| `PLATFORM_ADMIN_FIREBASE_UIDS` | optional | empty | no (contains UIDs, not secrets, but treat as sensitive config) | Comma-separated Firebase UIDs — see section C |

---

## C. First Platform-Admin Bootstrap

`PLATFORM_ADMIN_FIREBASE_UIDS` is the **only** mechanism that establishes
the first `platform_admin`. There is no seeded database row and no
break-glass API — this is deliberate: nothing else in this backend can
grant that role until at least one identity is trusted via this setting.

**Procedure:**
1. Identify the Firebase UID of the person(s) who should be the initial
   platform_admin(s).
2. Set `PLATFORM_ADMIN_FIREBASE_UIDS` in the deployment's environment
   configuration (comma-separated for more than one).
3. That identity is treated as `platform_admin` on every request from that
   point forward — no separate "activation" step.
4. **Verify**: have that identity call `GET /api/v1/admin/payment-roles`
   (should succeed) and confirm a plain attendee identity still gets 403
   on the same route.
5. **Transition to DB-backed grants**: once at least one real
   `platform_admin` exists, use `POST /api/v1/admin/payment-roles` to
   grant roles to others going forward — do not keep adding people to the
   env-var list as the primary mechanism; it has no audit trail (env
   changes aren't logged by this application) and no revoke endpoint. The
   DB-backed grants (`payment_platform_roles`) are attributable and
   revocable; the bootstrap list is not.
6. **Removal from bootstrap**: an identity can be removed from
   `PLATFORM_ADMIN_FIREBASE_UIDS` once they hold an equivalent DB-backed
   grant (or once they should no longer have platform_admin at all) — but
   removing everyone from the list with zero DB-backed platform_admin
   grants in place will make role administration unreachable again, so
   verify a working DB-backed platform_admin exists before doing this.

**No unsupported break-glass behavior exists.** If every bootstrap UID and
every DB-backed platform_admin grant is lost/misconfigured simultaneously,
the only recovery path is redeploying with an updated
`PLATFORM_ADMIN_FIREBASE_UIDS` value — there is no secondary recovery
mechanism, and this document does not claim one.

---

## D. Role Operations

All via `app/api/admin_payments.py`, `platform_admin`-only unless noted.

| Operation | Call |
|---|---|
| Grant a platform role | `POST /api/v1/admin/payment-roles` `{firebase_uid, role}` — role ∈ `platform_admin`, `finance_operator`, `auditor`, `support` |
| List active platform roles | `GET /api/v1/admin/payment-roles` (platform_admin or auditor) |
| Revoke a platform role | `POST /api/v1/admin/payment-roles/{grant_id}/revoke` |
| Grant event_admin for one event | `POST /api/v1/admin/events/{event_id}/payment-admins` `{firebase_uid}` |

**Verification after grant/revoke**: re-fetch `GET /api/v1/admin/payment-roles`
and confirm the expected state; have the affected identity attempt an
action their new/former role should/shouldn't allow.

**Audit evidence**: every grant/revoke emits an `event_audit_log` row
(`payment_role_granted`, `payment_role_revoked`, `event_payment_admin_granted`)
with `actor_uid` = the verified caller who performed it — see section J.

**Least-privilege guidance**: grant the narrowest role that satisfies the
need — `auditor` for read-only visibility (including seeing the role list
itself), `support`/`finance_operator` for their respective read-only
payment-operational scopes, `event_admin` for a single event's management,
`platform_admin` only when platform-wide write access is genuinely
required. `finance_operator`/`auditor`/`support` never gain event-CRUD
powers (`admin_events.py`) and `event_admin` never gains payment-role-grant
powers — these are enforced in code, not just convention.

---

## E. Payment Configuration Operations

```
create draft  ->  validate (optional dry-run)  ->  publish  ->  published
                                                        |
                                            (create a new draft, same key)
                                                        v
                                                 publish again
                                                        |
                                     previous published row -> retired
```

- **Create draft**: `POST /api/v1/admin/events/{event_id}/payment-configurations`
  — requires `platform_admin` or `event_admin` for that event.
- **Validate**: `POST .../{configuration_id}/validate` — dry run, no state
  change, returns pass/fail + reasons.
- **Publish**: `POST .../{configuration_id}/publish` — retires the
  event's previous published row (if any) and publishes this draft, in one
  transaction. Also mirrors `base_amount` onto `events.ticket_price` and
  flips `events.is_free = false`.
- **History**: `GET /api/v1/admin/events/{event_id}/payment-configurations`
  — every version, all statuses (`draft`/`published`/`retired`).

**Rollback/recovery guidance — read carefully**: a published configuration
**cannot be edited in place**, by design — this is a financial-integrity
property, not a missing feature. If a published configuration is wrong,
the recovery path is: create a new draft with corrected values, publish
it (this retires the wrong one). Any `payment_orders` row already priced
against the wrong version keeps that pricing permanently (its
`pricing_snapshot`, `configuration_id`, `configuration_version` never
change) — this is intentional so a customer's charged amount never shifts
underneath them. There is no "undo publish" and no way to make an already
-priced order retroactively use a newer configuration.

---

## F. Expiry Operations

**Mechanism**: `scripts/run_payment_lifecycle_sweep.py`, invoked in-process
(no HTTP, no token) — calls `payment_lifecycle_service.
expire_stale_payment_orders()` and `expire_stale_registration_holds()`
directly. **No scheduler is wired up in this repository as of this
sprint** — none exists to hook into (no Dockerfile, CI/CD workflow, cron,
or cloud scheduler config found anywhere in the repo). Wiring one is a
deployment-platform decision left to ops; example invocations:

```bash
# cron (crontab -e), from the backend/ directory with the venv active:
*/5 * * * * cd /path/to/backend && .venv/bin/python scripts/run_payment_lifecycle_sweep.py >> /var/log/nitksaa/payment_sweep.log 2>&1

# systemd timer: a oneshot service unit running the same command, triggered
# by a companion .timer unit with OnCalendar=*:0/5

# Any CI-based "scheduled workflow" (e.g. GitHub Actions cron trigger) that
# can reach the database and run the backend's Python environment
```

**Cadence**: recommended **every 5 minutes** as the pilot default —
derived from this codebase's `seat_hold_minutes`/
`payment_session_expiry_minutes` defaulting to 15 minutes each, so nothing
sits stale for more than one sweep interval before being caught. Adjust to
your actual configured hold/session durations if they differ; there is no
enforced coupling between the two, so misconfiguring the cadence relative
to your actual durations doesn't break anything, it just changes how
promptly stale state is cleaned up.

**Verifying successful execution**: the script prints one JSON line to
stdout per run and exits 0 only if both sweeps succeeded:
```json
{"run_id": "...", "started_at": "...", "finished_at": "...", "duration_ms": 12.3,
 "orders_status": "ok", "orders_expired_count": 2, "orders_error": null,
 "holds_status": "ok", "holds_expired_count": 0, "holds_error": null,
 "success": true, "wall_clock_ms": 45.1}
```
Whatever wraps the script (cron, systemd, CI) should alert on non-zero
exit code. The two sweeps are isolated — a failure in one (`orders_status:
"error"`) does not prevent the other from running or reporting its own
result.

**Manual invocation**: run the script directly at any time —
`.venv/bin/python scripts/run_payment_lifecycle_sweep.py` from `backend/`.
Safe to run ad hoc; it is idempotent (see below).

**Idempotent rerun**: running the sweep (script or the manual HTTP
endpoints below) again immediately afterward always reports
`expired_count: 0` for anything already processed — nothing is
double-expired, and nothing is double-audited (verified directly,
`test_payment_scheduler.py::test_script_rerun_is_idempotent`).

**What's protected**: orders with a payment attempt still in flight
(`initiated`/`pending`/`requires_verification`), already-`paid` orders,
and already-`registered` (confirmed) registrations are never touched by
either sweep — verified directly, including by forcing a past
`expires_at`/`hold_expires_at` onto protected rows and confirming the
sweep still skips them.

**Manual recovery**: if the automated sweep is not running (misconfigured
scheduler, ops hasn't wired one up yet, etc.), a `platform_admin` can
trigger the same underlying logic manually via
`POST /api/v1/admin/payments/lifecycle/expire-orders` and
`POST /api/v1/admin/payments/lifecycle/expire-registration-holds` — these
call the identical service functions the script does.

**If the scheduled job fails**: check the script's JSON output /
`orders_error`/`holds_error` fields first (never logs secrets — see
section I). If the failure is transient (DB connectivity), the next
scheduled run will simply pick up whatever became eligible in the
meantime — nothing is lost by a missed run, since eligibility is a live
DB query each time, not a queue. If the failure is persistent, use the
manual HTTP endpoints as a stopgap while diagnosing.

---

## G. Webhook Security Incidents

All webhook events are recorded in `payment_webhook_events`
(`gateway`, `gateway_event_id`, `signature_valid`, `processing_status`,
`error_code`, `received_at`) before any decision is made — this table is
the first place to look for any of the following.

| Symptom | What it means | What to check |
|---|---|---|
| Invalid-signature spike | Either a misconfigured/rotated `PAYMENT_SANDBOX_SIGNING_SECRET` mismatch between sender and this backend, or genuine forged traffic | `payment_webhook_events` rows with `signature_valid = false`; confirm the configured secret matches what the sandbox/gateway is actually signing with |
| Stale webhook spike | Clock skew on the sending side, a slow/retrying delivery queue, or `PAYMENT_WEBHOOK_MAX_AGE_SECONDS` set too tight for real network conditions | `error_code = 'timestamp_stale'` rows; compare `issued_at` (in the payload) against `received_at` |
| Future-timestamp errors | Clock skew (sender's clock ahead of this server), or a forged/replayed payload with a manipulated timestamp | `error_code = 'timestamp_future_skew'` rows |
| Duplicate/replay spike | Normal at some baseline (retry-happy senders); a spike specifically correlated with a single `gateway_order_ref` may indicate a captured-and-replayed payload being resent — but replay is a no-op by design (verified: `test_replay_attack_after_successful_capture_no_effect`, `test_old_duplicate_replay_causes_zero_additional_mutation`) | `processing_status = 'duplicate'` rows; confirm `payment_orders.amount_paid` for the affected order is unchanged |
| Money deducted but status pending | An attempt sat in `pending`/`requires_verification` past `PENDING_VERIFICATION_WINDOW_MINUTES` (30 min, Phase 0 constant in `payment_service.py`) | `payment_attempts.status`, `verification_check_count`; the attendee-facing `POST /payment-attempts/{id}/verify` re-checks and escalates automatically — do not manually flip status in the DB |
| Payment captured after seat expiry | The `PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY` exception exists exactly for this — funds are preserved (order marked `paid`), registration is deliberately NOT auto-confirmed | `GET /api/v1/dev/diagnostics/payments/exceptions` (dev-only currently — see section H) or query `payment_exceptions` directly; this requires a human decision (confirm the registration, or arrange a refund once refunds exist — neither is automatable today) |
| `requires_verification` cases | An attempt has been `pending` for more than the verification window with no resolving webhook | Same exceptions list; in Phase 0 sandbox, `POST /api/v1/dev/diagnostics/payments/attempts/{id}/resolve` can force a terminal outcome for **demo/dev only** — there is no production-safe equivalent yet (see Known Limitations) |

**What operators must NOT do**: never manually `UPDATE` `payment_orders.status`,
`payment_orders.amount_paid`, or `payment_attempts.status` directly in the
database to "fix" a stuck state. Every legitimate state transition in this
system goes through a webhook (real or, in dev, the sandbox-resolve
diagnostic) so that the audit trail, idempotency guarantees, and
registration-confirmation side effects stay consistent. A direct DB write
bypasses all of that silently.

---

## H. Payment Exceptions

**Honest current state**: exceptions (`PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY`,
`VERIFICATION_UNRESOLVED`) are **read-only** from any admin-facing surface
today. `GET /api/v1/dev/diagnostics/payments/exceptions` lists them, but
this route is development-only (`APP_ENV=development` gated) — there is
**no production-reachable way to list or resolve exceptions yet**, and no
`resolved_by`/`resolution` write path exists anywhere despite those
columns existing on `payment_exceptions`. This was already true after the
Payment Production Foundation sprint and remains true after this one — it
is explicitly **future scope**, not something this runbook can walk you
through operating today. If a `PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY`
exception needs resolving in production right now, that is a manual,
case-by-case decision made by whoever has direct database access, outside
any tooling this backend currently provides — document the decision
somewhere durable (a ticket, not just a DB update) since the application
itself won't record the resolution.

---

## I. Secret Handling and Rotation

**Principles** (this backend does not use a secret manager yet — secrets
live in environment configuration):
- `PAYMENT_SANDBOX_SIGNING_SECRET`, `SECRET_KEY`, `EVENTS_DB_URL`/
  `ALUMNI_DB_URL` (credentials embedded in the connection string) are the
  current secrets. None are logged anywhere in this codebase — verified
  directly for the new scheduler script
  (`test_payment_scheduler.py::test_script_output_contains_no_secrets`)
  and for the payment API surface
  (`test_payments.py::test_no_secret_leakage_in_responses`).
- **Rotating `PAYMENT_SANDBOX_SIGNING_SECRET`**: any webhook signed with
  the old secret and delivered after rotation will be rejected as
  `invalid_signature` — this is correct, not a bug. Coordinate rotation
  with whatever is sending sandbox webhooks (the deterministic sandbox
  itself signs and verifies with the same in-process secret, so this
  mainly matters if/when a real external gateway is integrated and needs
  to be told about the new secret in lockstep).
- **Rotating `SECRET_KEY`**: invalidates every currently-issued internal
  access token immediately (all logged-in sessions, attendee and admin
  alike) — plan for a coordinated re-login, not a live rotation.
  `PLATFORM_ADMIN_FIREBASE_UIDS`-based bootstrap access is unaffected
  (that check doesn't depend on `SECRET_KEY`), only the JWT signature
  itself.
- **Future real-gateway secrets** (API keys, webhook signing keys for a
  real payment gateway): not yet integrated, so no rotation procedure
  exists for them yet. When that integration happens, it should get its
  own documented rotation procedure here — do not assume the sandbox
  secret's handling generalizes without re-verification, since a real
  gateway's signature/rotation semantics may differ.
- Never print, paste, or commit an actual secret value anywhere — not in
  this document, not in a ticket, not in a Slack message, not in a log
  line.

---

## J. Audit and Evidence

| What | Where |
|---|---|
| Attendee-facing payment timeline (filtered, friendly labels) | `GET /api/v1/payment-orders/{order_id}/timeline` |
| Full technical/developer timeline (unfiltered) | `GET /api/v1/dev/diagnostics/payments/orders/{order_id}/technical-timeline` — dev-only |
| Raw webhook delivery records | `payment_webhook_events` table |
| General event audit log (registrations, payments, admin actions, role grants) | `event_audit_log` table — `entity_type`/`entity_id`/`event_type`/`context`/`actor_uid`/`created_at` |
| Payment configuration version history | `GET /api/v1/admin/events/{event_id}/payment-configurations` |
| Role grant/revoke history | `GET /api/v1/admin/payment-roles` (active only) or query `payment_platform_roles` directly for revoked history too (revoked rows are kept, not deleted) |
| Scheduler execution evidence | The sweep script's stdout JSON line per run (whatever your cron/systemd/CI wrapper captures as logs) plus one `payment_order_expired`/`registration_hold_expired` audit row per affected record in `event_audit_log` |
| Admin event-management mutations (create/update/publish/close event, create session) | `event_audit_log`, `event_type` prefixed `admin_event_*`/`admin_session_*` (added this sprint — these previously had no audit coverage at all) |

---

## K. Troubleshooting Matrix

| Symptom | Likely Layer | Checks | Safe Action | Escalate When |
|---|---|---|---|---|
| Payment initiation failure (order/attempt creation 4xx) | API/service validation | Response `detail` field (e.g. `payment_not_configured`, `seat_hold_expired`, `payment_order_expired`) | None — these are correct rejections, tell the attendee the specific reason | Same error at high volume for a published, correctly-configured event |
| Payment stuck pending | Gateway delivery / verification window | `payment_attempts.status`, `verification_check_count`, `verification_checked_at` | Have the attendee call `POST /payment-attempts/{id}/verify` (safe to re-call) | Past `PENDING_VERIFICATION_WINDOW_MINUTES` (30 min) with no resolution and a `VERIFICATION_UNRESOLVED` exception open |
| Retry blocked (`payment_attempt_active` / `payment_verification_in_progress`) | Business rule — by design | An unresolved attempt already exists for the order | None — this is the intended one-attempt-in-flight guarantee | Only if the "unresolved" attempt is itself stuck (see above) |
| Stale seat hold | Lazy/scheduled expiry | `registrations.hold_expires_at` vs now | Run the manual expiry-holds endpoint/script if the scheduler isn't wired up yet | Holds routinely going stale well past the sweep cadence — scheduler likely not actually running |
| Stale order (past `expires_at`, still `created`/`payment_pending`) | Same as above, order side | `payment_orders.expires_at`, `status` | Run the manual expire-orders endpoint/script | Same as above |
| Webhook rejection | Signature/timestamp/amount/currency validation | `payment_webhook_events.error_code` | See section G | Sustained spike in any one `error_code` |
| Registration/payment status mismatch (e.g. paid but not registered) | `PAYMENT_CAPTURED_AFTER_SEAT_EXPIRY` | `payment_exceptions` (dev-diagnostics list, or direct query) | Do not manually fix in the DB | Any occurrence — this always needs a human decision (section H) |
| Unauthorized admin (401/403 on an admin route) | RBAC | Confirm the caller has an active `platform_admin` bootstrap entry or DB grant, or an active `event_admin` membership for that specific event | Grant the correct role if legitimately needed (section D) | Repeated 403s from an identity that should have access — check for a revoked grant first |
| Scheduler failure | `run_payment_lifecycle_sweep.py` exit code / `*_error` fields | Script stdout JSON, `orders_error`/`holds_error` | Re-run manually; use the manual HTTP endpoints as a stopgap | Persistent failure across multiple scheduled runs |
| Payment exception (general) | `payment_exceptions` table | `exception_type`, `summary`, `detail` | Read-only inspection only (section H) | Always — no automated resolution exists |

---

## L. Incident Response

Severity guidance — none of this implies capabilities beyond what section
I/section D describe as actually available.

- **Suspected admin-account compromise** (a `platform_admin` or
  `event_admin` credential/identity may be compromised): revoke the
  affected platform role immediately via
  `POST /api/v1/admin/payment-roles/{grant_id}/revoke`; for a compromised
  `event_admin`, there is currently no dedicated revoke endpoint — flip
  the `event_members` row's `status` to `inactive` directly (the same
  direct-DB action `test_admin_rbac.py::test_revoked_event_admin_loses_access`
  exercises) and treat building a proper revoke endpoint as a fast-follow.
  If the identity is also in `PLATFORM_ADMIN_FIREBASE_UIDS`, that requires
  a config change and redeploy — it cannot be revoked live.
- **Suspected webhook-secret compromise**: rotate
  `PAYMENT_SANDBOX_SIGNING_SECRET` immediately (accepting that in-flight
  legitimate deliveries signed with the old secret will be rejected —
  acceptable in the Phase 0 sandbox since nothing is real money yet).
  Audit `payment_webhook_events` for `signature_valid = true` deliveries
  in the suspected compromise window that don't correlate to a real
  attempt your system initiated.
- **Repeated authorization failures**: check the troubleshooting matrix
  first (often a revoked/expired grant, not an attack); if the pattern
  looks like credential-stuffing or brute-force against admin routes,
  there is currently no rate limiting anywhere in this backend (Phase 0 —
  documented known limitation) — this is a real exposure, not a
  false-alarm, if observed at volume.
- **Unexpected payment state transitions**: pull the technical timeline
  and raw `payment_webhook_events` for the affected order first — every
  transition has a corresponding webhook record with its
  signature/timestamp verdict.
- **Duplicate-charge concern**: this system's dedup and idempotency
  guarantees mean a duplicate *webhook delivery* cannot double-charge
  (verified extensively — section G); a duplicate-charge concern more
  likely means two separate *attempts* both reached the gateway, which the
  unresolved-attempt guard is supposed to prevent — check
  `payment_attempts` for the order and confirm only one was ever
  `initiated`/`pending` at a time.
- **Audit/log anomaly**: `event_audit_log` inserts never raise (failures
  are swallowed and only logged locally — see `audit_service.py`'s
  docstring) — a *missing* expected audit row for an action that clearly
  happened is possible under a DB outage at exactly the wrong moment; it
  does not mean the action didn't happen, only that its audit trail may be
  incomplete for that one event.

---

## M. Backup/Recovery Boundaries

Database backup and disaster recovery are **entirely outside this
repository** — nothing here provisions, schedules, or verifies backups
for `events_db` or `alumni_db`. Whatever manages the actual Postgres
instance (a managed cloud database service, a self-hosted setup with its
own backup tooling, etc.) owns that responsibility. This runbook does not
invent or assume any specific backup cadence, retention window, or restore
procedure — confirm those with whoever owns the database infrastructure
before relying on any assumption about recoverability.

---

## N. Known Limitations

Carried forward from the prior sprint's report plus what this sprint
found:

- No real payment gateway — deterministic sandbox only, no real money.
- No refunds, cancellations, transfers, receipts, GST invoices, credit
  notes, or settlement reconciliation.
- No discounts, coupons, promotions, or non-individual pricing (family/
  group/early-bird).
- Payment exceptions are read-only (dev-diagnostics only) — no production
  resolution workflow exists (section H).
- No rate limiting anywhere in this backend.
- No secret manager — secrets live in plain environment configuration.
- No dedicated `event_admin` revoke endpoint (platform roles have one;
  event-scoped membership currently requires a direct DB update — section
  L).
- No scheduler is wired up for the expiry sweep — the script exists and is
  fully tested, but nothing invokes it automatically until ops configures
  one (section F).
- **RESOLVED (admin-event-schema-alignment sprint)**: `admin_events.py`'s
  event-mutation routes (create/update/publish/close event, create
  session) and the full check-in subsystem are now functionally correct
  against the real schema — all 13 routes work. The fix consolidated
  event CRUD onto the already-correct `EventsService`/`EventsRepository`
  stack `app/api/events.py` already used (the broken `EventRepository`/
  `EventService` were deleted, not repaired independently), rewrote
  `CheckInRepository`/`CheckInService` against the real `check_ins`
  columns, and fixed `registrations.qrtoken` never being populated at
  registration time (a second, independently-discovered gap — check-in
  could never have found any real registration without it). One new
  migration was required (`019_check_ins_uniqueness.sql` — a unique index
  on `check_ins(event_id, registration_id)`, needed for genuine
  concurrency-safe duplicate-check-in prevention). "Close" maps to
  `status='completed'` (the active status model has no separate 'closed'
  value). See `docs/payments/ADMIN_EVENT_SCHEMA_ALIGNMENT_REPORT.md` for
  full before/after evidence.
- **Still PARTIAL, by explicit product/schema decision**: check-in
  *attempt* logging (`GET .../check-in-attempts`) — no `check_in_attempts`
  table exists in the active schema; the route returns a documented `501`
  rather than fabricated data. A registration's check-in eligibility is
  `status == 'registered'` only; a successful check-in never mutates
  `registrations.status` (represented entirely by a `check_ins` row) —
  this was a deliberate decision to keep the check-in subsystem from
  touching the payment domain's status machine, capacity counting, or
  `uq_registrations_active`.
- `admin_events.py`'s two routes with no per-event scope
  (`POST /events` create, `GET /events` list-all) are `platform_admin`
  -only — there is no "list only my events" view for an `event_admin`.
- **RESOLVED (admin-auth-unification sprint)**: `app/api/events.py`'s
  admin routes (create/list/get/update/status), `app/api/people.py`
  (event people CRUD), and `app/api/sponsors_partners.py` (event
  sponsor/partner CRUD) previously trusted only `app.middleware.dev_auth`'s
  unauthenticated `X-Dev-User` header — reachable with zero real identity
  verification whenever `APP_ENV` was left at its `development` default
  (see section B). All three now use the same real Firebase-JWT-backed
  `admin_auth.py` RBAC as `admin_events.py`/`admin_payments.py`
  (`require_platform_role("platform_admin")` for the two routes in
  `events.py` with no `event_id` to scope to; `require_event_admin`
  everywhere else). `events.py`'s two public routes
  (`/events/public`, `/events/public/{id}`) remain intentionally
  unauthenticated — unaffected. `people.py`/`sponsors_partners.py`
  mutations are now audited (`person_*`/`sponsor_*`/`partner_*` event
  types in `event_audit_log`), closing a governance gap that existed
  independently of the auth mechanism (these routers previously emitted
  no audit trail at all). `app.middleware.dev_auth` itself is unchanged
  and still gated by `APP_ENV=development`, but as of this sprint no
  business-or-admin-capable router imports it — its only remaining
  callers are the self-contained, equally `APP_ENV`-gated
  `dev_diagnostics.py`/`week5_diagnostics.py` tooling. See
  `docs/payments/ADMIN_AUTH_UNIFICATION_SPRINT_REPORT.md` for the full
  before/after reproduction and route-by-route evidence.
- Payment retention/cleanup policy (how long webhook events, audit rows,
  failed attempts, exceptions are kept) remains undecided — explicitly a
  future governance decision, not something to infer a default for.
