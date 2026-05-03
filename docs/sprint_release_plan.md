# Event Management Platform — Sprint Release Plan

- **Cadence:** 2-week sprints
- **Start:** Sunday, May 3, 2026
- **Production GA:** October 31, 2026
- **Total sprints:** 13
- **Team:** Engineer A (Backend/Platform), Engineer B (Mobile / Event App), Engineer C (Admin Portal / Frontend)

---

## Status legend

| Value | Meaning |
|---|---|
| `Not Started` | Default |
| `In Progress` | Work begun |
| `Blocked` | Waiting on dependency / decision |
| `In Review` | PR open / under QA |
| `Done` | Merged + verified in staging |
| `Released` | Live in production |

---

## Sprint Calendar (High-Level)

| Sprint | Dates | Theme | Major Milestone |
|---|---|---|---|
| 1 | May 3 – May 16 | Foundation Setup | Repos, infra, auth skeleton |
| 2 | May 17 – May 30 | Auth & App Shells | Login works on all 3 apps |
| 3 | May 31 – June 13 | Events Core | Event CRUD end-to-end |
| 4 | June 14 – June 27 | Registration MVP (Free) | **First breakfast meeting beta** |
| 5 | June 28 – July 11 | Check-in + Razorpay Basic | Paid flow + QR check-in |
| 6 | July 12 – July 25 | MVP Hardening | **MVP v1.0 in Production** |
| 7 | July 26 – August 8 | Sessions & Speakers | Phase 2 starts |
| 8 | August 9 – August 22 | Resources & Announcements | Real-time push live |
| 9 | August 23 – September 5 | Remote Config & Localization | Multi-brand foundation |
| 10 | September 6 – September 19 | Tickets & Payment Dashboard | **Phase 2 GA** |
| 11 | September 20 – October 3 | Refunds & Audit Viewer | Phase 3 starts |
| 12 | October 4 – October 17 | Roles, Analytics, Security | Hardening pass |
| 13 | October 18 – October 31 | Production Hardening | **Production GA** |

---

## Sprint 1 — May 3 to May 16

**Theme:** Foundation Setup
**Goal:** All three apps running locally, deployed to dev environment, with placeholder login screens.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| May 3 – May 16 | Sprint 1 | Backend | Project bootstrap | FastAPI skeleton, Poetry, Docker, repo + branching strategy, pre-commit hooks | Engineer A | Not Started | | |
| May 3 – May 16 | Sprint 1 | Backend | GCP infrastructure | Cloud Run service, Cloud SQL Postgres 16 instance, Secret Manager, Terraform base | Engineer A | Not Started | | |
| May 3 – May 16 | Sprint 1 | Backend | CI/CD pipeline | GitHub Actions → Cloud Build, dev/staging/prod environments, automated migrations | Engineer A | Not Started | | |
| May 3 – May 16 | Sprint 1 | Backend | Firebase project setup | Firebase project, Auth providers (email/Google), Admin SDK keys in Secret Manager | Engineer A | Not Started | | |
| May 3 – May 16 | Sprint 1 | Event App | Flutter project bootstrap | Flutter create, folder structure, Riverpod, GoRouter, Dio, Hive setup | Engineer B | Not Started | | |
| May 3 – May 16 | Sprint 1 | Event App | Design tokens | Color palette (dark/light), typography, spacing, theme provider | Engineer B | Not Started | | |
| May 3 – May 16 | Sprint 1 | Event App | Splash + login screen UI | Splash screen, login screen layout (no logic yet) | Engineer B | Not Started | | |
| May 3 – May 16 | Sprint 1 | Admin Portal | React project bootstrap | Vite + TS + Tailwind + shadcn/ui, ESLint, Prettier, folder structure | Engineer C | Not Started | | |
| May 3 – May 16 | Sprint 1 | Admin Portal | Design system foundation | Tailwind theme tokens, base components (Button, Input, Card, Table) | Engineer C | Not Started | | |
| May 3 – May 16 | Sprint 1 | Admin Portal | Login screen UI | Login screen layout, app shell skeleton | Engineer C | Not Started | | |

---

## Sprint 2 — May 17 to May 30

**Theme:** Auth & App Shells
**Goal:** Working end-to-end login on Event App and Admin Portal. Backend authenticates Firebase tokens and enforces roles.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| May 17 – May 30 | Sprint 2 | Backend | Auth middleware | Firebase ID token verification, request user context, role custom claims | Engineer A | Not Started | | |
| May 17 – May 30 | Sprint 2 | Backend | Users module | `users` table, `/auth/session/verify`, `/users/me` GET/PATCH | Engineer A | Not Started | | |
| May 17 – May 30 | Sprint 2 | Backend | RBAC foundation | `user_roles` table, role enum, scope check decorator | Engineer A | Not Started | | |
| May 17 – May 30 | Sprint 2 | Backend | Audit logger | `audit_logs` append-only table, audit middleware, helper utility | Engineer A | Not Started | | |
| May 17 – May 30 | Sprint 2 | Backend | Error envelope | Standardized error response, exception handlers, request validation | Engineer A | Not Started | | |
| May 17 – May 30 | Sprint 2 | Event App | Firebase Auth integration | Email + Google sign-in, token refresh, secure storage | Engineer B | Not Started | | |
| May 17 – May 30 | Sprint 2 | Event App | App shell + navigation | Bottom tab bar, route guards, theme toggle in profile | Engineer B | Not Started | | |
| May 17 – May 30 | Sprint 2 | Event App | Profile screen | View/edit name, photo, language, theme, sign out | Engineer B | Not Started | | |
| May 17 – May 30 | Sprint 2 | Event App | API client | Dio client, interceptor for token, generated types from OpenAPI | Engineer B | Not Started | | |
| May 17 – May 30 | Sprint 2 | Admin Portal | Firebase Auth integration | Login flow, role check, redirect on no-access | Engineer C | Not Started | | |
| May 17 – May 30 | Sprint 2 | Admin Portal | App shell | Sidebar, top bar with breadcrumbs + account menu, theme toggle | Engineer C | Not Started | | |
| May 17 – May 30 | Sprint 2 | Admin Portal | Profile / account page | View profile, sign out, basic settings | Engineer C | Not Started | | |
| May 17 – May 30 | Sprint 2 | Admin Portal | API client | TanStack Query setup, generated TS types, error toast handling | Engineer C | Not Started | | |

---

## Sprint 3 — May 31 to June 13

**Theme:** Events Core
**Goal:** Admin can create/publish an event; attendee can see it in the app.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| May 31 – June 13 | Sprint 3 | Backend | Events CRUD API | `events` table, `POST/GET/PATCH /events`, publish/unpublish endpoints | Engineer A | Not Started | | |
| May 31 – June 13 | Sprint 3 | Backend | Event listing API | List with filters (status, category, date), pagination | Engineer A | Not Started | | |
| May 31 – June 13 | Sprint 3 | Backend | Ticket types model | `ticket_types` table + CRUD endpoints (single type only used in MVP) | Engineer A | Not Started | | |
| May 31 – June 13 | Sprint 3 | Backend | Cloud Storage integration | Image upload signed URLs for event covers | Engineer A | Not Started | | |
| May 31 – June 13 | Sprint 3 | Event App | Event list screen | Upcoming + past tabs, card layout, pull-to-refresh, empty/error states | Engineer B | Not Started | | |
| May 31 – June 13 | Sprint 3 | Event App | Event detail screen | Banner, date/venue, description, agenda summary, sticky CTA | Engineer B | Not Started | | |
| May 31 – June 13 | Sprint 3 | Event App | Local config loader | Bundled config.json, theme + branding driven by config | Engineer B | Not Started | | |
| May 31 – June 13 | Sprint 3 | Admin Portal | Events list page | Searchable/filterable table, status chips, pagination | Engineer C | Not Started | | |
| May 31 – June 13 | Sprint 3 | Admin Portal | Event create form | Multi-step form: basics → registration type (free/paid) → review | Engineer C | Not Started | | |
| May 31 – June 13 | Sprint 3 | Admin Portal | Event edit + publish | Edit existing event, publish/unpublish action with confirmation | Engineer C | Not Started | | |
| May 31 – June 13 | Sprint 3 | Admin Portal | Cover image upload | Image picker, signed URL upload, preview | Engineer C | Not Started | | |

---

## Sprint 4 — June 14 to June 27 ⭐ MVP BETA MILESTONE

**Theme:** Registration MVP (Free Events)
**Goal:** End-to-end free registration with QR badge. Run first internal breakfast meeting.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| June 14 – June 27 | Sprint 4 | Backend | Registration API (free) | `registrations` table, `POST /events/{id}/registrations`, validation | Engineer A | Not Started | | |
| June 14 – June 27 | Sprint 4 | Backend | QR code generation | Signed unique QR token per registration, encoding strategy | Engineer A | Not Started | | |
| June 14 – June 27 | Sprint 4 | Backend | Registration list / detail | List for admins, detail for attendee, search by name/email | Engineer A | Not Started | | |
| June 14 – June 27 | Sprint 4 | Backend | Registration cancellation (free) | `DELETE /registrations/{id}`, attendee + admin scoped | Engineer A | Not Started | | |
| June 14 – June 27 | Sprint 4 | Event App | Registration form | Config-driven fields, validation, form-data preserved on error | Engineer B | Not Started | | |
| June 14 – June 27 | Sprint 4 | Event App | QR badge screen | Generated QR display, attendee name, event info, save/share | Engineer B | Not Started | | |
| June 14 – June 27 | Sprint 4 | Event App | My registrations | List of user's registrations with status | Engineer B | Not Started | | |
| June 14 – June 27 | Sprint 4 | Admin Portal | Attendee list | Per-event attendee table, search, status filter | Engineer C | Not Started | | |
| June 14 – June 27 | Sprint 4 | Admin Portal | Basic CSV export | Export registrations CSV with form-field columns | Engineer C | Not Started | | |
| June 14 – June 27 | Sprint 4 | All | First breakfast meeting beta | Internal dogfood event run on staging | All | Not Started | | **MILESTONE** |

---

## Sprint 5 — June 28 to July 11

**Theme:** Check-in + Razorpay Basic
**Goal:** Volunteer can scan QR codes; paid registrations work end-to-end with Razorpay.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| June 28 – July 11 | Sprint 5 | Backend | Check-in API | `check_ins` table, `POST /events/{id}/check-ins`, duplicate detection | Engineer A | Not Started | | |
| June 28 – July 11 | Sprint 5 | Backend | Payment gateway adapter | `PaymentGateway` interface, `RazorpayGateway` implementation | Engineer A | Not Started | | |
| June 28 – July 11 | Sprint 5 | Backend | Payment orders | `payments` table, `POST /payments/orders`, idempotency keys | Engineer A | Not Started | | |
| June 28 – July 11 | Sprint 5 | Backend | Payment verify + webhook (basic) | `POST /payments/verify`, webhook endpoint with signature check | Engineer A | Not Started | | |
| June 28 – July 11 | Sprint 5 | Event App | QR scanner (volunteer mode) | Camera scan, success/duplicate/invalid feedback states | Engineer B | Not Started | | |
| June 28 – July 11 | Sprint 5 | Event App | Razorpay checkout | SDK integration, success/failure handling, retry on failure | Engineer B | Not Started | | |
| June 28 – July 11 | Sprint 5 | Event App | Paid registration flow | Order summary screen, payment status screen, registration confirmation | Engineer B | Not Started | | |
| June 28 – July 11 | Sprint 5 | Admin Portal | Check-in dashboard (basic) | Live attendee count, % checked in, recent check-ins | Engineer C | Not Started | | |
| June 28 – July 11 | Sprint 5 | Admin Portal | Payment status display | Per-registration payment chip, basic payments list | Engineer C | Not Started | | |
| June 28 – July 11 | Sprint 5 | Admin Portal | Manual check-in | Search attendee, mark as checked-in (fallback for QR issues) | Engineer C | Not Started | | |

---

## Sprint 6 — July 12 to July 25 ⭐ MVP PRODUCTION RELEASE

**Theme:** MVP Hardening
**Goal:** MVP shipped to production app stores. First real public breakfast meeting runs on it.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| July 12 – July 25 | Sprint 6 | Backend | Push notification backend | FCM integration, send-to-event-attendees endpoint | Engineer A | Not Started | | |
| July 12 – July 25 | Sprint 6 | Backend | Security hardening (pass 1) | Rate limiting, CORS lockdown, request size limits, OWASP top-10 checklist | Engineer A | Not Started | | |
| July 12 – July 25 | Sprint 6 | Backend | Monitoring + alerts | Cloud Monitoring dashboards, Sentry integration, error budget alerts | Engineer A | Not Started | | |
| July 12 – July 25 | Sprint 6 | Backend | Bug fixes & QA | Issues from breakfast meeting beta | Engineer A | Not Started | | |
| July 12 – July 25 | Sprint 6 | Event App | Push notifications | FCM setup, in-app + system notifications | Engineer B | Not Started | | |
| July 12 – July 25 | Sprint 6 | Event App | Production polish | Loading states, error states, accessibility pass, deep links | Engineer B | Not Started | | |
| July 12 – July 25 | Sprint 6 | Event App | Store submission | iOS App Store + Google Play submission, review prep, screenshots | Engineer B | Not Started | | |
| July 12 – July 25 | Sprint 6 | Admin Portal | Production polish | Loading skeletons, empty states, keyboard shortcuts, error toasts | Engineer C | Not Started | | |
| July 12 – July 25 | Sprint 6 | Admin Portal | Export improvements | Date-range exports, registration + check-in CSV | Engineer C | Not Started | | |
| July 12 – July 25 | Sprint 6 | All | **MVP v1.0 Production Release** | Tag v1.0, deploy to prod, run first public breakfast meeting | All | Not Started | | **MILESTONE** |

---

## Sprint 7 — July 26 to August 8

**Theme:** Sessions & Speakers (Phase 2 begins)
**Goal:** Multi-session events with speakers fully supported.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| July 26 – August 8 | Sprint 7 | Backend | Sessions API | `sessions` table, CRUD endpoints, scoped to event | Engineer A | Not Started | | |
| July 26 – August 8 | Sprint 7 | Backend | Speakers API | `speakers` table, `session_speakers` join, CRUD | Engineer A | Not Started | | |
| July 26 – August 8 | Sprint 7 | Backend | Tracks & rooms | Track + room as session attributes, filter API | Engineer A | Not Started | | |
| July 26 – August 8 | Sprint 7 | Event App | Session schedule UI | Day tabs, track filter, time-grouped list, session detail | Engineer B | Not Started | | |
| July 26 – August 8 | Sprint 7 | Event App | Speaker profiles | Speakers list, speaker detail with bio + sessions, LinkedIn link | Engineer B | Not Started | | |
| July 26 – August 8 | Sprint 7 | Event App | Add to calendar | Per-session ICS export, calendar integration | Engineer B | Not Started | | |
| July 26 – August 8 | Sprint 7 | Admin Portal | Session manager | Per-event sessions table, create/edit drawer, drag-to-reorder | Engineer C | Not Started | | |
| July 26 – August 8 | Sprint 7 | Admin Portal | Speaker manager | Speakers library (reusable across events), assign to sessions | Engineer C | Not Started | | |

---

## Sprint 8 — August 9 to August 22

**Theme:** Resources & Announcements
**Goal:** Attendees receive real-time announcements; resources (PDFs, links) available per event.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| August 9 – August 22 | Sprint 8 | Backend | Resources API | `resources` table, file upload (PDF), link/video types | Engineer A | Not Started | | |
| August 9 – August 22 | Sprint 8 | Backend | Announcements API | `announcements` table + Firestore mirror for real-time push | Engineer A | Not Started | | |
| August 9 – August 22 | Sprint 8 | Backend | Push fan-out | FCM topic-per-event, send announcement → push to all registered | Engineer A | Not Started | | |
| August 9 – August 22 | Sprint 8 | Backend | Visibility rules | Public vs registered-only resources/announcements | Engineer A | Not Started | | |
| August 9 – August 22 | Sprint 8 | Event App | Resources screen | List with type icons, in-app PDF viewer, external link handling | Engineer B | Not Started | | |
| August 9 – August 22 | Sprint 8 | Event App | Announcements feed | Real-time list via Firestore listener, mark-as-read, unread badge | Engineer B | Not Started | | |
| August 9 – August 22 | Sprint 8 | Event App | Notification settings | Per-event mute/unmute, notification preferences | Engineer B | Not Started | | |
| August 9 – August 22 | Sprint 8 | Admin Portal | Resources upload | Drag-drop upload, link adder, ordering, visibility toggle | Engineer C | Not Started | | |
| August 9 – August 22 | Sprint 8 | Admin Portal | Announcements composer | Compose, schedule, preview, send-now, audience selector | Engineer C | Not Started | | |

---

## Sprint 9 — August 23 to September 5

**Theme:** Remote Config & Localization
**Goal:** Branding/modules can change without app rebuild. Localization wired (English live, others pluggable).

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| August 23 – September 5 | Sprint 9 | Backend | Config API | `GET /config`, `POST /config`, `config_versions` table, JSON schema validation | Engineer A | Not Started | | |
| August 23 – September 5 | Sprint 9 | Backend | Config publish flow | Versioning, rollback, publish to Firebase Remote Config | Engineer A | Not Started | | |
| August 23 – September 5 | Sprint 9 | Backend | Strings API | Localization strings stored, served per-locale | Engineer A | Not Started | | |
| August 23 – September 5 | Sprint 9 | Event App | Remote Config integration | Fetch + cache + fallback chain, force-refresh flag, min-version gate | Engineer B | Not Started | | |
| August 23 – September 5 | Sprint 9 | Event App | Localization framework | i18n setup, English string pack, language switcher in settings | Engineer B | Not Started | | |
| August 23 – September 5 | Sprint 9 | Event App | Dynamic theming | Apply colors/fonts/logos from Remote Config at runtime | Engineer B | Not Started | | |
| August 23 – September 5 | Sprint 9 | Admin Portal | Config editor | JSON editor with schema validation, diff view, version history | Engineer C | Not Started | | |
| August 23 – September 5 | Sprint 9 | Admin Portal | Strings editor | Translation table per locale, import/export JSON | Engineer C | Not Started | | |
| August 23 – September 5 | Sprint 9 | Admin Portal | Localization wiring | Admin Portal i18n pass, English string pack | Engineer C | Not Started | | |

---

## Sprint 10 — September 6 to September 19 ⭐ PHASE 2 GA

**Theme:** Tickets & Payment Dashboard
**Goal:** Multiple ticket types per event; full payment dashboard with reconciliation.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| September 6 – September 19 | Sprint 10 | Backend | Multiple ticket types | Quantity tracking, sale windows, member-only tickets | Engineer A | Not Started | | |
| September 6 – September 19 | Sprint 10 | Backend | Invoice generation | WeasyPrint PDF, branded template, email delivery via SendGrid | Engineer A | Not Started | | |
| September 6 – September 19 | Sprint 10 | Backend | Payment reports | Aggregations: revenue per event, per ticket type, per day | Engineer A | Not Started | | |
| September 6 – September 19 | Sprint 10 | Event App | Ticket selector UI | Select ticket type during registration, sold-out states, member gating | Engineer B | Not Started | | |
| September 6 – September 19 | Sprint 10 | Event App | Invoice viewer | View past invoices, download PDF | Engineer B | Not Started | | |
| September 6 – September 19 | Sprint 10 | Admin Portal | Payment dashboard | Per-event totals, charts, status filters, search | Engineer C | Not Started | | |
| September 6 – September 19 | Sprint 10 | Admin Portal | Ticket type manager | Create/edit ticket types, sales windows, capacity, preview | Engineer C | Not Started | | |
| September 6 – September 19 | Sprint 10 | Admin Portal | Reconciliation view | Match gateway payments vs registrations, flag mismatches | Engineer C | Not Started | | |
| September 6 – September 19 | Sprint 10 | All | **Phase 2 GA** | Tag v2.0, deploy, communications | All | Not Started | | **MILESTONE** |

---

## Sprint 11 — September 20 to October 3

**Theme:** Refunds & Audit Viewer (Phase 3 begins)
**Goal:** Admin-triggered refund flow live. Audit log viewable in Admin Portal.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| September 20 – October 3 | Sprint 11 | Backend | Refund API | `refunds` table, gateway refund integration, audit-logged | Engineer A | Not Started | | |
| September 20 – October 3 | Sprint 11 | Backend | Webhook hardening | Idempotency on `(event_id, payment_id)`, Cloud Tasks queue, dead-letter | Engineer A | Not Started | | |
| September 20 – October 3 | Sprint 11 | Backend | Reconciliation cron | Daily job: stuck payments, gateway-vs-DB diff, alerts | Engineer A | Not Started | | |
| September 20 – October 3 | Sprint 11 | Backend | Audit log search API | Filter by actor, action, entity, date; pagination | Engineer A | Not Started | | |
| September 20 – October 3 | Sprint 11 | Event App | Cancellation request UI | Request cancel/refund flow for paid events, status tracking | Engineer B | Not Started | | |
| September 20 – October 3 | Sprint 11 | Event App | Refund status notifications | Push + in-app updates as refund progresses | Engineer B | Not Started | | |
| September 20 – October 3 | Sprint 11 | Admin Portal | Refund initiation UI | Search payment, enter reason + amount, confirm dialog, status tracking | Engineer C | Not Started | | |
| September 20 – October 3 | Sprint 11 | Admin Portal | Audit log viewer | Filterable table, diff view (before/after), export | Engineer C | Not Started | | |

---

## Sprint 12 — October 4 to October 17

**Theme:** Roles, Analytics, Security
**Goal:** Role management UI, analytics dashboard, security hardening pass 2.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| October 4 – October 17 | Sprint 12 | Backend | Role management API | Assign/revoke roles, scope management, role list | Engineer A | Not Started | | |
| October 4 – October 17 | Sprint 12 | Backend | MFA for admins | Optional TOTP, recovery codes, enforcement flag | Engineer A | Not Started | | |
| October 4 – October 17 | Sprint 12 | Backend | Analytics endpoints | Registration funnel, attendance %, revenue trend, cohort | Engineer A | Not Started | | |
| October 4 – October 17 | Sprint 12 | Backend | Security hardening (pass 2) | Pen-test fixes, secret rotation, dependency audit, Cloud Armor rules | Engineer A | Not Started | | |
| October 4 – October 17 | Sprint 12 | Backend | Load testing | k6 scripts: 5k concurrent registrations, latency targets | Engineer A | Not Started | | |
| October 4 – October 17 | Sprint 12 | Event App | Accessibility pass | Screen reader labels, contrast, font scaling, keyboard nav (web) | Engineer B | Not Started | | |
| October 4 – October 17 | Sprint 12 | Event App | Performance pass | Image caching, list virtualization, cold start, bundle size | Engineer B | Not Started | | |
| October 4 – October 17 | Sprint 12 | Event App | Final UI polish | Design QA across all screens, micro-interactions, copy review | Engineer B | Not Started | | |
| October 4 – October 17 | Sprint 12 | Admin Portal | Role management UI | Users table, assign role with scope, revoke, audit-linked | Engineer C | Not Started | | |
| October 4 – October 17 | Sprint 12 | Admin Portal | Analytics dashboard | Cards + charts: registrations, revenue, attendance, top events | Engineer C | Not Started | | |
| October 4 – October 17 | Sprint 12 | Admin Portal | Config diagnostics | Active config view, version, source, fallback indicator, test mode | Engineer C | Not Started | | |

---

## Sprint 13 — October 18 to October 31 ⭐ PRODUCTION GA

**Theme:** Production Hardening
**Goal:** Final QA, runbooks, on-call setup. Public production launch.

| Sprint Dates | Sprint | App | Title | Features | Developer | Status | Review | Comments |
|---|---|---|---|---|---|---|---|---|
| October 18 – October 31 | Sprint 13 | Backend | Production runbook | Incident response, escalation, common issues, gateway outage SOP | Engineer A | Not Started | | |
| October 18 – October 31 | Sprint 13 | Backend | SLOs & alerting | API uptime 99.9%, p95 < 400ms, error budget alerts in PagerDuty | Engineer A | Not Started | | |
| October 18 – October 31 | Sprint 13 | Backend | DR drill | Backup restore test, region failover plan documented | Engineer A | Not Started | | |
| October 18 – October 31 | Sprint 13 | Backend | Final security review | Third-party review checklist, public bug bounty (optional) | Engineer A | Not Started | | |
| October 18 – October 31 | Sprint 13 | Event App | Final QA cycle | Regression testing across iOS + Android, device matrix, network conditions | Engineer B | Not Started | | |
| October 18 – October 31 | Sprint 13 | Event App | App store updates | v3.0 submission with new screenshots, release notes, listings | Engineer B | Not Started | | |
| October 18 – October 31 | Sprint 13 | Event App | User documentation | Help center articles, in-app onboarding, FAQ | Engineer B | Not Started | | |
| October 18 – October 31 | Sprint 13 | Admin Portal | Final QA cycle | Regression across role types, browsers (Chrome, Safari, Firefox, Edge) | Engineer C | Not Started | | |
| October 18 – October 31 | Sprint 13 | Admin Portal | Admin documentation | Admin guide, video walkthroughs, training material | Engineer C | Not Started | | |
| October 18 – October 31 | Sprint 13 | Admin Portal | Multi-event scaling | Pagination tuning, indexes, caching, performance verification | Engineer C | Not Started | | |
| October 18 – October 31 | Sprint 13 | All | **Production GA Release** | Tag v3.0, deploy, on-call rotation begins, launch communications | All | Not Started | | **MILESTONE** |

---

## Tracking Conventions

- **Daily standup** — async on Slack, 3 lines: yesterday / today / blockers.
- **Sprint review** — last Friday of each sprint, demo new features.
- **Sprint retro** — same Friday, 30 min, what worked / what didn't / 1 action item.
- **Status updates** — engineers update the `Status` column daily; PM/lead updates `Review` column on PR merge; `Comments` for blockers/decisions.
- **Definition of Done** — code merged + tests green + deployed to staging + acceptance criteria verified + docs updated.

---

## Risk Buffers Built In

- Sprint 6 includes intentional polish/bugfix capacity post-MVP-beta.
- Sprint 12 holds analytics + hardening that can absorb slippage from any earlier sprint.
- Sprint 13 is intentionally light on new features — pure hardening.
- If Phase 2 slips: drop Sprint 10 reconciliation view (move to post-GA backlog).
- If Phase 3 slips: drop analytics dashboard (move to post-GA), keep refund + audit + roles.

---

*Living document — update Status / Review / Comments columns through each sprint.*
