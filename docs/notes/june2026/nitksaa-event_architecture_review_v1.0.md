# NITKSAA Event App — Architecture Review v1.0

**Version:** 1.0  
**Status:** Architecture Review Draft  
**Prepared For:** NITKSAA Event App Development Team  
**Prepared By:** Sudarshana Karkala / Event App Team  
**Date:** June 2026  

---

## 1. Executive Summary

The NITKSAA Event App is the dedicated event-management system for NITKSAA and alumni-community events. It is not an isolated product. It is the third major application in the broader NITKSAA digital ecosystem, alongside the existing Admin Portal and Website.

The Event App architecture must reuse the existing NITKSAA identity, infrastructure, backend conventions, frontend patterns, database ownership model, and deployment approach wherever practical.

The June MVP focuses on:

- Authentication foundation
- Event creation
- Public event listing
- Event detail view
- Registration
- Confirmation email
- Attendee list and export

The June MVP deliberately avoids unnecessary expansion into payments, advanced attendee types, discounts, QR check-in, sessions, speakers, sponsors, announcements, and analytics dashboards unless explicitly approved for the MVP.

---

## 2. Architecture Objectives

The architecture must satisfy the following goals:

1. Keep Event App aligned with the NITKSAA Website and Admin Portal.
2. Reuse the same Firebase identity anchor.
3. Keep all frontend/backend communication API-based.
4. Avoid direct database access from frontend apps.
5. Keep event business data in `events_db`.
6. Keep alumni identity data in `alumni_db`.
7. Use stable API contracts because the Website will later consume Event APIs directly.
8. Preserve operational auditability.
9. Keep implementation understandable for a small development team.
10. Avoid premature microservices or overengineering.

---

## 3. Existing Ecosystem Context

The NITKSAA ecosystem contains three major applications:

| Application | Purpose | Status |
|---|---|---|
| Admin Portal | Internal operations and alumni data management | Existing production system |
| Website | Public and member-facing community hub | Existing / active development |
| Event App | Event lifecycle management | New / in development |

All three systems should share:

- Firebase project
- Firebase UID identity anchor
- Cloud SQL infrastructure
- API-first interaction model
- Consistent auth/JWT philosophy
- Consistent UX tone and theme direction

---

## 4. Approved Repository Structure

The Event App implementation should remain inside the same `nitksaa-event` repository:

```text
nitksaa-event/
├── backend/                       # FastAPI backend
├── apps/
│   └── event_app/                 # Flutter attendee app
├── admin/
│   └── event_admin/               # React admin portal
└── docs/
```

No separate repository should be created for the event admin portal at this stage.

---

## 5. System Context

```text
                         ┌─────────────────────┐
                         │      Firebase       │
                         │  Authentication     │
                         └──────────┬──────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
┌─────────────▼─────────────┐ ┌─────▼──────────────┐ ┌────▼───────────────┐
│ Flutter Event App          │ │ React Event Admin  │ │ NITKSAA Website    │
│ Attendee-facing            │ │ Staff operations   │ │ Future event views │
└─────────────┬─────────────┘ └─────┬──────────────┘ └────┬───────────────┘
              │                     │                     │
              └─────────────────────┼─────────────────────┘
                                    │
                         ┌──────────▼──────────┐
                         │ FastAPI Event API   │
                         │ /api/v1/...         │
                         └──────────┬──────────┘
                                    │
       ┌────────────────────────────┼────────────────────────────┐
       │                            │                            │
┌──────▼───────┐             ┌──────▼───────┐             ┌──────▼───────┐
│ events_db    │             │ alumni_db    │             │ website_db   │
│ Event data   │             │ Identity     │             │ Website data │
└──────────────┘             └──────────────┘             └──────────────┘
```

---

## 6. Identity Architecture

### 6.1 Primary Identity Anchor

The system must use the same Firebase project as the existing Website and Admin Portal.

Primary identity fields:

| Field | Purpose |
|---|---|
| `firebase_uid` | Stable authentication identity |
| `ref_id` | Value reference to `alumni_db.alumni.alumni_id` |
| `user_type` | `alumni` or `other` |
| `is_admin` | Admin flag for Alpha |
| `permissions[]` | Future scoped capabilities |

### 6.2 Rules

- Do not create a new Firebase project.
- Do not create a second identity system.
- Do not create a new global role model for Alpha.
- Do not store full alumni profile data in `events_db`.
- Use `ref_id` as a value reference only.
- No cross-database foreign keys.

---

## 7. Authentication Architecture

### 7.1 Approved Authentication Flow

```text
Flutter / React Client
        │
        ▼
Firebase Sign-In
        │
        ▼
Firebase ID Token
        │
        ▼
POST /api/v1/auth/firebase
        │
        ▼
Event Backend verifies Firebase token
        │
        ▼
Event Backend upserts event_users
        │
        ▼
Event Backend returns internal JWT
        │
        ▼
Client stores Event JWT
        │
        ▼
Client calls protected APIs using:
Authorization: Bearer <event_jwt>
```

### 7.2 Important Rules

- Firebase ID token is used only for login/token exchange.
- Backend APIs must not verify Firebase token on every request.
- Internal Event JWT is used for protected Event APIs.
- JWT field names must remain aligned with Website-style contract.
- Backend JWT validation is the final source of authenticated state.
- Frontend login alone is not sufficient.

### 7.3 JWT Claims for Event App

Recommended Alpha JWT shape:

```json
{
  "firebase_uid": "firebase-user-id",
  "ref_id": "ALUMNI-000001",
  "user_type": "alumni",
  "is_admin": true,
  "permissions": [],
  "exp": 1234567890
}
```

---

## 8. Authorization Architecture

### 8.1 Alpha Admin Rule

For Alpha / June MVP:

```text
is_admin = true
```

is sufficient for Event Admin access.

### 8.2 Deferred Authorization

The following are deferred:

- Scoped event coordinator permissions
- Chapter-scoped event managers
- Volunteer permissions
- Finance permissions
- Super-admin hierarchy
- Role delegation UI

### 8.3 Backend Enforcement

All protected actions must be enforced by backend dependencies.

UI hiding is not security.

Example protected actions:

- Create event
- Edit event
- Publish event
- Cancel event
- View attendees
- Export attendees

---

## 9. Database Architecture

### 9.1 Database Ownership

| Database | Ownership |
|---|---|
| `alumni_db` | Alumni identity and profile source of truth |
| `website_db` | Website/community data |
| `events_db` | Event business data |

### 9.2 Event DB Tables

Current Week 1 migrations define:

- `events`
- `sessions`
- `event_users`
- `event_members`
- `registrations`
- `check_ins`
- `event_content`
- `event_audit_log`
- `notifications`
- `notification_preferences`

### 9.3 Core Rules

- Store event-specific data only in `events_db`.
- Store `ref_id` as an alumni reference, not a foreign key.
- Do not duplicate alumni name, branch, year unless required as a historical snapshot.
- Hydrate current alumni information from `alumni_db` using service functions.
- Do not query protected databases directly from frontend apps.

---

## 10. Backend Architecture

### 10.1 Backend Stack

- FastAPI
- PostgreSQL
- asyncpg currently in Event backend
- Firebase Admin SDK
- Internal JWT
- Raw SQL / repository style
- API-first contract

### 10.2 Recommended Backend Structure

```text
backend/
├── app/
│   ├── api/
│   │   ├── auth.py
│   │   ├── health.py
│   │   ├── events.py
│   │   ├── registrations.py
│   │   ├── attendees.py
│   │   └── dev_diagnostics.py
│   ├── core/
│   ├── middleware/
│   ├── models/
│   ├── schemas/
│   ├── services/
│   ├── repositories/
│   ├── database.py
│   ├── config.py
│   └── main.py
└── migrations/
    └── events_db/
```

### 10.3 Backend API Principles

- All APIs must be under `/api/v1`.
- Use FastAPI `HTTPException`.
- Error format: `{ "detail": "message" }`.
- Success format: `{ "status": "ok", ... }` where useful.
- Public event APIs must not expose protected join links.
- Protected APIs require `Authorization: Bearer <event_jwt>`.
- Admin APIs require `is_admin`.

---

## 11. API Design Standards

### 11.1 HTTP Status Rules

| Case | Status |
|---|---|
| Invalid/missing auth | 401 |
| Authenticated but not allowed | 403 |
| Missing resource | 404 |
| Duplicate/conflict state | 409 |
| Validation error | 422 |
| Server error | 500 |

### 11.2 Public Event API Contract

The public APIs must be stable because the Website will later consume them directly.

#### `GET /api/v1/events`

Public. Returns published events only.

Must exclude protected join links.

#### `GET /api/v1/events/{slug}`

Public. Returns event details for a published event.

Must use `slug`, not `event_id`, for public URLs.

### 11.3 Admin Event APIs

Admin-only.

```http
POST   /api/v1/events
PATCH  /api/v1/events/{event_id}
DELETE /api/v1/events/{event_id}
PATCH  /api/v1/events/{event_id}/status
```

### 11.4 Registration APIs

Authenticated alumni-only for June MVP.

```http
POST /api/v1/events/{event_id}/register
GET  /api/v1/events/{event_id}/my-registration
```

### 11.5 Attendee APIs

Admin-only.

```http
GET /api/v1/events/{event_id}/attendees
GET /api/v1/events/{event_id}/attendees/export
```

---

## 12. June MVP Scope

### 12.1 In Scope

For June MVP:

- Auth foundation
- Event creation
- Event listing
- Event detail
- Event publishing
- Event registration
- Confirmation email
- Attendee list
- Attendee CSV export
- Staff walkthrough document
- Known issues list
- Local/staging demo

### 12.2 Explicitly Deferred

Deferred unless separately approved:

- Payments
- Refunds
- Discounts
- Coupons
- Multi-step event wizard
- Complex attendee-type configuration
- Guest/family co-registration
- QR check-in
- Offline check-in
- Sessions/tracks
- Speaker management
- Sponsor management
- Announcements
- Push notifications
- Analytics dashboards
- Mobile-responsive admin polish beyond basic usability

---

## 13. Weekly MVP Delivery Plan

### Week 1 — Foundation

Status: Complete.

Delivered:

- Flutter authentication
- Backend authentication
- JWT exchange
- Session persistence
- Developer Diagnostics
- Database migrations
- React Admin foundation
- Request logging
- CORS
- Local verification guide

### Week 2 — Event Creation and Public Listing

Goal:

```text
Staff can create events.
Public can browse events.
Public can view event details.
```

Deliverables:

- Event CRUD APIs
- Public listing API
- Event detail API
- Publish/unpublish API
- Admin event creation form
- Admin event list
- Flutter public event list
- Flutter event detail
- Event diagnostics

### Week 3 — Registration and Confirmation

Goal:

```text
Alumni can register.
Confirmation email sent.
Join link visible after registration.
```

Deliverables:

- Register API
- My registration API
- Capacity enforcement
- Duplicate guard
- Confirmation screen
- Confirmation email
- Protected virtual link logic

### Week 4 — Attendees and Export

Goal:

```text
Admin can manage attendees.
System is demo-ready.
```

Deliverables:

- Attendee list API
- Search/filter attendee list
- CSV export
- Admin attendee page
- Error and empty states
- Known issues list
- Staff walkthrough

---

## 14. Frontend Architecture — Flutter Event App

### 14.1 Responsibility

The Flutter app is the attendee/user-facing app.

It handles:

- Public event listing
- Event detail
- Login
- Registration
- Confirmation
- My event state
- Developer diagnostics

### 14.2 Flutter Rules

- No direct DB access.
- All data via backend APIs.
- Store backend JWT securely/local storage.
- Do not expose Firebase ID token in UI.
- Use auth state plus backend `/auth/me` validation.
- Public event listing should not require login.
- Registration CTA should navigate to login if unauthenticated.

### 14.3 Week 2 Screens

```text
EventListScreen
EventDetailScreen
```

Event list:

- Upcoming tab
- Past tab
- Event cards
- Type badge
- Capacity indicator
- Registration status

Event detail:

- Title
- Description
- Date/time/timezone
- Location or Online indicator
- Registration CTA
- Join link hidden until registered

---

## 15. Frontend Architecture — React Event Admin

### 15.1 Responsibility

The React Event Admin Portal is for staff and authorized admins.

It handles:

- Event creation
- Event editing
- Publish/unpublish
- Attendee list
- Export
- Future operations

### 15.2 Admin Rules

- Admin UI must call backend APIs only.
- Admin UI must not enforce security alone.
- Backend must validate admin permissions.
- Use NITKSAA website visual style.
- Keep UI simple for June MVP.

### 15.3 Week 2 Admin Screens

```text
EventsPage
EventCreateForm
EventEditForm
EventListTable
```

Fields:

- Title
- Tagline
- Description
- Start date/time
- End date/time
- Timezone
- Physical/virtual
- Venue
- Map URL
- Virtual URL
- Capacity
- Registration opens
- Registration closes
- Thumbnail/banner URL optional
- Status

---

## 16. Backend Design Flows

### 16.1 Create Event Flow

```text
Admin Portal
  → POST /api/v1/events
  → Backend validates JWT
  → Backend checks is_admin
  → Backend validates payload
  → Backend generates slug
  → Backend inserts events row as draft
  → Backend writes audit log
  → Response returns created event
```

### 16.2 Publish Event Flow

```text
Admin Portal
  → PATCH /api/v1/events/{event_id}/status
  → Backend validates admin
  → Backend validates event completeness
  → Backend sets status = published
  → Backend sets published_at
  → Backend writes audit log
  → Public listing now includes event
```

### 16.3 Public Listing Flow

```text
Flutter / Website
  → GET /api/v1/events
  → Backend returns published events only
  → Backend excludes virtual_url
  → Frontend displays event cards
```

### 16.4 Event Detail Flow

```text
Flutter / Website
  → GET /api/v1/events/{slug}
  → Backend returns public event detail
  → Backend excludes protected join link until registration flow exists
```

### 16.5 Registration Flow

```text
Flutter
  → User taps Register
  → If unauthenticated, navigate to login
  → POST /api/v1/events/{event_id}/register
  → Backend validates alumni user
  → Backend checks event status, registration window, capacity, duplicate
  → Backend creates registration
  → Backend emits confirmation
  → Flutter shows confirmation
```

### 16.6 Attendee Export Flow

```text
Admin Portal
  → GET /api/v1/events/{event_id}/attendees/export
  → Backend validates admin
  → Backend generates CSV
  → Audit export action
  → Browser downloads CSV
```

---

## 17. Developer Diagnostics Architecture

Developer Diagnostics should remain debug-only.

Categories:

- General
- Authentication
- Database
- Event Management
- Registration
- Admin / Attendees

Week 2 should enable Event Management diagnostics:

- Event list API test
- Event detail API test
- Event create API test
- Publish/unpublish API test

Diagnostics should show:

- Feature name
- Backend API
- HTTP method
- Auth requirement
- Status
- Last run
- Sample UI purpose

---

## 18. Security Architecture

Security requirements:

- All protected APIs require backend JWT.
- Backend enforces admin permissions.
- Backend enforces alumni-only registration.
- Do not expose join links before registration.
- Do not log Firebase tokens or JWTs.
- Do not expose attendee personal data to unauthorized users.
- Exports are admin-only.
- Audit sensitive actions.
- Client apps never directly access protected databases.
- Secrets never committed to source control.

---

## 19. Privacy Architecture

Privacy rules:

- Collect only event-required data.
- Keep alumni profile data in `alumni_db`.
- Do not duplicate alumni master data unnecessarily.
- Protect attendee data.
- Restrict exports.
- Avoid logging PII unnecessarily.
- Use audit records for sensitive admin actions.

---

## 20. Deployment Architecture

### 20.1 Target Infrastructure

- Cloud Run
- Cloud SQL
- Firebase Authentication
- Secret Manager
- Same region: `asia-south1`
- Same Firebase project

### 20.2 Local Development

Local URLs:

| Platform | Backend URL |
|---|---|
| Chrome / Admin Portal | `http://localhost:8000` |
| Flutter Web | `http://localhost:8000` |
| Android Emulator | `http://10.0.2.2:8000` |
| iOS Simulator | `http://127.0.0.1:8000` |
| Physical phone | `http://<LAN-IP>:8000` |

### 20.3 Production

Production should use:

- Cloud Run backend service
- Cloud SQL socket connection
- Secret Manager for DB credentials and JWT secret
- Firebase authorized domains configured
- HTTPS only

---

## 21. Testing and Verification

### 21.1 Backend

- Python compile
- Health check
- Auth exchange
- `/auth/me`
- Event CRUD API tests
- Registration API tests
- Attendee export tests

### 21.2 Flutter

- `flutter analyze`
- `flutter test`
- Android emulator
- Flutter Web Chrome
- Session persistence
- Logout
- Developer Diagnostics

### 21.3 React Admin

- `npm run build`
- `npm run lint`
- Login
- Dashboard
- Event create
- Event publish
- Event list
- Logout

### 21.4 Database

- Migrations
- Table existence
- Seed event data
- Registration constraints
- Duplicate protection

---

## 22. Key Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Diverging from Website auth | High | Use website-style JWT contract |
| Creating new role model too early | High | Use `is_admin` for Alpha |
| Exposing join links publicly | High | Exclude from public APIs |
| Duplicating alumni data | Medium | Store `ref_id`, hydrate from `alumni_db` |
| Implementing full v1.2 scope in June | High | Keep MVP scope strict |
| Registration race conditions | High | Use DB constraints and transactions |
| Email failures confusing users | Medium | Registration succeeds; email failure logged |
| Admin UI becoming too complex | Medium | Keep June UI simple |

---

## 23. Open Questions

1. For June MVP, should event creation be allowed for `is_admin` only, or also selected non-admin coordinators?
2. Should confirmation email be mandatory for demo acceptance, or can it be logged/stubbed locally?
3. Should public event detail show capacity count or only availability status?
4. Should event cancellation be part of Week 2 or Week 4?
5. Should June MVP include `virtual_url` storage but hide it until Week 3 registration?
6. Should attendee export include only confirmed registrations for MVP?
7. Should events use hard delete, soft delete, or cancelled/archive state only?

---

## 24. Architecture Decisions

| Decision | Status |
|---|---|
| Same Firebase project | Approved |
| Event backend owns Event JWT lifecycle | Approved |
| Website-style JWT shape | Approved |
| `is_admin` for Alpha admin | Approved |
| `events_db` owns event data | Approved |
| `alumni_db` remains source of truth | Approved |
| No direct frontend DB access | Approved |
| Public APIs use slug | Approved |
| Registration alumni-only for Alpha | Approved |
| Payments deferred | Approved |
| QR check-in deferred from June MVP | Approved |
| React Admin for operations | Approved |
| Flutter for attendee app | Approved |

---

## 25. Recommended Immediate Next Steps

1. Finalize this architecture review.
2. Get product owner / architecture approval.
3. Start Week 2 backend vertical slice.
4. Implement Event APIs.
5. Add Event Diagnostics.
6. Integrate React Admin Events page.
7. Integrate Flutter Event List/Detail.
8. Prepare Week 2 verification report.

---

## 26. References

This architecture review is based on:

- Event Management App Requirements v1.2
- NITKSAA Jun 30 Beta Plan
- NITKSAA Event App Integration & Architecture Alignment Note
- NITKSAA Digital Ecosystem Master Plan v2.1
- Existing NITKSAA Website architecture references
- Existing NITKSAA Portal v2 architecture references
- NITKSAA Event App Architecture Alignment Reference
