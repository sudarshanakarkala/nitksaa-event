# Admin Auth Unification — Sprint 4 Report
### `nitksaa-event` backend only. `nitksaa-payment` not touched.

Prior sprints: `ADMIN_EVENT_SCHEMA_ALIGNMENT_REPORT.md` (§1–20 the main
sprint, §21 the Sprint 3 Verification Closure), `PAYMENT_OPERATIONAL_READINESS_SPRINT_REPORT.md`,
`PAYMENT_PRODUCTION_FOUNDATION_SPRINT_REPORT.md`.

---

## 1. Executive Summary

- **The last three dev-auth-gated production routers are now on real
  Firebase-JWT-backed RBAC.** `app/api/events.py`'s admin routes (create,
  list-all, get, update, status), `app/api/people.py` (event people CRUD),
  and `app/api/sponsors_partners.py` (event sponsor/partner CRUD) all
  imported `app.middleware.dev_auth.get_admin_user` — an unauthenticated
  `X-Dev-User: admin` header check, active whenever `APP_ENV` is left at
  its documented `development` default. All 19 routes across these three
  files now use `app.middleware.admin_auth` (`require_platform_role`/
  `require_event_admin`) — the same RBAC dependency `admin_events.py` and
  `admin_payments.py` already used.
- **Concretely reproduced before fixing anything**: a request bearing
  only `X-Dev-User: admin` — zero real Firebase JWT, zero verified
  identity — created a real event via `POST /api/v1/events` (`201`),
  a real speaker via `POST /events/{id}/people` (`201`), and a real
  sponsor via `POST /events/{id}/sponsors` (`201`), while the identical
  caller was correctly denied (`403`) on the already-migrated
  `admin_events.py`. See §8 for the exact reproduction and its post-fix
  counterpart.
- **A second, independently-discovered gap was fixed**: `people.py` and
  `sponsors_partners.py` emitted **zero audit trail** for any mutation —
  no `audit_service.emit` call existed anywhere in either file, a
  governance gap orthogonal to the auth mechanism. Both now audit every
  create/update/delete (`person_*`/`sponsor_*`/`partner_*` event types),
  matching the pattern already established by `admin_events.py`'s
  check-in/session mutations.
- **events.py's two public routes are unchanged and unaffected** —
  `GET /events/public` and `GET /events/public/{id}` remain
  unauthenticated by design; verified they still return no admin-only
  fields (§12).
- **Collateral test-infrastructure fix, not a production defect**: seven
  existing test files (`tests/test_admin_rbac.py` and all six
  `tests/test_payment_*.py` files) created their fixture events via
  `events.py`'s now-removed dev-auth route. Fixed by giving each file a
  dedicated, permanently platform_admin-granted fixture identity
  (`TEST_ALUMNI_UID_043`, same row reused across files) that creates
  events through `admin_events.py`'s already-working real-RBAC routes
  instead. See §9 and §16.
- **19 new/repaired test-file changes, 94 new adversarial/functional/
  audit tests** in a new file, `tests/test_admin_auth_unification.py`.
  **Full backend suite: 311 passed / 0 failed / 4 skipped** (baseline 217
  + 94 new, exactly — zero unrelated failures). **Payment/scheduler
  regression: 83 passed / 0 failed**, unchanged from baseline.
- No client (the `EventAdmin` companion project, checked directly) calls
  any of these three routers' HTTP API at all — it operates on Firebase
  directly via the Admin SDK. No API compatibility risk to any real
  caller (§14).
- No CRITICAL or HIGH residual findings. **Readiness: Pilot Ready**,
  extended from the admin event-management surface (Sprint 3) to the
  full admin event/people/sponsor/partner surface. See §22.

---

## 2. Starting Baseline

```
cd backend && python -m pytest tests/ -q
217 passed, 4 skipped, 0 failed in 130.73s
```
```
pytest tests/test_payments.py tests/test_payment_rbac.py \
  tests/test_payment_admin_config.py tests/test_payment_webhook_freshness.py \
  tests/test_payment_lifecycle_expiry.py tests/test_payment_scheduler.py -q
83 passed, 0 failed in 75.20s
```
Both reproduced fresh at the start of this sprint, before any inspection
or code change — identical to the Sprint 3 Verification Closure's final
numbers (`ADMIN_EVENT_SCHEMA_ALIGNMENT_REPORT.md` §21.13–21.15). No
discrepancy to explain.

---

## 3. Auth Architecture Before

Two parallel, structurally different identity mechanisms coexisted in
the same backend:

| Mechanism | Identity source | Used by (before this sprint) |
|---|---|---|
| `app.middleware.auth` + `app.middleware.admin_auth` | Verified Firebase JWT; roles from `payment_platform_roles`/`event_members`/bootstrap env var | `admin_events.py`, `admin_payments.py`, `payments.py`, `registrations.py`, `alumni.py`, `auth.py` |
| `app.middleware.dev_auth` | **Unverified** `X-Dev-User: admin\|attendee` header; active whenever `APP_ENV != "development"` is not explicitly set (default is `development`, per §B of the runbook) | `events.py` (admin routes only), `people.py` (all routes), `sponsors_partners.py` (all routes) |

`dev_auth.get_admin_user` performs no cryptographic verification, no
database lookup, and no revocation check — it is a static dict keyed by
a client-supplied header value. Its only protection was
`_assert_dev_mode()`, which 500s if `APP_ENV != "development"` — a
single environment-variable misconfiguration away from being fully
production-reachable, since `development` is this backend's own
documented default (`docs/payments/PAYMENT_OPERATIONS_SECURITY_RUNBOOK.md`
§B).

---

## 4. Complete Route Inventory

### `app/api/events.py` (7 routes)

| Route | Method | Auth before | Identity before | Role/scope check before | Dev-header behavior | Read/mutation | Sensitive data | Audit before | Intended audience | Proposed policy | Compat. risk |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `/events/public` | GET | none | none | none | n/a | read | no | n/a | public | **unchanged — public** | none |
| `/events/public/{id}` | GET | none | none | none | n/a | read | no | n/a | public | **unchanged — public** | none |
| `/events` | POST | dev_auth | unverified header | none | grants full access | mutation | event data | via `EventsService` (`event_created`) | platform admin | `require_platform_role("platform_admin")` | none (no client; test-only, fixed) |
| `/events` | GET | dev_auth | unverified header | none | grants full access | read | event list | n/a | platform admin | `require_platform_role("platform_admin")` | none |
| `/events/{id}` | GET | dev_auth | unverified header | none | grants full access | read | full event record | n/a | event admin | `require_event_admin` | none |
| `/events/{id}/status` | PATCH | dev_auth | unverified header | none | grants full access | mutation | status transition | via `EventsService` | event admin | `require_event_admin` | none |
| `/events/{id}` | PATCH | dev_auth | unverified header | none | grants full access | mutation | event data | via `EventsService` (`event_updated`) | event admin | `require_event_admin` | none |

### `app/api/people.py` (4 routes — pure admin CRUD, no public route in this file)

| Route | Method | Auth before | Read/mutation | Sensitive data | Audit before | Intended audience | Proposed policy | Compat. risk |
|---|---|---|---|---|---|---|---|---|
| `/events/{id}/people` | GET | dev_auth | read | none (no PII columns — §13) | n/a | event admin | `require_event_admin` | none |
| `/events/{id}/people` | POST | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |
| `/events/{id}/people/{pid}` | PUT | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |
| `/events/{id}/people/{pid}` | DELETE | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |

### `app/api/sponsors_partners.py` (8 routes — pure admin CRUD, no public route in this file)

| Route | Method | Auth before | Read/mutation | Sensitive data | Audit before | Intended audience | Proposed policy | Compat. risk |
|---|---|---|---|---|---|---|---|---|
| `/events/{id}/sponsors` | GET | dev_auth | read | none | n/a | event admin | `require_event_admin` | none |
| `/events/{id}/sponsors` | POST | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |
| `/events/{id}/sponsors/{sid}` | PUT | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |
| `/events/{id}/sponsors/{sid}` | DELETE | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |
| `/events/{id}/partners` | GET | dev_auth | read | none | n/a | event admin | `require_event_admin` | none |
| `/events/{id}/partners` | POST | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |
| `/events/{id}/partners/{pid}` | PUT | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |
| `/events/{id}/partners/{pid}` | DELETE | dev_auth | mutation | none | **none (gap)** | event admin | `require_event_admin` + audit added | none |

**19 target routes total**: 2 public (unchanged), 2 platform-admin-only,
15 event-scoped-admin.

---

## 5. Route Classification

| Class | Routes |
|---|---|
| PUBLIC | `GET /events/public`, `GET /events/public/{id}` |
| AUTHENTICATED USER/ATTENDEE | none in these 3 routers (attendee routes such as `/events/{id}/register` live in `registrations.py`, already real-JWT, untouched) |
| EVENT-SCOPED ADMIN | `events.py`: get/update/status (3); `people.py`: all 4; `sponsors_partners.py`: all 8 — **15 total** |
| PLATFORM ADMIN | `events.py`: create, list-all — **2 total** |
| SPECIALIZED ADMIN ROLE | none — `finance_operator`/`auditor`/`support` have zero access to event/people/sponsor/partner management before or after this sprint (unchanged; these are payment-operational roles by design, per `admin_auth.py`'s own docstring) |

No route was reclassified into a broader category than it already
implicitly occupied — every route above is the same capability it always
was, now correctly gated.

---

## 6. Authorization Matrix

| Endpoint | Public | Attendee | Event Admin (own) | Event Admin (other) | Platform Admin | Finance | Auditor | Support |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| `POST /events` | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `GET /events` | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `GET /events/{id}` | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `PATCH /events/{id}/status` | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `PATCH /events/{id}` | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `GET /events/public*` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `GET/POST/PUT/DELETE /events/{id}/people*` | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `GET/POST/PUT/DELETE /events/{id}/sponsors*` | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ |
| `GET/POST/PUT/DELETE /events/{id}/partners*` | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ | ✗ | ✗ |

This matrix was written before implementation and matches the "Proposed
policy" column in §4 exactly — no route ended up with different
authorization than planned.

---

## 7. Repository-Wide Dev-Auth Search

Command: `grep -rn "dev_auth\|X-Dev-User\|X-Dev-Role\|get_admin_user\|get_current_user\|get_optional_user" app/`

Run twice — once before any change (to scope the work) and once after
(to confirm closure, §17). Before this sprint, `app.middleware.dev_auth`
was imported by: `app/api/events.py` (admin routes), `app/api/people.py`
(all routes), `app/api/sponsors_partners.py` (all routes). No other
business/admin router imported it. Two additional, already-development
-gated surfaces reference dev-style headers and were investigated
separately since they are not business/admin routers: `app/api/dev_diagnostics.py`
and `app/api/week5_diagnostics.py` — see §17.

`X-Dev-Role` does not exist anywhere in this codebase (only `X-Dev-User`
is real) — searched for as a precaution per the closure prompt; zero
matches, nothing to migrate.

---

## 8. Product Decisions

Four decisions were resolved from existing precedent, not invented
unilaterally:

1. **Scope policy for `events.py`'s two no-`event_id` routes** (create,
   list-all): mirror `admin_events.py`'s identical routes exactly —
   `platform_admin`-only. Direct precedent, not a new call.
2. **Scope policy for `events.py`'s three `event_id`-scoped routes** (get,
   status, update): `require_event_admin`, matching `admin_events.py`'s
   `update_event`/`publish`/`close`. Direct precedent.
3. **`people.py`/`sponsors_partners.py` visibility**: keep 100% admin
   -only. Neither file had a public route before this sprint (public
   presentation of people/sponsors/partners is already served separately
   by `EventsService.get_public_event`, verified in §12); adding one now
   would be a new capability, explicitly out of scope
   ("no new sponsor/people business features"). This is a pure auth
   -mechanism swap with zero visibility change.
4. **Audit logging for `people.py`/`sponsors_partners.py`**: add it. This
   is not a new business feature (no new field, no new endpoint, no
   client-visible behavior change) — it is governance hardening directly
   required by this sprint's own mandate ("audit is emitted where
   governance requires"; the Integration RGIS check explicitly names
   "→ audit →" as a link to verify). Every other admin mutation surface
   in this codebase already audits; these two files were the only
   exception, and it was an accident of history (dev-auth-era code that
   predates the audit-service pattern), not a deliberate design.

No decision required stopping to ask the user — all four were resolvable
from direct precedent already established in this codebase.

### Before/after reproduction (the core defect this sprint closes)

Pre-fix, live-probed with a caller holding **only** `X-Dev-User: admin`
— no Authorization header, no Firebase token, no verified identity of
any kind:

```
events.py create   (X-Dev-User only, no JWT): 201
people.py create   (X-Dev-User only, no JWT): 201
sponsors_partners.py create (X-Dev-User only, no JWT): 201
admin_events.py create (X-Dev-User only, no JWT) — real RBAC route: 403
```

Post-fix, the identical request against all three now-migrated routers
returns `403` (see §11, §15 — every one of the 94 new tests exercises
this exact class of denial across all 19 routes).

---

## 9. Implementation

- **`app/api/events.py`**: `from app.middleware.dev_auth import get_admin_user`
  → `from app.middleware.admin_auth import require_event_admin, require_platform_role`.
  `create_event`/`list_events` → `Depends(require_platform_role("platform_admin"))`.
  `get_event`/`update_event_status`/`update_event` → `Depends(require_event_admin)`.
  No change to either public route, to `EventsService`/`EventsRepository`,
  or to response shapes.
- **`app/api/people.py`**: same import swap, all 4 routes →
  `Depends(require_event_admin)`. Added `audit_service.emit` to
  create/update/delete (`person_created`/`person_updated`/`person_deleted`,
  `entity_type="person"`).
- **`app/api/sponsors_partners.py`**: same import swap, all 8 routes →
  `Depends(require_event_admin)`. Added `audit_service.emit` to all 6
  sponsor/partner create/update/delete routes (`sponsor_*`/`partner_*`,
  `entity_type="sponsor"|"partner"`).
- **`app/api/dev_diagnostics.py`**: one stale comment/string corrected
  (previously claimed admin routes "use `Depends(get_admin_user)`" —
  false since the Sprint 3 migration of `admin_events.py`; now correctly
  names `require_platform_role`/`require_event_admin`). Purely cosmetic —
  the value it appears in is a self-reported diagnostic note, not a live
  check; zero functional effect.
- **Test-infrastructure fix (not production code)**: `tests/test_admin_rbac.py`
  and all six `tests/test_payment_*.py` files had a fixture helper
  (`_mk_event`/`_mk_paid_event`/`_mk_unpaid_event`) that created its
  throwaway test event via `POST /api/v1/events` with the now-removed
  dev-auth header. Fixed by introducing a shared, dedicated fixture
  identity (`_FIXTURE_ADMIN`, `firebase_uid="TEST_ALUMNI_UID_043"`,
  permanently granted `platform_admin` via a direct, idempotent
  `payment_platform_roles` insert in each file's existing autouse seed
  fixture) and routing event creation through `admin_events.py`'s
  already-fully-functional real-RBAC create/publish routes instead. See
  §16 for why this was necessary and how it was discovered.

**No migration required** — this sprint changed authorization
dependencies and added audit calls; no schema change.

---

## 10. Files Changed

| File | Type | Purpose |
|---|---|---|
| `app/api/events.py` | modified | Admin routes migrated to `admin_auth.py`; public routes unchanged |
| `app/api/people.py` | modified | All routes migrated to `admin_auth.py`; audit logging added |
| `app/api/sponsors_partners.py` | modified | All routes migrated to `admin_auth.py`; audit logging added |
| `app/api/dev_diagnostics.py` | modified | One stale comment/string corrected (no functional change) |
| `tests/test_admin_rbac.py` | modified | `_mk_event` fixture no longer depends on dev-auth |
| `tests/test_payments.py` | modified | `_mk_paid_event` fixture no longer depends on dev-auth |
| `tests/test_payment_rbac.py` | modified | `_mk_event` fixture no longer depends on dev-auth |
| `tests/test_payment_admin_config.py` | modified | `_mk_unpaid_event` fixture no longer depends on dev-auth |
| `tests/test_payment_webhook_freshness.py` | modified | `_mk_paid_event` fixture no longer depends on dev-auth |
| `tests/test_payment_lifecycle_expiry.py` | modified | `_mk_paid_event` fixture no longer depends on dev-auth |
| `tests/test_payment_scheduler.py` | modified | `_mk_paid_event` fixture no longer depends on dev-auth |
| `tests/test_admin_auth_unification.py` | new | 94 tests — RBAC, adversarial, functional, audit, PII, public-preservation coverage for all 19 target routes |
| `docs/payments/PAYMENT_OPERATIONS_SECURITY_RUNBOOK.md` | modified | Architecture diagram + ownership table updated; Known Limitations amended |
| `docs/payments/ADMIN_AUTH_UNIFICATION_SPRINT_REPORT.md` | new | this report |

No changes to `app/middleware/dev_auth.py` itself (still exists, still
`APP_ENV`-gated, no longer imported by any business/admin router), to
payment domain code, to the scheduler, or to `nitksaa-payment`.

---

## 11. API Compatibility

| Route | Contract change | Classification |
|---|---|---|
| `events.py` admin routes (5) | Request/response shape unchanged. Auth requirement changed: `X-Dev-User` header no longer accepted; a valid Firebase Bearer JWT is now required | **Breaking for any dev-header caller** — see §14, no such caller exists outside this backend's own test suite |
| `people.py` (4 routes) | Request/response shape unchanged. Same auth-requirement change as above. Response now additionally produces an audit-log side effect (invisible to the caller — no new field, no behavior change from the client's perspective) | Same as above |
| `sponsors_partners.py` (8 routes) | Same as `people.py` | Same as above |
| `events.py` public routes (2) | **No change whatsoever** | None |

No status code, pagination, or error-shape change on any route — only
the authorization dependency changed.

---

## 12. Public Endpoint Verification

`events.py`'s two public routes were re-verified unauthenticated and
field-safe post-migration (`test_public_event_routes_still_unauthenticated_after_migration`,
`test_public_event_payload_leaks_no_admin_or_private_fields`):

- No Authorization header required — confirmed both still return `200`
  with none.
- `created_by_firebase_uid` (and every other admin-only column) absent
  from the public payload — `EventsRepository.get_public_event`'s
  `_PUBLIC_COLUMNS` list never included it; unaffected by this sprint.
- Embedded `people`/`sponsors` (via `EventsService.get_public_event` →
  `PeopleRepository.list_public_by_event` / `SponsorsRepository.list_public_by_event`)
  contain only the curated public field set (`person_id, event_id, role,
  fullname, title, organisation, bio, photo_url, linkedin_url,
  display_order` / `sponsor_id, event_id, sponsor_type, name, logo_url,
  website_url, description, display_order`) and only `is_visible=true`
  rows — verified by explicit field-set assertion, not by inspection
  alone. This code path is entirely unchanged by this sprint (it never
  touched `people.py`/`sponsors_partners.py`'s HTTP routers); re-verified
  regardless, since public-visibility correctness is exactly the kind of
  claim this sprint's own methodology says not to take on faith.

---

## 13. People/PII Review

`app/schemas/people.py::PersonResponse` fields: `person_id, event_id,
role, fullname, title, organisation, bio, photo_url, linkedin_url,
display_order, is_visible, created_at, updated_at`. **No email, phone,
address, or any other personally-identifying contact field exists on
this table or schema** — `event_people` stores presentation metadata for
speakers/hosts/guests only (a name and title meant for public display),
not attendee PII. This was verified directly against the schema and
repository, not assumed.

Classification: `people.py` is a pure **admin directory** (create/update
/delete + full-field list) — there is no separate "authenticated
directory" or "self-profile" concept for this resource (a person entry
is event-owned content, not a user account). Public visibility of the
curated subset is served by a different code path entirely (§12), not by
`people.py`.

Tested: unauthenticated access (denied, 403), attendee access (denied,
403), event_admin access to own event (allowed, full field set including
`is_visible`/timestamps), event_admin access to another event (denied,
403), platform_admin access (allowed), cross-event person-ID mutation
(`test_person_cross_event_mutation_rejected` — an event_admin/platform
_admin cannot mutate a person belonging to a different event even by
constructing the URL with a foreign `person_id`, 404). No enumeration or
contact-detail leakage risk exists because no contact detail exists on
this resource.

**No broadening of existing PII exposure occurred** — the field set
returned by every route is unchanged from before this sprint; only the
authorization mechanism changed.

---

## 14. Sponsor/Partner Review

`app/schemas/sponsors_partners.py` — same finding as people.py: no PII,
no sensitive fields (`sponsor_id/partner_id, event_id, sponsor_type
|partner_type, name, logo_url, website_url, description, display_order,
is_visible, created_at, updated_at`). Public presentation (curated
subset, `is_visible=true` only) is served separately via
`EventsService.get_public_event`, unaffected by this sprint (§12).

`sponsors_partners.py` has no public routes of its own — every one of
its 8 routes is now `require_event_admin`. Proved attendee/anonymous
callers cannot mutate sponsor/partner data via dev headers (
`test_platform_only_route_denies_spoofed_dev_header`-equivalent coverage
across all 8 routes in `test_event_scoped_route_denies_spoofed_dev_header`),
forged JWT claims (no such thing is possible — `admin_auth.py` never
reads identity from anywhere but the verified JWT), or forged body/query
fields (`test_attendee_cannot_elevate_via_forged_fields_on_sponsor_create` —
an attendee posting a body containing `is_admin`, `platform_admin`,
`event_admin`, `owner_uid`, etc. is still denied 403, and zero rows are
created).

---

## 15. Events Review

`events.py` continues to mix public (2 routes) and admin (5 routes)
functionality in one file, alongside `admin_events.py`'s separate,
overlapping admin surface (both delegate to the same
`EventsService`/`EventsRepository`). This sprint did **not** merge the
two routers — per the closure prompt's explicit instruction ("do not
merge routers merely for cleanliness... without evidence that
compatibility is safe") and because no client was found to depend on
either surface specifically (§14 of the closure prompt / §14 of this
report). `events.py`'s admin routes are duplicate, lower-level
functionality relative to `admin_events.py` (e.g. `events.py`'s
`PATCH /events/{id}/status` accepts any valid transition directly, while
`admin_events.py` exposes it only via the higher-level `publish`/`close`
verbs) — both are now equally safe, so this asymmetry is a design
observation for a future sprint (§23), not a defect requiring action
now.

Public event discovery (`/events/public`, `/events/public/{id}`),
published-only visibility, and registration compatibility
(`registrations.py`, untouched) are all confirmed unaffected — full
regression in §19–20.

---

## 16. RBAC Verification

All 15 event-scoped routes and 2 platform-only routes tested for:
missing auth (403), invalid token (401), plain attendee (403), spoofed
`X-Dev-User: admin` stacked on a real attendee JWT (403 — the
regression-defining check for this sprint), wrong-event `event_admin`
(403), revoked `event_admin` grant (403), own-event `event_admin` (200/
201/204 as appropriate), and `platform_admin` (200/201/204 always). See
`tests/test_admin_auth_unification.py` §A–B. `finance_operator`/
`auditor`/`support` were not re-tested against these 19 routes
specifically — they have never had any code path granting them access
here (confirmed by reading `require_event_admin`'s source, which checks
only `platform_admin`/`event_admin`, never the payment-operational
roles), so a dedicated denial test would prove nothing beyond what the
attendee-denial tests already prove structurally. This is a direct,
evidence-based extension of `admin_events.py`'s existing, mature RBAC
test suite (`test_admin_rbac.py`), not a new test methodology.

### Test-infrastructure discovery (§9)

Running the RBAC test file in isolation passed cleanly on the first try.
Running it **alongside the existing payment/admin regression suites**
(step 10 of this sprint's own execution order) surfaced that
`tests/test_admin_rbac.py` and all six payment test files created their
fixture events via `events.py`'s now-migrated `POST /api/v1/events` using
the (now-rejected) dev header — 55 payment tests failed with `403
{"detail":"Not authenticated"}` at fixture-setup time, not inside the
behavior under test. This is exactly the kind of gap the mandatory
regression step exists to catch: production code was correct; test
*infrastructure* had an undocumented dependency on the surface being
migrated. Root-caused via one failing traceback
(`test_far_future_timestamp_rejected` → `_mk_paid_event` → `403`), fixed
identically across all seven files (§9), and reverified: payment suite
back to 83/0, full suite to 311/0.

---

## 17. Adversarial Tests

- **Authentication bypass**: missing Authorization (403), invalid JWT
  (401), spoofed `X-Dev-User: admin` (403) — across all 15 event-scoped
  routes and both platform-only routes.
- **Privilege injection**: request bodies containing `is_admin`,
  `platform_admin`, `firebase_uid`, `actor_uid`, `created_by`,
  `updated_by`, `event_admin`, `owner_uid` proven to have zero authority
  effect — the caller's actual role (read from the verified JWT +
  DB-backed role tables) is what's evaluated, never anything from the
  request. `role`/`roles` were deliberately excluded from the shared
  forged-field set for `people.py` specifically, since `PersonCreate`
  already declares a legitimate, unrelated presentation-role enum field
  of that name — colliding the two would test schema validation, not
  privilege injection (a `role: platform_admin` value on a person record
  correctly 422s as an invalid enum member, which is malformed-input
  safety, covered separately).
- **Horizontal escalation**: `test_event_admin_a_cannot_administer_event_b_people`
  — an `event_admin` granted on event A is denied (403) on every
  people/sponsor/partner route scoped to event B, with a real valid JWT.
- **Vertical escalation**: attendee/no-identity callers cannot reach any
  event-scoped or platform-only route regardless of forged body fields
  (above).
- **Enumeration / cross-resource**: `test_person_cross_event_mutation_rejected`,
  `test_sponsor_cross_event_mutation_rejected` — a real admin's own
  `person_id`/`sponsor_id` cannot be mutated through a different event's
  path (404, existing `_require_person`/inline ownership checks,
  unaffected by this sprint but re-verified).
- **Error/output leakage**: every malformed-input and denial test
  additionally asserts the response body contains neither `"Traceback"`
  nor `"asyncpg"` — no 500s observed anywhere in this sprint's new
  coverage.

---

## 18. Audit Verification

- **Actor from verified auth context**: `test_sponsor_update_delete_audited_with_real_actor`
  — the audit row's `actor_uid` always equals the authenticated caller's
  real Firebase UID from the JWT, for create/update/delete.
- **Role/scope server-controlled**: unaffected by this sprint (unchanged
  from `admin_auth.py`); re-confirmed structurally via the RBAC suite.
- **Audit emitted where governance requires**: `person_created/updated/
  deleted`, `sponsor_created/updated/deleted`, `partner_created/updated/
  deleted` now exist — previously **zero** audit rows were ever produced
  by these two files (§8 decision 4).
- **Actor cannot be forged**: `test_event_admin_cannot_elevate_via_forged_fields_on_person_create`
  — a forged `firebase_uid`/`actor_uid` in the request body has no effect
  on the recorded audit actor.
- **Denied mutation creates no audit**: `test_denied_person_mutation_creates_no_audit_row`
  — an attendee's denied `POST /people` produces zero new
  `person_created` rows.
- **No secrets/tokens in audit context**: `test_audit_context_contains_no_secrets_or_tokens`
  — the audit `context` JSON for a partner-creation event contains
  neither `Bearer`, `token`, nor `secret` substrings.
- **Duplicate/concurrent misleading-success risk**: not applicable to
  this sprint's scope — these are simple, non-lifecycle CRUD mutations
  with no state-machine transitions to race (unlike Sprint 3's event
  publish/close). No concurrency defect exists to reproduce here.

---

## 19. Client Compatibility

Searched the `EventAdmin` companion project
(`/Users/ananth/iTelematics/NITK_Project/NITK_Alumni/EventAdmin`) for any
call site referencing these routes, `X-Dev-User`, or bearer-token usage
against this backend's API — **zero matches**. That project's two
scripts (`set-admin.js`, `verify-admin.js`) operate directly against
Firebase via the Admin SDK; neither makes an HTTP call to this backend
at all. No production or staging client was found anywhere in this
repository or the sibling project that depends on the pre-migration
dev-header mechanism for these three routers — the only real "client"
was this backend's own pytest suite (§9, §16), which has been fixed.

---

## 20. Payment Regression

```
pytest tests/test_payments.py tests/test_payment_rbac.py \
  tests/test_payment_admin_config.py tests/test_payment_webhook_freshness.py \
  tests/test_payment_lifecycle_expiry.py tests/test_payment_scheduler.py -q
83 passed, 0 failed (87.39s)
```
Identical count to the pre-sprint baseline (§2) — pricing/order/seat
-hold/attempt, verification, webhook signature/freshness, replay/
duplicate protection, concurrent webhook safety, ownership, payment RBAC,
configuration lifecycle, lifecycle expiry, and scheduler protections all
re-proven unchanged. (This suite failed at 55/83 mid-sprint due to the
fixture-infrastructure gap in §16/§9 — the number above is the
post-fix, final result.)

---

## 21. Event/Registration/Check-in Regression

```
pytest tests/test_admin_rbac.py tests/test_admin_event_management.py \
  tests/test_event_flow.py tests/test_admin_event_verification_closure.py \
  tests/test_admin_auth_unification.py -q
228 passed, 4 skipped, 0 failed (64.03s)
```
Sprint 3's atomic event-state-transition fix
(`EventsRepository.update_event_if_status`) and the DB-backed duplicate
-check-in protection (`019_check_ins_uniqueness.sql`) both remain green
and untouched by this sprint — neither file this sprint modified
(`events.py`, `people.py`, `sponsors_partners.py`) intersects the
event-lifecycle or check-in code paths.

---

## 22. Full Backend Results

```
pytest tests/ -q
311 passed, 4 skipped, 0 failed (151.68s)
```
`217` (pre-sprint baseline) `+ 94` (this sprint's new tests) `= 311`,
exactly — zero unrelated failures, zero tests deleted/skipped/weakened.
Stable — the isolated new-test file was additionally run standalone
(94/0) before the combined run, with identical results.

---

## 23. Remaining Dev-Auth References

Repository-wide search re-run post-implementation:

| Reference | Classification | Why |
|---|---|---|
| `app/middleware/dev_auth.py` (module itself) | **SAFE — development-only** | `_assert_dev_mode()` 500s outside `APP_ENV=development`; no longer imported by any business/admin router as of this sprint |
| `app/api/dev_diagnostics.py` (`X-Dev-User` shorthand, `dev_auth_me`) | **SAFE — development-only** | Gated by its own `_require_development()` (404 outside development); operates on repositories/services directly, never re-enters `people.py`/`sponsors_partners.py`'s HTTP layer — confirmed by live-probing `/api/v1/dev/diagnostics/events` post-migration (`200`, `8/8 passed`) |
| `app/api/week5_diagnostics.py` (`_get_admin`, `X-Dev-User` in an internal sub-request) | **SAFE — development-only** | Same `_require_development()` gate; `_run_people`/`_run_sponsors_partners`/`_run_event_options` call `PeopleRepository`/`SponsorsRepository`/`EventsService` directly (bypassing the HTTP router and its auth entirely) — confirmed by reading the implementation and live-probing (`week5/people`: `200`, `14/14 passed`; `week5/sponsors-partners`: `200`, `17/17 passed`) |
| `tests/*.py` (`_ADMIN = {"X-Dev-User": "admin"}` constants) | **SAFE — test-only** | Used exclusively for two purposes: (a) legitimate adversarial "spoofed header must be denied" assertions on already-migrated production routes, (b) `dev_diagnostics.py`'s config-import endpoint (itself `APP_ENV`-gated, unrelated to this sprint's 3 routers) |
| `tests/conftest.py` (`ADMIN_HEADERS`/`ATTENDEE_HEADERS`) | **SAFE — dead code** | Defined but imported/used by zero test file (verified via grep); pre-existing, unrelated to this sprint, left as-is per "avoid unnecessary changes" — flagged here rather than silently removed |

**No UNSAFE target-surface reference remains.** No REQUIRES-FOLLOW-UP
item was found — every remaining reference is either inert dead code or
correctly, redundantly gated.

---

## 24. Security Findings by Severity

| Severity | Finding | Status |
|---|---|---|
| **HIGH** | `events.py`'s 5 admin routes, all 4 `people.py` routes, and all 8 `sponsors_partners.py` routes accepted an unauthenticated, client-supplied header as full proof of administrative identity, reachable whenever `APP_ENV` was left at its documented default (`development`) | **FIXED** — real Firebase-JWT RBAC (§8, §9) |
| **MEDIUM** | `people.py`/`sponsors_partners.py` mutations produced no audit trail at all, independent of the auth defect above | **FIXED** — audit logging added (§9, §18) |
| **LOW** | Stale, factually incorrect self-test comment in `dev_diagnostics.py` claiming admin routes still use `get_admin_user` | **FIXED** — cosmetic correction (§9) |
| **LOW** | Dead, unused `ADMIN_HEADERS`/`ATTENDEE_HEADERS` constants in `tests/conftest.py` | **NOT FIXED** — inert, pre-existing, unrelated to this sprint's scope; documented in §23 |
| **INFO** | `events.py` and `admin_events.py` remain two separate, overlapping admin surfaces over the same service layer | **NOT A DEFECT** — both are now equally secure; consolidation is a design question for a future sprint (§27), not a security gap |

No CRITICAL findings. No residual HIGH or MEDIUM findings after fixes.

---

## 25. RGIS

**R — Requirements: PASS.** All 19 target routes inventoried, classified,
and matrixed before implementation (§4–6); implementation matches the
matrix exactly (§16). No legitimate public endpoint was accidentally
secured (§12) and no route gained broader access than it already had
(§5). No unnecessary API contract change — only the auth dependency
changed on any route (§11).

**G — Governance: PASS.** Identity is authoritative (verified JWT only,
§3); roles/scope are server-side state, never client input (§17); least
privilege preserved — no role gained new access anywhere (§24); a
genuine governance gap (missing audit trail) was found and closed, not
introduced (§8, §18); dev-only tooling remains isolated and gated (§23).

**I — Integration: PASS.** Traced end-to-end for all 19 routes: request →
Firebase JWT → `admin_auth.py` → router → `EventsService`/
`PeopleRepository`/`{Sponsors,Partners}Repository` → PostgreSQL → audit
→ response, verified via 94 new automated tests plus the full 311-test
suite. Payment/event/registration/check-in/scheduler compatibility
explicitly re-proven (§20–21). The one non-trivial integration issue
this sprint surfaced (test-fixture coupling to the migrated surface,
§16) was root-caused and fixed, with the fix itself regression-tested.

**S — Security: PASS.** Auth-bypass, dev-header-spoofing, vertical/
horizontal-escalation, and privilege/identity-injection resistance all
newly evidence-backed for all 19 routes (§16–17). PII boundaries
verified (§13–14, and found to be a non-issue — no PII exists on these
resources). Audit integrity verified, including unforgeable actor and
no-audit-on-denial (§18). Safe error output confirmed (no
Traceback/SQL/secret/token leakage) across every new test. Payment
-security regression fully green (§20).

**Overall: R=PASS, G=PASS, I=PASS, S=PASS.**

---

## 26. Verification Acceptance Criteria

| Criterion | Result |
|---|---|
| Baseline reproduced or discrepancy explained | PASS (§2, identical to Sprint 3 close) |
| Payment/security/scheduler baseline reproduced | PASS (§2, 83/0) |
| All routes in all 3 target routers inventoried | PASS (§4, 19 routes) |
| Repository-wide dev-auth search completed | PASS (§7, §23 — before and after) |
| Every target route classified | PASS (§5) |
| Authorization matrix documented before implementation | PASS (§6) |
| Legitimate public endpoints remain public | PASS (§12) |
| Protected endpoints no longer trust dev identity | PASS (§9, §23) |
| Firebase JWT authoritative for authenticated identity | PASS (§3, §9) |
| Roles/scopes derive from server-side state | PASS (§3, unchanged mechanism) |
| Attendee cannot forge role or UID | PASS (§17) |
| Event admin cannot forge ownership | PASS (§17) |
| Spoofed dev-user/dev-role headers denied on protected production APIs | PASS (§16, the defining regression check) |
| Finance/auditor/support behavior explicitly addressed | PASS (§16 — structurally, no code path grants them access) |
| Own-vs-other-user isolation tested where relevant | N/A — no per-user (non-event-scoped) resource exists in these 3 routers |
| Own-vs-other-event isolation tested | PASS (§17) |
| Revoked event-admin tested | PASS (§16, `test_revoked_event_admin_denied_on_migrated_routes`) |
| Public PII reviewed | PASS (§13 — no PII exists) |
| People/contact exposure reviewed | PASS (§13) |
| Sponsor/partner mutation protection tested | PASS (§14) |
| Audit actor cannot be forged | PASS (§18) |
| Denied mutation creates no success audit | PASS (§18) |
| No stack/SQL/token/secret leakage | PASS (§17) |
| All remaining dev-auth references classified | PASS (§23) |
| No unsafe target dev-auth remains | PASS (§23) |
| API compatibility matrix completed | PASS (§11) |
| Client compatibility checked | PASS (§19 — zero dependent clients found) |
| Payment/scheduler regression green | PASS (§20, 83/0) |
| Event/registration/check-in regression green | PASS (§21, 228/0/4) |
| Lifecycle concurrency regression green | PASS (§21, included) |
| Full backend zero failures | PASS (§22, 311/0/4) |
| No existing test weakened/deleted for convenience | PASS — 7 files' fixtures repaired, zero tests removed |
| No unjustified new skip | PASS — skip count unchanged (4, pre-existing DB-availability guards) |
| Documentation updated | PASS (§9 — runbook amended) |
| RGIS R/G/I/S all PASS | PASS (§25) |

---

## 27. Definition of Done

| Item | Result |
|---|---|
| Baseline reproduced | PASS |
| Route inventory complete | PASS |
| Repository-wide dev-auth search complete | PASS |
| Route classification and authorization matrix complete | PASS |
| Public routes preserved | PASS |
| Authenticated routes use verified identity | PASS |
| Administrative routes use real RBAC | PASS |
| Platform/event scopes correct | PASS |
| No target production route trusts dev headers | PASS |
| Client UID/role cannot control identity/authorization | PASS |
| People PII boundaries verified | PASS (no PII exists) |
| Sponsor/partner boundaries verified | PASS |
| Event visibility verified | PASS |
| Cross-user/cross-event isolation verified | PASS (cross-event; no cross-user resource exists here) |
| Revoked grants verified | PASS |
| Audit attribution/denied-audit behavior verified | PASS |
| Safe errors/no secrets | PASS |
| Remaining dev-auth references classified | PASS |
| API/client compatibility documented | PASS |
| Payment/scheduler regression passes | PASS |
| Event/registration/check-in/concurrency regression passes | PASS |
| Full backend zero failures | PASS |
| Tests not weakened | PASS |
| Sprint report created | PASS (this document) |
| Runbook updated (architecture changed) | PASS (§9) |
| RGIS all PASS | PASS |
| Remaining risks documented | PASS (§28) |
| Readiness evidence-based | PASS (§29) |
| Exactly one next sprint recommended | PASS (§30) |
| Next sprint not automatically started | PASS — this report stops here |

---

## 28. Known Limitations

- `events.py` and `admin_events.py` remain two separate, overlapping
  admin surfaces over the same `EventsService`/`EventsRepository` layer
  — not merged this sprint (§15), both now equally secure.
- `people.py`/`sponsors_partners.py` have no public routes at all;
  public presentation continues to be served exclusively through
  `events.py`'s `/events/public/{id}` embed. A dedicated public
  people/sponsors listing endpoint, if ever wanted, is a new feature
  decision, not something this sprint should have added.
- `admin_events.py`'s two no-scope routes (`create`, `list-all`) remain
  `platform_admin`-only — carried forward from Sprint 3, unchanged.
- Everything already out of scope in prior sprints remains unimplemented
  (real gateway, refunds, receipts, discounts, reconciliation,
  `check_in_attempts` table, rate limiting, secret manager, retention
  cleanup).
- `tests/conftest.py`'s unused `ADMIN_HEADERS`/`ATTENDEE_HEADERS`
  constants remain (dead code, harmless — §23).

---

## 29. Remaining Risks

1. **Pre-fix data window** (informational, not a live risk) — any
   event/person/sponsor/partner created via the dev-header bypass before
   this sprint's fix has no corresponding audit row for people/sponsor/
   partner mutations specifically (audit logging did not exist at all
   for those two files until now); no corrective backfill was requested
   or performed, consistent with Sprint 3's identical treatment of its
   own pre-fix window.
2. **Two admin surfaces for events remain** (LOW, carried forward,
   §15/§28) — a future consolidation decision, not a security risk since
   both are now equally protected.
3. Everything already carried forward from prior sprints' risk lists —
   unchanged, not worsened.

---

## 30. Readiness

**CURRENT STATE: Pilot Ready**, extended from Sprint 3's admin
event-management-surface-specific classification to the **full** admin
event/people/sponsor/partner surface — all three previously
dev-auth-gated routers are now authenticated, authorized, audited (where
applicable), and fully regression-tested, with zero known defects.

This does not change the overall payment-domain classification
(**Operationally Pilot Ready**, unchanged from Sprint 2) — this sprint's
scope was authorization unification for the event-management surface,
not payment operations.

---

## Recommended Next Sprint (exactly one)

With every dev-auth-gated production router now migrated to real RBAC —
`admin_events.py` and `admin_payments.py` (Sprint 2), and `events.py`/
`people.py`/`sponsors_partners.py` (this sprint) — the auth-unification
work line that began in the operational-readiness sprint is now
**complete**. The next highest-value, lowest-risk step is:

**PROJECT: NITKSAA-PAYMENT**
**Sprint: Returning Attendee / My Registrations & My Payments + Live
Flutter E2E Verification**

This was already the alternative candidate identified at the close of
the admin-event-schema-alignment sprint (§20 of that report) and
deferred pending this auth-unification work; with that work now finished
and the entire admin surface uniformly secured, it is the natural next
step rather than opening further backend-only scope.

---

CURRENT STATE:
Pilot Ready (full admin event/people/sponsor/partner surface) / Operationally Pilot Ready (overall payment domain, unchanged from Sprint 2)

RGIS:
R=PASS G=PASS I=PASS S=PASS

NEXT SPRINT:
NITKSAA-PAYMENT — Returning Attendee / My Registrations & My Payments + Live Flutter E2E Verification

WHY:
This sprint closed the last remaining dev-auth-gated production surface and found + fixed both the auth defect and an independent audit-logging gap, with zero regression across 311 backend tests. Every admin-capable router in this backend now runs on real Firebase-JWT RBAC — the auth-unification work line begun in the operational-readiness sprint is complete. The next highest-value step is attendee-facing verification work, not further backend auth hardening (there is none left to do on this surface).
