# Event Management Platform — Pre-Kickoff Readiness Document

**Status:** Required before Sprint 1 (May 3, 2026)
**Owner:** Engineer A (tech lead) with sign-off from all three engineers
**Companion docs:** `EVENT_MANAGEMENT_REQUIREMENT_AND_DESIGN.md`, `SPRINT_RELEASE_PLAN.md`

---

## 0. How to use this document

This is the single document that must be **read, agreed, and signed off by all three engineers before Sprint 1 begins.** It contains:

- **Section 1** — operational items that must be *done* (KYC, accounts, infra) before May 3.
- **Sections 2–11** — standards and norms that must be *agreed* before any code is written.
- **Section 12** — a sign-off checklist confirming everyone has read and accepted it.

Treat sections 2–11 as a living handbook — update them as the team learns, but only by PR review, not by edit-in-place.

---

## 1. Pre-Kickoff Operational Checklist

These tasks must be **complete or in motion** before May 3. Items with lead time are flagged.

### 1.1 Business & Legal

| # | Item | Owner | Lead Time | Status |
|---|---|---|---|---|
| 1.1.1 | Company GST + PAN verified for Razorpay | Founder/PM | — | ☐ |
| 1.1.2 | Razorpay account + KYC submitted | Founder/PM | **1–2 weeks** | ☐ |
| 1.1.3 | Razorpay test mode keys obtained | Engineer A | — | ☐ |
| 1.1.4 | Razorpay live mode keys (post-KYC) | Founder/PM | After KYC | ☐ |
| 1.1.5 | Apple Developer Account ($99/yr) | Engineer B | 24–48 h | ☐ |
| 1.1.6 | Google Play Developer Account ($25 one-time) | Engineer B | 24 h | ☐ |
| 1.1.7 | Domain registered (e.g. `eventos.app`) | Founder/PM | 1 h | ☐ |
| 1.1.8 | Privacy Policy drafted | Legal/PM | 3–5 days | ☐ |
| 1.1.9 | Terms of Service drafted | Legal/PM | 3–5 days | ☐ |
| 1.1.10 | Refund Policy drafted | Legal/PM | 2–3 days | ☐ |
| 1.1.11 | DPDP Act (India) data-handling review | Legal | 1 week | ☐ |

### 1.2 Cloud & Infrastructure

| # | Item | Owner | Status |
|---|---|---|---|
| 1.2.1 | Google Cloud organization created | Engineer A | ☐ |
| 1.2.2 | GCP billing account + budget alerts (₹X/month) | Engineer A | ☐ |
| 1.2.3 | Three GCP projects: `evt-dev`, `evt-staging`, `evt-prod` | Engineer A | ☐ |
| 1.2.4 | IAM groups + least-privilege roles | Engineer A | ☐ |
| 1.2.5 | Firebase project linked to each GCP project | Engineer A | ☐ |
| 1.2.6 | DNS configured (Cloudflare or Route53) | Engineer A | ☐ |
| 1.2.7 | Subdomains: `api.`, `api-staging.`, `api-dev.`, `admin.`, `admin-staging.` | Engineer A | ☐ |
| 1.2.8 | Wildcard TLS cert via Google-managed certs | Engineer A | ☐ |

### 1.3 Repositories & Tooling

| # | Item | Owner | Status |
|---|---|---|---|
| 1.3.1 | GitHub organization created | Engineer A | ☐ |
| 1.3.2 | Three private repos: `evt-backend`, `evt-event-app`, `evt-admin` | Engineer A | ☐ |
| 1.3.3 | Branch protection on `main` (require PR + 1 review + green CI) | Engineer A | ☐ |
| 1.3.4 | GitHub Actions secrets (GCP keys, Firebase) | Engineer A | ☐ |
| 1.3.5 | Linear (or Jira) workspace + EVT project | PM | ☐ |
| 1.3.6 | Figma workspace + design system file | Engineer C | ☐ |
| 1.3.7 | 1Password (or Bitwarden) shared vault | Engineer A | ☐ |
| 1.3.8 | Slack workspace + channels (see §10) | PM | ☐ |
| 1.3.9 | Sentry org + 3 projects (backend, event-app, admin) | Engineer A | ☐ |
| 1.3.10 | SendGrid (or Resend) account + sender verified | Engineer A | ☐ |

### 1.4 Knowledge & Access

| # | Item | Owner | Status |
|---|---|---|---|
| 1.4.1 | All engineers have read the Requirement & Design doc | All | ☐ |
| 1.4.2 | All engineers have read the Sprint Release Plan | All | ☐ |
| 1.4.3 | All engineers have read this Pre-Kickoff doc | All | ☐ |
| 1.4.4 | Local dev environment runs (per Onboarding §11) | All | ☐ |
| 1.4.5 | Each engineer has access to all required services | All | ☐ |

---

## 2. Engineering Standards

### 2.1 Languages & Versions

| Stack | Version | Notes |
|---|---|---|
| Python | 3.12 | Backend; pinned in `pyproject.toml` |
| Node.js | 20 LTS | Admin Portal build; pinned in `.nvmrc` |
| Flutter | latest stable channel | Pinned in `fvm` config |
| PostgreSQL | 16 | Cloud SQL |

### 2.2 Code Style — Tools

| Stack | Formatter | Linter | Type checker |
|---|---|---|---|
| Python | Black | Ruff | mypy (strict on `services/`, `models/`) |
| TypeScript | Prettier | ESLint (airbnb-typescript base) | `tsc --noEmit` |
| Dart | `dart format` | `dart analyze` (very_good_analysis ruleset) | built-in |

All three repos enforce these via **pre-commit hooks** and **CI gates**. PRs that fail formatting/linting are auto-rejected.

### 2.3 Naming Conventions

- Files: `snake_case.py`, `kebab-case.tsx`, `snake_case.dart`
- Classes: `PascalCase`
- Functions/variables: `snake_case` (Python, Dart), `camelCase` (TS)
- Constants: `UPPER_SNAKE_CASE`
- Database tables: `snake_case`, plural (`registrations`, `audit_logs`)
- API routes: `kebab-case`, plural (`/api/v1/check-ins`)

### 2.4 File & Folder Structure

Defined per repo in the design doc (§15.1, §15.2, §16.2). Don't deviate without an ADR.

### 2.5 Commits — Conventional Commits

Format: `<type>(<scope>): <subject>`

| Type | Use for |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Code restructure, no behavior change |
| `test` | Tests only |
| `docs` | Docs only |
| `chore` | Tooling, deps, config |
| `perf` | Performance improvement |
| `ci` | CI/CD changes |

Examples:
- `feat(events): add publish endpoint`
- `fix(payments): handle Razorpay webhook duplicate event`
- `chore(deps): bump fastapi to 0.115`

### 2.6 Branching

```
main          ← protected, prod releases tagged here
  ↑
develop       ← default branch, auto-deploys to dev
  ↑
feature/EVT-123-event-publish-endpoint
hotfix/EVT-456-fix-webhook-signature
release/v1.0.0
```

- Feature branches: from `develop`, merged to `develop` via squash merge.
- Release branches: cut from `develop` for staging stabilization, merged to `main` and back to `develop`.
- Hotfix: from `main`, merged to `main` and `develop`.

### 2.7 Pull Requests

| Rule | Value |
|---|---|
| Reviewers required | 1 minimum |
| Self-merge allowed | No (except hotfix with explicit approval) |
| CI must pass | Yes — lint, type, test, build |
| Soft size limit | 400 lines changed (split larger PRs) |
| PR title | Conventional Commit format |
| PR description | Linked Linear ticket + screenshots/curl examples for API changes |
| Stale PR auto-close | After 14 days inactive |

### 2.8 Code Review Norms

- Reviewers respond within 1 business day.
- Reviews are blocking on: correctness, security, public API shape, breaking changes.
- Reviews are non-blocking nits (prefix `nit:` or `optional:`) on: style preferences, naming bikesheds, micro-optimizations.
- Authors don't merge their own PRs.

---

## 3. API Design Guidelines

### 3.1 URL Structure

- All endpoints under `/api/v1/...`
- Resources are plural, kebab-case: `/api/v1/events`, `/api/v1/check-ins`
- Nested resources: `/api/v1/events/{event_id}/registrations`
- Actions on resources (rare): `/api/v1/events/{id}/publish` (POST)

### 3.2 HTTP Methods

| Method | Use for |
|---|---|
| GET | Read (no side effects) |
| POST | Create or action |
| PATCH | Partial update (preferred over PUT) |
| DELETE | Remove (or soft-delete) |
| PUT | Avoid — only for full replacements |

### 3.3 Status Codes

| Code | Meaning |
|---|---|
| 200 | OK (read, update) |
| 201 | Created |
| 204 | No content (delete) |
| 400 | Bad request (malformed) |
| 401 | Unauthenticated |
| 403 | Authenticated but forbidden |
| 404 | Not found |
| 409 | Conflict (duplicate, state violation) |
| 422 | Validation error (well-formed but semantically invalid) |
| 429 | Rate limited |
| 500 | Server error |

### 3.4 Error Envelope (mandatory shape)

```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "Event with id evt_abc not found.",
    "details": {
      "resource": "event",
      "id": "evt_abc"
    },
    "request_id": "req_01HX..."
  }
}
```

### 3.5 Pagination

Cursor-based, never offset-based:

```
GET /api/v1/events?limit=20&cursor=eyJpZCI6...

Response:
{
  "data": [...],
  "next_cursor": "eyJpZCI6...",
  "has_more": true
}
```

### 3.6 Idempotency

Required on:
- `POST /payments/orders`
- `POST /payments/verify`
- `POST /events/{id}/registrations`

Client sends `Idempotency-Key: <uuid>` header. Server stores `(key, response)` for 24h and replays on retry.

### 3.7 Versioning

URL versioning (`/api/v1/`). New major version only when contract breaks. Within v1, additive changes only — never remove or rename a field.

### 3.8 Date & Time

- All API timestamps are ISO 8601 in UTC: `2026-05-03T14:30:00Z`.
- Event-local times stored as UTC + IANA timezone (`Asia/Kolkata`).
- Clients format for display.

### 3.9 Money

- Stored as integer **paise** in DB (avoid float).
- API returns `{ "amount": 50000, "currency": "INR" }` — never `500.00`.

---

## 4. Security Standards

### 4.1 Per-PR Checklist (mandatory)

Author confirms in PR description:

- [ ] No secrets in code or config files
- [ ] Input validated with Pydantic / Zod / Dart models
- [ ] Auth check present on every new endpoint
- [ ] Role + scope check on admin/finance endpoints
- [ ] DB access via ORM (raw SQL requires reviewer approval)
- [ ] No PII in application logs
- [ ] No new HTTP (non-TLS) calls
- [ ] New dependencies vetted (license + security)
- [ ] Error responses don't leak stack traces to clients

### 4.2 Per-Release Checklist

- [ ] `pip-audit` / `npm audit` / `dart pub audit` clean (no high/critical)
- [ ] Secrets rotated if any new contributor in last 90 days
- [ ] Security headers verified (CSP, HSTS, X-Frame-Options, etc.)
- [ ] Rate limits in place on auth + payments endpoints
- [ ] CORS allowlist reviewed

### 4.3 Secrets Management

- All secrets live in **Google Secret Manager** in prod/staging.
- `.env.example` files committed; real `.env` files gitignored.
- Local dev uses local `.env` synced via 1Password CLI, not via Slack/email.
- Secret rotation: every 90 days for service accounts, immediately on suspicion.

### 4.4 Sensitive Data

- Card data: **never touches our servers** (Razorpay-hosted checkout).
- Passwords: never stored — Firebase Auth handles all credentials.
- Email/phone: encrypted at rest (Cloud SQL default), never in logs.
- Audit log: append-only, no UPDATE/DELETE permitted at DB role level.

---

## 5. Testing Strategy

### 5.1 Test Pyramid

| Layer | Coverage target | Speed | Run on |
|---|---|---|---|
| Unit | 80% on `services/`, 100% on `payments/`, `auth/` | < 10s total | Every commit |
| Integration | All API endpoints, real Postgres, mocked external | < 2 min | Every PR |
| E2E / Smoke | Critical paths only | < 5 min | Post-deploy to staging |

### 5.2 What Must Be Tested

- Every payment state transition
- Every auth/role check
- Every audit-logged action
- Every webhook handler (idempotency case included)
- Every config fallback path

### 5.3 What's OK to Skip

- Dumb getters/setters
- Pure UI styling
- Generated code (OpenAPI clients)

### 5.4 CI Gates

PR cannot merge unless:
- Lint passes
- Type check passes
- Unit + integration tests pass
- Coverage threshold not regressed
- Build succeeds

---

## 6. Deployment & Environments

### 6.1 Environments

| Env | Branch | Backend URL | Admin URL | Auto-deploy |
|---|---|---|---|---|
| Dev | `develop` | `api-dev.eventos.app` | `admin-dev.eventos.app` | Yes |
| Staging | `release/*` | `api-staging.eventos.app` | `admin-staging.eventos.app` | Yes |
| Prod | `main` | `api.eventos.app` | `admin.eventos.app` | **Manual approval** |

### 6.2 Deploy Flow

```
develop → auto-deploy to dev
release/vX.Y.Z (cut from develop) → auto-deploy to staging → QA
release/vX.Y.Z merged to main → manual approval → prod
main tagged with vX.Y.Z
```

### 6.3 Database Migrations

- Tool: Alembic.
- Every migration has a `down` step **OR** is purely additive (new column nullable, new table).
- Backward-compatible only — new code must work with old schema for at least one deploy.
- Destructive changes (drop column, rename) are a 2-deploy process: stop using → deploy → drop in next migration.

### 6.4 Rollback

- **Cloud Run:** revert to previous revision (one-click in console; documented in runbook).
- **Database:** forward-only fix; never run `down` migrations in prod without DR review.
- **Mobile app:** can't rollback published version — fix forward via patch release. Server-side feature flags allow disabling broken features instantly.

### 6.5 Hotfix Process

1. Branch `hotfix/EVT-NNN-summary` from `main`.
2. Fix + add regression test.
3. PR with `hotfix:` prefix; one reviewer; expedited.
4. Merge to `main` → manual approval → prod.
5. Cherry-pick to `develop`.
6. Post-mortem within 48 hours if customer-impacting.

---

## 7. Definition of Done

A story is **Done** when **all** of the following are true:

- [ ] Acceptance criteria from the ticket are met
- [ ] Code reviewed by at least one other engineer
- [ ] Unit tests written and passing
- [ ] Integration test added if endpoint or critical flow
- [ ] Pre-PR security checklist (§4.1) confirmed
- [ ] Documentation updated (README, OpenAPI spec, ADR if architectural)
- [ ] Deployed to staging
- [ ] Verified working on staging
- [ ] No regressions in related areas
- [ ] Audit log entry verified for sensitive actions
- [ ] Linear ticket moved to Done with link to PR

A story is **NOT** done if it's "merged but not verified on staging." Merging to develop is not the finish line — staging verification is.

---

## 8. Architecture Decision Records (ADR)

### 8.1 Why

Every non-trivial architectural decision must be captured so future engineers understand *why* — not just *what*.

### 8.2 When to write one

Write an ADR when the decision:
- Is hard to reverse
- Constrains other decisions
- Was contested or had real alternatives
- Affects multiple modules

Do **not** write ADRs for: routine code changes, library version bumps, small refactors.

### 8.3 Location

`/docs/adr/NNNN-short-title.md` in the relevant repo. Numbered sequentially, never deleted (superseded ADRs reference the new one).

### 8.4 Template

```markdown
# ADR-NNNN: <Title>

**Status:** Proposed | Accepted | Superseded by ADR-MMMM
**Date:** YYYY-MM-DD
**Authors:** @engineerA, @engineerB

## Context
What is the issue motivating this decision?

## Decision
What we're going to do.

## Alternatives considered
What else we looked at and why we said no.

## Consequences
Positive and negative outcomes of this decision.
```

### 8.5 Initial ADRs to write in Sprint 1

- ADR-0001: Modular monolith over microservices
- ADR-0002: Hybrid PostgreSQL + Firestore data layer
- ADR-0003: React for Admin Portal (vs Flutter Web)
- ADR-0004: FastAPI for backend (vs Node.js)
- ADR-0005: Razorpay as primary payment gateway
- ADR-0006: Configuration-first architecture via Firebase Remote Config

---

## 9. Risk Register (Initial)

| ID | Risk | Likelihood | Impact | Owner | Mitigation Trigger |
|---|---|---|---|---|---|
| R-01 | Razorpay KYC delay blocks Sprint 5 | Med | High | PM | Start KYC week of Apr 20; escalate if not approved by May 15 |
| R-02 | One engineer leaves mid-project | Low | Critical | PM | Document everything; pair-program critical paths; cross-train |
| R-03 | Scope creep (chat, social features) | High | High | PM | Lock scope; route requests to backlog; weekly scope review |
| R-04 | First production event has P1 bug | Med | High | All | Soft-launch on small breakfast meeting in Sprint 4; engineer on-site |
| R-05 | App Store rejection delays MVP launch | Med | Med | Engineer B | Submit early in Sprint 6; pre-review against guidelines |
| R-06 | Cloud cost overrun | Low | Med | Engineer A | Budget alerts at 50/80/100%; min-instance=0 in dev |
| R-07 | Webhook reliability issues | Med | High | Engineer A | Idempotency from day 1; reconciliation cron from Sprint 11 |
| R-08 | PII / data breach | Low | Critical | All | Per-PR security checklist; pen-test before GA |
| R-09 | Translation backlog (post-launch) | Low | Low | Engineer C | English-only at launch; framework ready for additions |
| R-10 | Firebase Auth vendor lock-in | Med | Low | Engineer A | Auth abstracted at backend; users table is source of truth |

Risk register reviewed at every sprint retro. New risks added; closed risks archived.

---

## 10. Communication & Meeting Cadence

### 10.1 Meetings

| Meeting | Cadence | Duration | Attendees |
|---|---|---|---|
| Daily standup (async) | Every workday | — | All engineers |
| Sprint planning | First Mon of sprint | 1 h | All engineers + PM |
| Mid-sprint check | Wed of week 1 | 30 min | All engineers |
| Sprint review / demo | Last Fri of sprint | 1 h | All + stakeholders |
| Sprint retro | Last Fri of sprint | 30 min | Engineers only |
| Stakeholder demo | Monthly | 30 min | Wider audience |

### 10.2 Async Standup Format

Posted in `#standup` by 11:00 IST every workday:

```
Yesterday: <what I shipped or moved forward>
Today: <what I'm picking up>
Blockers: <none / what's stuck and who can unblock>
```

### 10.3 Slack Channels

| Channel | Purpose |
|---|---|
| `#general` | Team-wide non-engineering |
| `#eng` | Technical discussion, design questions |
| `#standup` | Async daily standups only |
| `#prs` | Auto-posted PR notifications |
| `#releases` | Auto-posted deploy notifications |
| `#incidents` | Production issues only — paged |
| `#random` | Off-topic |

### 10.4 Response Expectations

- Slack mention: same business day
- PR review: within 1 business day
- `#incidents` mention: immediate (page if outside hours)
- Email: not used for engineering coordination

### 10.5 Working Hours & On-Call

- Core hours: 10:00–17:00 IST overlap.
- After-hours work is opt-in, never expected.
- Post-MVP (Sprint 7+): light on-call rotation, weekly. PagerDuty triggers only on prod-down or payment-failure alerts.

---

## 11. Onboarding (Day 1 Checklist for Each Engineer)

By end of Day 1, each engineer must:

- [ ] Have GitHub access to all 3 repos
- [ ] Have GCP IAM access to dev project
- [ ] Have Firebase Console access
- [ ] Have Linear access
- [ ] Have Figma access
- [ ] Have Slack + correct channels joined
- [ ] Have 1Password vault access
- [ ] Have local dev env running:
  - Backend: `make dev` brings up FastAPI + Postgres in Docker
  - Event App: `flutter run` launches against dev API
  - Admin: `pnpm dev` launches against dev API
- [ ] Have made and merged a "hello world" PR (e.g. add their name to `CONTRIBUTORS.md`)
- [ ] Have read this document end-to-end
- [ ] Have read the Requirement & Design doc
- [ ] Have read the Sprint Release Plan

---

## 12. Sign-Off

By signing below, each engineer confirms they have read this document, the Requirement & Design document, and the Sprint Release Plan, and agree to the standards and processes described.

| Name | Role | Date | Signature |
|---|---|---|---|
| _Engineer A_ | Backend / Platform Lead | _____ | _____ |
| _Engineer B_ | Mobile / Event App Lead | _____ | _____ |
| _Engineer C_ | Admin Portal / Frontend Lead | _____ | _____ |
| _PM / Founder_ | Product Owner | _____ | _____ |

---

## 13. Appendix: Documents Deliberately Deferred

These will be written *during* the sprints, not before. Listed here so they're not forgotten.

| Document | When | Owner |
|---|---|---|
| Per-incident runbooks | After first incidents in Sprint 6+ | Engineer A |
| Auto-generated API reference | Continuously, from OpenAPI | CI |
| Admin user manual | Sprint 12 | Engineer C |
| Attendee help-center articles | Sprint 13 | Engineer B |
| On-call playbook | Sprint 12 | Engineer A |
| DR (disaster recovery) drill report | Sprint 13 | Engineer A |
| Per-feature ADRs | As decisions arise | Whoever proposes |
| Post-mortem template | After first incident | Engineer A |
| Brand customization guide (multi-brand) | Sprint 9–10 | Engineer C |

---

*End of document. This is a living standard — update via PR with team review, not direct edit.*
