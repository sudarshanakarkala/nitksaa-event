# Event Management Platform — Requirement & Design Document

- **Version:** 1.0
- **Status:** Draft for Engineering & Product Review
- **Target Production Release:** October 2026
- **Team Size:** 3
- **Timeline:** 6 months

---

## 1. Executive Summary

This document defines the requirements, architecture, and phased delivery plan for a secure, configuration-driven **Event Management Platform** designed for professional alumni and community events — annual events, breakfast meetings, webinars, chapter events, reunions, and conferences.

The platform consists of exactly two applications:

1. **Admin Portal** — a web application for event operations, registrations, payments, audit, and reporting.
2. **Event App** — a Flutter mobile application for attendees to discover events, register, pay, view sessions, and check in via QR.

The platform is built on **Google Cloud + Firebase**, uses a **hybrid Firestore + PostgreSQL** data layer, communicates exclusively through **REST APIs**, and is fully **JSON/Remote-Config driven** so that multiple event brands can run on the same codebase.

The MVP is scoped to be operational for breakfast meetings within the first 8 weeks, with the full production platform delivered by **October 2026**.

---

## 2. Product Definition

A multi-tenant-ready event operations platform that lets organizers run professional events end-to-end — from creation, configuration, registration, and payment, through to on-site check-in, sessions, and post-event reporting — while giving attendees a clean, premium app experience.

The platform is **event-first**, not social-first. It does not include chat, social feed, marketplace, jobs, or startup networking modules.

---

## 3. Product Vision

> *"A premium, lightweight event operating system that any professional community can deploy as their own branded experience through configuration alone — without writing a single line of code."*

Core principles:

- **Secure by design** — every interaction goes through authenticated APIs.
- **Event-first** — every screen serves an event-execution purpose.
- **Configuration-driven** — branding, modules, fields, and flows are JSON-controlled.
- **Role-based** — admin, event manager, volunteer, attendee.
- **Audit-friendly** — every sensitive action is logged.
- **API-driven** — frontend and backend are strictly decoupled.
- **Maintainable by a small team** — minimal surface area, sharp scope.
- **Multi-brand ready** — one codebase, many event identities.

---

## 4. Target Users

| User Type | Description | Primary Application |
|---|---|---|
| Attendee | Alumni, community member, professional attending an event | Event App |
| Event Manager | Plans and runs events, manages registrations, sessions | Admin Portal |
| Volunteer / Check-in Staff | Performs on-site check-in via QR scanning | Event App (volunteer mode) |
| Finance Admin | Monitors payments, refunds, reconciliation | Admin Portal |
| Super Admin | Manages roles, configuration, audit logs | Admin Portal |

---

## 5. Applications in Scope

### 5.1 Admin Portal (Web)

Operations and management layer.

- Event creation and configuration
- Session and speaker management
- Registration management and exports
- Payment monitoring and refund initiation
- User and role management
- Audit log viewer
- Reports and analytics dashboard
- Configuration management (Remote Config)
- Check-in monitoring

### 5.2 Event App (Flutter — iOS & Android)

Attendee-facing execution layer.

- Login / signup
- Event discovery (list + detail)
- Registration and payment
- Session schedule and speaker bios
- QR badge generation
- QR check-in (volunteer mode)
- Resources (PDFs, links, sponsor info)
- Announcements
- Basic attendee directory
- Profile and settings

---

## 6. Explicitly Out of Scope

The following are **NOT** part of this platform:

- Public-facing marketing website / discovery portal
- Chat / direct messaging
- Social feed / posts / comments / likes
- Marketplace
- Job board
- Startup ecosystem / investor matching
- Business networking / lead exchange
- Email marketing campaigns
- Video conferencing / streaming infrastructure (only links to external streams)
- CRM features beyond attendee record-keeping

---

## 7. Customer-Facing Features (Event App)

| Feature | Phase | Description |
|---|---|---|
| Auth (email/OTP/Google) | P1 | Firebase Auth |
| Event listing | P1 | Upcoming + past events |
| Event detail | P1 | Description, date, venue, agenda summary |
| Registration | P1 | Configurable form fields |
| Payment (paid events) | P1 (basic) → P2 | Razorpay integration |
| QR badge | P1 | Generated on successful registration |
| Check-in (volunteer mode) | P1 | QR scanner |
| Sessions / schedule | P2 | Track-wise agenda |
| Speakers | P2 | Bio + photo |
| Resources | P2 | PDFs, links, slides |
| Announcements | P2 | Push + in-app |
| Attendee directory | P2 | Opt-in basic discovery |
| Profile / settings | P1 | Edit profile, notifications, language |
| Theme (dark/light) | P1 | System + manual toggle |

---

## 8. Admin / Event Manager Features (Admin Portal)

| Feature | Phase | Description |
|---|---|---|
| Admin login | P1 | Firebase Auth + role check |
| Event CRUD | P1 | Create/edit/publish events |
| Registration form builder | P1 (basic) → P2 | JSON-defined fields |
| Attendee list & search | P1 | Filter, search, export |
| CSV export | P2 | Registrations, payments, check-ins |
| Sessions & speakers | P2 | Manage schedule |
| Payment dashboard | P2 | Status, totals, reconciliation |
| Refund initiation | P3 | Manual + audit logged |
| Check-in dashboard | P2 | Live count, % checked in |
| User & role management | P3 | Assign roles |
| Audit log viewer | P3 | Filter by user/action/date |
| Remote Config editor | P2 | Update JSON live |
| Analytics | P3 | Registration funnel, attendance, revenue |
| Announcements composer | P2 | Push to event attendees |

---

## 9. Payment Features

| Capability | Phase | Notes |
|---|---|---|
| Free event support | P1 | Skip payment flow |
| Paid event support | P1 (basic) → P2 (full) | Single ticket type in P1 |
| Multiple ticket types | P2 | Early bird, regular, member |
| Razorpay integration | P1 (basic) → P2 (production) | Primary gateway |
| Payment status tracking | P1 | pending / success / failed |
| Webhook handling | P2 → P3 (hardened) | Idempotent processing |
| Refund placeholder | P2 → P3 (full flow) | Manual admin-triggered |
| Invoice / receipt | P2 | PDF generation, emailed |
| Payment audit log | P2 | Every payment action logged |
| Payment dashboard | P2 | Per-event totals, reconciliation |
| Gateway abstraction | P1 design, P3 enforced | Adapter pattern — no vendor lock-in |
| Retry / reconciliation job | P3 | Cron job for stuck payments |

**Recommended Indian gateways (placeholders, not locked):** Razorpay (primary), Cashfree (alternate), PhonePe Business (alternate). All accessed via a `PaymentGateway` adapter interface.

---

## 10. Configuration & Customization Requirements

The platform must run multiple brands from one codebase. Configuration is delivered via **Firebase Remote Config** with a **bundled local fallback** JSON.

Configurable surface:

| Category | Keys |
|---|---|
| Branding | `product_name`, `product_logo_url`, `primary_color`, `accent_color`, `secondary_color`, `background_color`, `font_family` |
| Imagery | `splash_image`, `login_banner`, `default_event_cover` |
| Navigation | `tabs[]` (each: id, label, icon, enabled, order) |
| Modules | `modules.{registration, payments, sessions, speakers, resources, announcements, directory}.enabled` |
| Categories | `event_categories[]` |
| Forms | `registration_form_fields[]` (per event override possible) |
| Payments | `payments.enabled`, `gateway`, `currency`, `ticket_types[]` |
| Roles | `role_labels.{admin, manager, volunteer, attendee}` |
| Permissions | `permission_messages.{denied, restricted}` |
| Localization | `default_language`, `supported_languages[]`, `strings.{lang}.{key}` |
| Support | `support_email`, `support_phone`, `support_url` |
| Legal | `privacy_url`, `terms_url`, `refund_policy_url` |
| Feature flags | `flags.{key: bool}` |
| Config control | `config_version`, `force_remote_config`, `min_app_version` |

**Resolution order at runtime:**
`Remote Config (latest)` → `Cached Remote Config` → `Bundled local config.json`

If `force_remote_config = true`, the app blocks until Remote Config is fetched (with timeout + retry).

---

## 11. Localization Requirements

- **Default language:** English (`en`).
- **Architecture-ready** for: Hindi (`hi`), and any future locale.
- All user-visible strings sourced from a `strings.<lang>.json` map served via Remote Config and cached locally.
- App-level language switcher in Profile → Settings.
- Date, time, and currency formatted using device locale unless overridden by config.
- No hardcoded strings in UI — enforced via lint rule and code review.
- Translations stored as flat JSON keyed by string ID, loadable per-locale.

---

## 12. Security Requirements

| Area | Requirement |
|---|---|
| Authentication | Firebase Auth (Email + OTP + Google). MFA optional for admins in P3. |
| Authorization | All API calls validated against role + event scope on the backend. |
| Transport | HTTPS / TLS 1.2+ only. HSTS enabled. |
| Database access | No direct DB access from client. All access via API. |
| Secrets | Stored in Google Secret Manager. Never in code or config files. |
| Tokens | Short-lived Firebase ID tokens; refreshed via SDK. |
| API hardening | Rate limiting, request size limits, CORS allowlist, input validation (Pydantic). |
| Payment | PCI-SAQ-A — no card data ever touches our servers. Webhooks signature-verified. |
| Audit | All sensitive actions logged with actor, target, timestamp, IP. |
| PII handling | Encryption at rest (default GCP), encryption in transit, minimal PII collection. |
| Backups | Daily automated PostgreSQL backups, 30-day retention. |
| Vulnerability mgmt | Dependabot / `pip-audit` / `npm audit` in CI. |
| Logging | No PII in application logs. Structured JSON logs. |

---

## 13. Role-Based Access Control

| Role | Scope | Key Permissions |
|---|---|---|
| `super_admin` | Platform | Manage roles, config, all events, audit logs |
| `event_manager` | Assigned events | Create/edit events, manage registrations, view payments |
| `finance_admin` | Platform | View payments, initiate refunds, export financial reports |
| `volunteer` | Assigned event | Check-in scanner only |
| `attendee` | Self | View events, register, pay, view own profile |

RBAC is enforced at **two layers**:

1. **Backend API middleware** — authoritative; rejects requests lacking required role/scope.
2. **Frontend UI** — hides controls user cannot use (UX only, never relied on for security).

Roles stored in PostgreSQL `user_roles` table; surfaced as Firebase custom claims for fast token-time checks.

---

## 14. Audit Logging Requirements

Every sensitive action is recorded as an immutable audit event.

**Tracked actions:**

- Login / logout / failed login
- Role assignment / revocation
- Event create / update / publish / unpublish / delete
- Registration create / cancel
- Payment initiated / succeeded / failed / refunded
- Config update (with diff)
- Bulk export
- Check-in (each scan)

**Audit record schema:**

```
audit_id, actor_user_id, actor_role, action, entity_type, entity_id,
before_value, after_value, ip_address, user_agent, timestamp
```

Stored in PostgreSQL (`audit_logs` table). Append-only; no UPDATE/DELETE permitted at DB role level. Viewable in Admin Portal (P3) with filters by actor, action, entity, date range.

---

## 15. Frontend Architecture

### 15.1 Event App — Flutter

- **Framework:** Flutter (latest stable)
- **State management:** Riverpod
- **Routing:** GoRouter
- **Networking:** Dio + Retrofit-style typed clients
- **Local storage:** Hive (for cached config + offline read)
- **Auth:** `firebase_auth`
- **Push:** `firebase_messaging`
- **Analytics:** `firebase_analytics` + Crashlytics
- **Theming:** Material 3 + custom design tokens from Remote Config

**Layered structure:**

```
lib/
  core/         (theme, config, networking, auth, utils)
  data/         (api clients, models, repositories)
  features/    (event, registration, payment, checkin, profile)
  ui/           (shared widgets, screens)
  app.dart
```

### 15.2 Admin Portal — React

**Recommendation: React (over Flutter Web)** — richer ecosystem for admin tooling (data tables, charts, form builders), faster iteration, better SEO/accessibility, smaller bundle.

- **Framework:** React + TypeScript + Vite
- **UI library:** shadcn/ui + Tailwind CSS
- **State / data:** TanStack Query + Zustand
- **Routing:** React Router
- **Forms:** React Hook Form + Zod
- **Charts:** Recharts
- **Tables:** TanStack Table
- **Auth:** Firebase Auth Web SDK

### 15.3 Theming

Both apps consume the same design tokens (`colors`, `typography`, `spacing`, `radii`) from Remote Config, mapped to native theme systems on each platform. Dark mode is default; light mode supported.

---

## 16. Backend Architecture

**Recommended stack: FastAPI (Python 3.12) on Cloud Run.**

Rationale: clean async API-first design, Pydantic validation matches our config-heavy nature, fast iteration for a 3-person team, excellent OpenAPI generation for client SDKs, mature SQLAlchemy + asyncpg.

### 16.1 Components

| Component | Tech |
|---|---|
| API service | FastAPI on Cloud Run |
| Auth verification | Firebase Admin SDK |
| ORM | SQLAlchemy 2.0 (async) + Alembic migrations |
| Background jobs | Cloud Tasks + Cloud Scheduler |
| File storage | Google Cloud Storage |
| Secrets | Google Secret Manager |
| Email | SendGrid / Resend (abstracted) |
| Push | Firebase Cloud Messaging |
| PDF generation | WeasyPrint (invoices) |
| Logging | Cloud Logging (structured JSON) |
| Monitoring | Cloud Monitoring + Sentry |

### 16.2 Layered Architecture

```
api/         (FastAPI routers, request/response models)
services/    (business logic)
repositories/(data access — Postgres + Firestore)
adapters/    (payments, email, push, storage)
models/      (SQLAlchemy + Pydantic)
core/        (auth, config, errors, middleware)
jobs/        (scheduled & queued workers)
```

### 16.3 Deployment

- Cloud Run (autoscale 0→N)
- Cloud Build CI/CD with GitHub triggers
- Three environments: `dev`, `staging`, `prod`
- Infrastructure as Code: Terraform

---

## 17. API-First Communication Design

- **All** frontend-backend communication is via versioned REST APIs (`/api/v1/...`).
- **No** direct Firestore or PostgreSQL access from clients (Firestore client SDK is used **only** for Remote Config and FCM, not for app data).
- OpenAPI 3.1 spec auto-generated from FastAPI; published to `/docs` (admin-protected in prod).
- Typed client SDKs generated for Flutter (`openapi-generator`) and React (`openapi-typescript`).
- Every endpoint:
  - Requires Firebase ID token in `Authorization: Bearer <token>`.
  - Validates role and scope.
  - Returns standardized error envelope: `{ "error": { "code": "...", "message": "...", "details": {...} } }`.
  - Supports pagination via `?limit=&cursor=`.
- Idempotency keys required on all `POST /payments/*` and `POST /registrations` endpoints.

---

## 18. Database Architecture

### 18.1 Hybrid Recommendation

| Data | Store | Why |
|---|---|---|
| Events, sessions, speakers | **PostgreSQL** | Relational, transactional, exportable |
| Registrations | **PostgreSQL** | Strong consistency, joins, reporting |
| Payments | **PostgreSQL** | ACID, auditability, financial integrity |
| Attendees / users | **PostgreSQL** | Relational with roles, registrations |
| Check-ins | **PostgreSQL** | Audit trail, time-series queries |
| Audit logs | **PostgreSQL** | Append-only, queryable by admin |
| User profiles (auth) | **Firebase Auth** | Identity provider |
| Roles / claims | **PostgreSQL** (source) + **Firebase Custom Claims** (cache) | Fast token check |
| Remote configuration | **Firebase Remote Config** | Dynamic, no deploy needed |
| Announcements (live) | **Firestore** | Real-time push to app |
| Live check-in counters | **Firestore** | Real-time admin dashboard |
| Static assets | **Cloud Storage** | Images, PDFs, logos |

**Principle:** PostgreSQL is the system of record for all business data. Firestore is used **only** where its real-time push capability adds clear value.

### 18.2 PostgreSQL Setup

- Cloud SQL for PostgreSQL 16
- Connection pooling via PgBouncer
- Daily automated backups, point-in-time recovery
- Read replica added in P3 for analytics queries

---

## 19. Google Cloud / Firebase Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                         CLIENTS                               │
│  ┌─────────────────────┐      ┌─────────────────────┐         │
│  │  Event App (Flutter)│      │ Admin Portal (React)│         │
│  └──────────┬──────────┘      └──────────┬──────────┘         │
│             │                              │                  │
│             │  Firebase Auth ID token      │                  │
└─────────────┼──────────────────────────────┼──────────────────┘
              │                              │
              ▼                              ▼
        ┌──────────────────────────────────────────┐
        │   API Gateway / Cloud Load Balancer      │
        └──────────────────────┬───────────────────┘
                               │
                               ▼
                ┌────────────────────────────┐
                │   FastAPI on Cloud Run     │
                └──────┬─────────────┬───────┘
                       │             │
        ┌──────────────┘             └──────────────┐
        ▼                                            ▼
  ┌────────────┐                          ┌──────────────────┐
  │ Cloud SQL  │                          │  Firestore       │
  │ Postgres   │                          │ (config, live)   │
  └────────────┘                          └──────────────────┘

  Other services consumed by backend:
  - Firebase Auth (token verification)
  - Firebase Cloud Messaging (push)
  - Firebase Remote Config (config delivery)
  - Cloud Storage (assets, invoices)
  - Secret Manager (gateway keys)
  - Cloud Tasks (async jobs)
  - Cloud Scheduler (cron)
  - Cloud Logging / Monitoring / Sentry
```

---

## 20. Payment Architecture

### 20.1 Flow (Razorpay reference)

```
1. Attendee taps "Register" on a paid event.
2. App → POST /api/v1/registrations (status: pending_payment).
3. Backend → POST /api/v1/payments/orders → creates Razorpay order, returns order_id.
4. App opens Razorpay checkout SDK with order_id.
5. User pays. Razorpay returns payment_id + signature to app.
6. App → POST /api/v1/payments/verify (payment_id, signature, order_id).
7. Backend verifies signature → marks payment success → confirms registration → issues QR badge → emails invoice.
8. Razorpay webhook → POST /api/v1/payments/webhook → idempotent reconciliation safety net.
```

### 20.2 Gateway Abstraction

```python
class PaymentGateway(Protocol):
    def create_order(self, amount, currency, metadata) -> Order: ...
    def verify_payment(self, payload) -> VerifiedPayment: ...
    def refund(self, payment_id, amount) -> Refund: ...
    def verify_webhook(self, headers, body) -> WebhookEvent: ...
```

Implementations: `RazorpayGateway`, `CashfreeGateway`, `PhonePeGateway`. Selected via config key `payments.gateway`.

### 20.3 Webhook Hardening (P3)

- Signature verification using gateway secret from Secret Manager.
- Idempotency: `(event_id, payment_id)` uniqueness guarded in DB.
- Retry-safe processing via Cloud Tasks queue.
- Dead-letter queue for repeated failures, alerted to ops.

### 20.4 Audit & Refunds

- Every payment state transition logged to `audit_logs`.
- Refunds initiated only by `finance_admin` or `super_admin`.
- Refund record links back to original payment with reason and approver.

---

## 21. UI / UX Theme and Design System

### 21.1 Design Direction

Premium, calm, professional. Inspired by **Linear, Stripe, and Apple**. Not flashy. Not social-media-like. The product should feel like a well-engineered operating system for events.

### 21.2 Color Palette (Dark — Default)

| Token | Hex | Usage |
|---|---|---|
| `bg/base` | `#0B0D10` | App background |
| `bg/surface` | `#14171C` | Cards, sheets |
| `bg/elevated` | `#1B1F26` | Modals, popovers |
| `border/subtle` | `#252A33` | Dividers |
| `text/primary` | `#F5F7FA` | Headings, body |
| `text/secondary` | `#9AA3B2` | Captions, meta |
| `text/muted` | `#6B7380` | Disabled |
| `accent/primary` | `#5B8DEF` | CTAs, links |
| `accent/primary-hover` | `#3B6FD9` | Hover |
| `success` | `#3FB950` | Confirmed |
| `warning` | `#D29922` | Pending |
| `danger` | `#F85149` | Errors, refund |

### 21.3 Color Palette (Light)

| Token | Hex |
|---|---|
| `bg/base` | `#FFFFFF` |
| `bg/surface` | `#F7F8FA` |
| `bg/elevated` | `#FFFFFF` |
| `border/subtle` | `#E5E8EC` |
| `text/primary` | `#0E1117` |
| `text/secondary` | `#4A5260` |
| `accent/primary` | `#2563EB` |

### 21.4 Typography

- **Primary font:** Inter (UI), system fallback.
- **Display font:** Inter Display or Söhne (optional, premium feel).
- **Mono:** JetBrains Mono (admin code/IDs).

| Style | Size / Weight |
|---|---|
| Display | 32 / 700 |
| H1 | 24 / 700 |
| H2 | 20 / 600 |
| H3 | 18 / 600 |
| Body | 15 / 400 |
| Caption | 13 / 400 |
| Micro | 11 / 500 / uppercase / tracked |

### 21.5 Spacing System

8-point grid: `4, 8, 12, 16, 20, 24, 32, 40, 48, 64`. All paddings, margins, and gaps snap to these values.

### 21.6 Cards

- Radius: `16px` (Event App), `12px` (Admin Portal)
- Background: `bg/surface`
- Border: `1px solid border/subtle`
- Shadow: none in dark, subtle `0 1px 2px rgba(0,0,0,0.04)` in light
- Padding: `20px`

### 21.7 Buttons

- Primary: filled, accent color, 44px height (mobile), 36px (web)
- Secondary: outlined, `border/subtle`
- Tertiary: text-only with accent color
- Radius: `10px`
- States: hover, focus (2px ring), pressed, disabled, loading

### 21.8 Navigation

- **Event App:** Bottom tab bar (3–5 tabs from config), top app bar for context.
- **Admin Portal:** Left sidebar with collapsible groups, top bar for breadcrumbs and account.

### 21.9 Admin Portal UI Style

Dense but uncluttered. Data tables with inline actions, sticky headers, server-side pagination. Cmd-K command palette in P3.

### 21.10 Event App UI Style

Spacious, image-forward on event detail. Sticky CTA on registration screens. Large tap targets (≥44pt).

---

## 22. Core User Flows

### 22.1 Event Discovery

```
Open app → Auth check → Home tab → Upcoming events list
→ Tap event → Event detail (banner, date, venue, agenda summary, CTA)
```

### 22.2 Registration (Free Event)

```
Event detail → "Register" → Form (config-driven fields) → Submit
→ Confirmation screen with QR badge → Email confirmation
```

### 22.3 Registration + Payment (Paid Event)

```
Event detail → "Register" → Form → Continue → Order summary
→ Razorpay checkout → Success → QR badge issued → Invoice emailed
                       ↓ Failure
                    Retry / cancel → Registration stays pending_payment
```

### 22.4 QR Check-in

```
Volunteer logs in → "Check-in" mode (event-scoped)
→ Camera scans QR → Backend validates → Success/duplicate/invalid feedback
→ Live count updates in admin dashboard
```

### 22.5 Admin Event Creation

```
Admin Portal → Events → "+ New Event" → Step 1: Basics (name, date, venue, category)
→ Step 2: Registration (free/paid, ticket types, form fields)
→ Step 3: Sessions (optional in P1) → Step 4: Review → Save Draft / Publish
```

### 22.6 Refund / Cancellation (Placeholder → P3)

```
Admin Portal → Payments → Search payment → "Initiate Refund"
→ Reason + amount → Confirm → Gateway refund API → Webhook confirms
→ Audit log entry → Attendee notified
```

---

## 23. Data Models / Collections / Tables

### 23.1 PostgreSQL Tables (key fields only)

**`users`**
`id, firebase_uid, email, phone, full_name, photo_url, created_at, updated_at, deleted_at`

**`user_roles`**
`id, user_id, role, scope_type (global|event), scope_id, granted_by, granted_at`

**`events`**
`id, name, slug, category, description, cover_image_url, start_at, end_at, timezone, venue_name, venue_address, status (draft|published|completed|cancelled), is_paid, max_capacity, created_by, created_at, updated_at`

**`ticket_types`**
`id, event_id, name, price, currency, quantity, sales_start_at, sales_end_at, active`

**`sessions`**
`id, event_id, title, description, start_at, end_at, track, room, created_at`

**`session_speakers`** (join)
`session_id, speaker_id, role`

**`speakers`**
`id, name, title, company, bio, photo_url, linkedin_url, created_at`

**`registrations`**
`id, event_id, user_id, ticket_type_id, status (pending_payment|confirmed|cancelled|refunded), form_data (jsonb), qr_code, registered_at, cancelled_at`

**`payments`**
`id, registration_id, gateway, gateway_order_id, gateway_payment_id, amount, currency, status (pending|success|failed|refunded), webhook_verified, raw_payload (jsonb), created_at, updated_at`

**`refunds`**
`id, payment_id, amount, reason, initiated_by, gateway_refund_id, status, created_at`

**`check_ins`**
`id, registration_id, event_id, scanned_by, scanned_at, location, device_info`

**`resources`**
`id, event_id, title, type (pdf|link|video), url, visibility (public|registered), created_at`

**`announcements`** (mirrored to Firestore for realtime push)
`id, event_id, title, body, audience, sent_at, sent_by`

**`audit_logs`**
`id, actor_user_id, actor_role, action, entity_type, entity_id, before, after, ip, user_agent, created_at`

**`config_versions`**
`id, version, payload (jsonb), published_by, published_at`

### 23.2 Firestore Collections

| Collection | Purpose |
|---|---|
| `live_announcements/{eventId}/items` | Real-time push to event app |
| `live_checkin_stats/{eventId}` | Live counter for admin dashboard |
| `remote_config_overrides/{brandId}` | Per-brand dynamic config |

---

## 24. API Modules

| Module | Sample Endpoints |
|---|---|
| Auth | `POST /auth/session/verify`, `POST /auth/logout` |
| Users | `GET /users/me`, `PATCH /users/me`, `GET /users/{id}` (admin) |
| Roles | `GET /roles`, `POST /roles/assign`, `DELETE /roles/{id}` |
| Events | `GET /events`, `GET /events/{id}`, `POST /events`, `PATCH /events/{id}`, `POST /events/{id}/publish` |
| Sessions | `GET /events/{id}/sessions`, `POST /events/{id}/sessions`, `PATCH /sessions/{id}` |
| Speakers | `GET /speakers`, `POST /speakers`, `PATCH /speakers/{id}` |
| Registrations | `POST /events/{id}/registrations`, `GET /events/{id}/registrations`, `DELETE /registrations/{id}` |
| Payments | `POST /payments/orders`, `POST /payments/verify`, `POST /payments/webhook`, `POST /payments/{id}/refund` |
| Check-in | `POST /events/{id}/check-ins`, `GET /events/{id}/check-ins/stats` |
| Resources | `GET /events/{id}/resources`, `POST /events/{id}/resources` |
| Announcements | `POST /events/{id}/announcements`, `GET /events/{id}/announcements` |
| Reports | `GET /reports/registrations.csv`, `GET /reports/payments.csv`, `GET /reports/check-ins.csv` |
| Config | `GET /config`, `POST /config` (admin), `GET /config/versions` |
| Audit | `GET /audit-logs` (admin) |

All endpoints follow `/api/v1/...`, return JSON, and use the standard error envelope.

---

## 25. Phase 1 — MVP Scope

**Goal:** Operational for breakfast meetings. Small attendee count (≤200), single-brand, mostly free events with basic paid support.

| Capability | Included |
|---|---|
| Firebase Auth (email + Google) | ✅ |
| Local JSON config (bundled, no Remote Config yet) | ✅ |
| Event listing + detail (Event App) | ✅ |
| Basic registration form (fixed fields + 2 custom) | ✅ |
| Free event registration | ✅ |
| Paid event — basic Razorpay integration | ✅ |
| QR badge generation | ✅ |
| QR check-in (volunteer mode) | ✅ |
| Admin Portal: login, event CRUD, attendee list, basic CSV export | ✅ |
| Payment status display (admin) | ✅ |
| Dark theme | ✅ |
| Light theme | ✅ |
| Push notifications (basic) | ✅ |
| Audit log (write-only, no UI viewer yet) | ✅ |

**Excluded from MVP:** Sessions, speakers, resources, announcements, attendee directory, refund UI, advanced analytics, Remote Config UI, role management UI, multi-brand switching.

---

## 26. Phase 2 — Core Platform

| Capability | Notes |
|---|---|
| Sessions & schedule | Track-based agenda |
| Speakers | Bio + photo |
| Resources module | PDFs, links |
| Announcements | Push + in-app, Firestore-backed |
| Multiple ticket types | Early bird, regular, member |
| Production Razorpay flow | Webhooks + invoice PDF |
| Payment dashboard | Per-event totals, reconciliation |
| Check-in dashboard | Live counts, % attended |
| Registration/payment exports | CSV |
| Remote Config | JSON push without app release |
| Localization foundation | English fully wired; ready for `kn`, `hi` |
| Form builder (basic) | Admin can add/remove fields per event |

---

## 27. Phase 3 — Production Platform

| Capability | Notes |
|---|---|
| Refund flow (full) | Admin-triggered, audit-logged, gateway-verified |
| Webhook hardening | Idempotency, dead-letter queue, alerts |
| Audit log viewer (Admin Portal) | Filter by actor, action, date |
| User & role management UI | Assign/revoke roles |
| Config diagnostics | Show active config, version, source, fallback status |
| Analytics dashboard | Registration funnel, attendance rates, revenue |
| Multi-event scaling | Pagination, indexes, caching |
| Multi-brand config | Per-brand Remote Config templates |
| MFA for admins | Optional but available |
| Security hardening | Pen-test fixes, rate limit tuning, OWASP review |
| Load & soak testing | 5k concurrent registrations target |
| Production runbook + on-call | Alerting, dashboards, SLOs |

---

## 28. 6-Month Release Plan — Ending October 2026

Assumes start of **May 2026**, production release **end of October 2026**.

| Month | Sprint Focus | Milestone |
|---|---|---|
| **May 2026** | Foundations: repos, CI/CD, Cloud Run, Cloud SQL, Firebase project, design tokens, auth | Auth working in both apps; skeleton screens deployed |
| **June 2026** | MVP build: events, registrations, free flow, QR badge, basic admin | **MVP usable for first breakfast meeting (mid-June)** |
| **July 2026** | MVP polish + paid flow: Razorpay basic, payment status, admin export, push | **MVP v1.0 in production for live events** |
| **August 2026** | Phase 2 core: sessions, speakers, resources, announcements, Remote Config, localization wiring, payment dashboard | Phase 2 beta with internal events |
| **September 2026** | Phase 2 finish + Phase 3 start: ticket types, invoice PDFs, exports, audit viewer, role management UI, refund flow | Phase 2 GA; Phase 3 features in staging |
| **October 2026** | Hardening: webhook hardening, analytics, security review, load testing, runbook, docs | **Production GA — October 2026** |

---

## 29. Team Allocation for 3 People

| Role | Primary Ownership | Secondary |
|---|---|---|
| **Engineer A — Backend / Platform Lead** | FastAPI, PostgreSQL, payments, audit, security, DevOps (Cloud Run, Terraform, CI/CD), API design | Admin Portal API integration |
| **Engineer B — Mobile / Event App Lead** | Flutter Event App (all features), Firebase Auth/FCM/RemoteConfig integration, QR flows, theming | Push notification backend hooks |
| **Engineer C — Admin Portal / Frontend Lead** | React Admin Portal, design system implementation, dashboards, exports, role/audit UIs | Localization tooling, content for QA |

**Shared responsibilities:** product spec refinement, code review (every PR has 1 reviewer), testing, on-call rotation post-launch.

**Working norms:**
- 2-week sprints
- Weekly demo to stakeholders
- Friday cut, Monday deploy to staging
- Production deploys gated on green CI + manual approval

---

## 30. Risks and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Scope creep (chat, social, etc.) | High | High | Lock scope to this document; log requests to backlog, not sprint |
| Payment gateway outage | Med | High | Gateway abstraction; manual reconciliation runbook; alternate gateway ready |
| Webhook reliability | Med | High | Cloud Tasks retry, idempotency, dead-letter queue, daily reconciliation cron |
| 3-person team capacity | High | Med | Strict P1/P2/P3 phasing; reuse open-source heavily; no premature abstraction |
| Config-driven flexibility leading to QA explosion | Med | Med | Config schema validation; snapshot tests per active brand config |
| First production event failure | Low | High | Soft launch on small breakfast meeting; on-site engineer present |
| Firebase vendor lock-in | Med | Low | Auth and Remote Config are easy to swap; business data lives in Postgres |
| Security incident (PII / payment) | Low | Critical | OWASP checklist, Secret Manager, MFA for admins (P3), pen-test before GA |
| Slow Cloud Run cold starts | Med | Low | Min-instances=1 in prod; lightweight container; warm-up endpoint |
| Translation backlog | Low | Low | English-only at launch; architecture-ready for late additions |

---

## 31. Success Metrics

**Operational**
- Time to create + publish a new event: **< 5 minutes**
- Time to check in an attendee: **< 2 seconds per scan**
- Registration form completion rate: **> 85%**
- Payment success rate: **> 97%**

**Reliability**
- API uptime: **99.9%** monthly
- p95 API latency: **< 400ms**
- Crash-free sessions (Event App): **> 99.5%**

**Adoption**
- Number of events run on platform per quarter
- Number of registrations per event
- % of attendees checked in via QR (target > 90%)

**Quality**
- Zero P1 security incidents
- < 1 P2 bug per 100 registrations
- Audit log coverage: 100% of sensitive actions

---

## 32. Final MVP Acceptance Criteria

The MVP is accepted when **all** of the following are demonstrably true on production:

1. A new admin can sign in to the Admin Portal and create a new event in under 5 minutes.
2. An attendee can install the Event App, sign in, view the event, register (free), and receive a QR badge.
3. An attendee can complete a paid registration end-to-end via Razorpay and see payment status reflected in both the app and Admin Portal.
4. A volunteer can scan an attendee's QR badge and see immediate confirmation; duplicates and invalid codes are handled.
5. The Admin Portal shows the live attendee list with search and CSV export.
6. All API calls require a valid Firebase ID token; no client touches the database directly.
7. Sensitive actions (login, event create/update, payment, check-in) appear in the `audit_logs` table.
8. Branding (name, logo, primary color) can be changed by editing the bundled `config.json` and rebuilding — no code changes required.
9. Dark mode and light mode both render correctly across all MVP screens.
10. The platform has successfully run **at least one live breakfast meeting** with real attendees, with no P1 issues.

---

*End of document.*
