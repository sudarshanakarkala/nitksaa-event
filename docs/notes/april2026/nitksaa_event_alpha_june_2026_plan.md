# NITKSAA Event Platform — Alpha Delivery Plan (June 2026)

## Objective

Deliver a working **NITKSAA Event Platform Alpha** by **June 30, 2026**.

The Alpha version should support:
- internal demos
- customer walkthroughs
- architectural validation
- initial volunteer/staff testing
- September 2026 hardening and stabilization

This Alpha is NOT the final production release.

---

# Product Goal

Replace Dreamcast (currently white-labelled for NITKonnect 2026) with a tightly integrated NITKSAA Event Platform.

The platform must:
- share NITKSAA identity
- avoid separate accounts
- integrate with existing Firebase auth
- support NITKonnect-scale events
- support future chapter events and webinars

---

# Architecture Principles

The Alpha must follow these constraints:

## Mandatory

- One FastAPI backend
- PostgreSQL as system of record
- Firebase only for identity/auth
- Shared Firebase project with Website/Admin Portal
- Cloud Run deployment target
- Shared design system across applications
- Componentized frontend/backend architecture
- Reuse existing UI patterns
- Shared operational vocabulary

## Avoid During Alpha

- Microservices
- Offline-first sync engines
- Realtime dependency
- Dynamic workflow builders
- Plugin systems
- Advanced multi-tenant SaaS abstractions
- Excessive configuration systems
- Complex orchestration
- Over-automation

---

# Alpha Scope (Must Be Completed by June 30)

| Capability | Notes |
|---|---|
| Event creation by staff / chapter coordinators | Title, description, date, location (physical or virtual), capacity, registration deadline |
| Public event listing page | No login required to view |
| Event detail page | Schedule, speakers, sponsors, registration CTA |
| Member registration | Login required; autofill from alumni_db via Alumni Service (or direct read initially) |
| Registration confirmation email | Via mail service |
| Attendee list (admin view) | With export |
| Session / track support | NITKonnect has parallel tracks |
| QR code check-in | Mobile-friendly — this is used on the day |
| Post-event: recording links + photo gallery | Simple link list, not a media host |

---

# Deferred Features (NOT Part of Alpha)

## What can wait for Feb:

| Capability | Notes |
|---|---|
| Payment / ticketed events | Only if a paid event is planned before Feb |
| Chapter-specific event series | Admin can manage manually until this is built |
| Waitlist management | Manual process initially |
| Speaker / sponsor management portal | Managed in a spreadsheet until this is built |
| Event analytics dashboard | Post-event reporting |

---

The following features are intentionally deferred:

- Payment integration
- Waitlist management
- Advanced analytics dashboard
- Speaker/sponsor management portal
- Offline synchronization
- Realtime dashboards
- Complex notification orchestration
- Dynamic workflow builders
- Multi-brand runtime SaaS customization

---

# Team Assumption

## Current Team

- 2 part-time architect/developer
- AI-assisted development (Claude/Codex/ChatGPT)
- Existing Firebase project
- Existing Flutter foundation completed
- Existing Admin Portal foundation started
- Existing FastAPI backend skeleton started

---

# Current Status (Completed)

## Flutter Event App

### Foundation
- Flutter bootstrap completed
- Firebase connected
- Hive initialized
- Riverpod configured
- GoRouter configured
- Material 3 theme system completed
- Logger framework completed
- Developer diagnostics screen completed

### Authentication Foundation
- Splash screen completed
- Login screen completed
- Auth wrapper created
- Logout flow foundation created
- Firebase auth foundation added

### Architecture
- Feature-first folder structure established
- Shared routing foundation created
- Theme architecture stabilized
- Production-safe logging established

---

# June 2026 Alpha Execution Plan

## Week 1 — Shared UI + Authentication Completion

### Goal
Stabilize design system and complete authentication.

### Deliverables

#### Shared UI Components
Create reusable components:

```text
shared/widgets/
  app_scaffold.dart
  app_card.dart
  app_primary_button.dart
  app_secondary_button.dart
  app_text_field.dart
  app_loading_view.dart
  app_error_view.dart
  app_empty_view.dart
```

#### Refactor Existing Screens
Refactor:
- SplashScreen
- LoginScreen
- HomePlaceholderScreen
- DeveloperDiagnosticsScreen
- FoundationReadyScreen

#### Authentication
Complete:
- Email/password login
- Google Sign-In
- Route guards
- Session persistence
- Logout flow validation

### Success Criteria
- No duplicate button styles
- No duplicate form field logic
- Auth fully functional
- All routes protected correctly
- Flutter analyze/test clean

---

## Week 2 — Backend + Database Foundation

### Goal
Establish production-safe backend foundation.

### Deliverables

## Backend

### FastAPI
Create:

```text
backend/
  app/
    api/
    models/
    schemas/
    services/
    repositories/
    middleware/
```

### Database
Create `events_db` schema:

```text
events
sessions
registrations
attendees
check_ins
```

### API Foundation
Implement:
- health endpoint
- auth verification endpoint
- event CRUD APIs
- session CRUD APIs
- registration APIs

### Security
Implement:
- Firebase token verification
- role middleware
- request logging
- audit foundation

### Success Criteria
- Backend deployable locally
- APIs testable
- Database migrations working
- Firebase auth verification functional

---

## Week 3 — Event Creation + Public Listing

### Goal
Deliver event management foundation.

### Deliverables

### Staff Event Creation
Support:
- title
- description
- date/time
- location
- virtual/physical flag
- capacity
- registration deadline
- publish/unpublish

### Public Event Listing
Features:
- upcoming events
- past events
- search/filter basics
- no login required

### Event Detail Page
Support:
- schedule
- speakers
- sponsors
- registration CTA

### Success Criteria
- Staff can create event
- Public users can browse events
- Event detail works end-to-end

---

## Week 4 — Registration + Attendee Management

### Goal
Deliver complete registration workflow.

### Deliverables

### Registration Flow
Support:
- authenticated registration
- Firebase UID mapping
- alumni reference mapping
- registration confirmation state

### Confirmation Email
Implement:
- basic transactional email
- registration success email

### Attendee Management
Support:
- attendee list
- search/filter
- CSV export

### Success Criteria
- User can register successfully
- Admin can see attendees
- Export works
- Email confirmation sent

---

## Week 5 — Sessions + QR Check-In

### Goal
Deliver operational event-day workflows.

### Deliverables

### Session / Track Support
Support:
- multiple tracks
- session schedules
- parallel sessions

### QR Badge
Support:
- QR generation
- attendee badge identifier

### QR Check-In
Support:
- mobile-friendly scanning
- volunteer check-in flow
- attendee status update

### Success Criteria
- QR generated correctly
- Volunteer can scan/check-in attendee
- Sessions visible on event detail

---

## Week 6 — Alpha Hardening + Demo Preparation

### Goal
Stabilize Alpha for walkthrough/demo.

### Deliverables

### Post-Event Content
Support:
- recording links
- photo gallery URLs

### Hardening
Perform:
- bug fixing
- UI cleanup
- flow validation
- API cleanup
- performance review
- HAR analysis
- latency review

### Demo Data
Prepare:
- NITKonnect sample event
- Breakfast Club sample event
- Webinar sample event

### Documentation
Update:
- sprint progress
- architecture docs
- API docs
- setup docs
- deployment docs

### Success Criteria
- Stable demo walkthrough
- Internal review possible
- All Alpha features functional
- No critical blockers

---

# Daily Engineering Workflow

## Recommended Execution Pattern

Every feature/component should follow:

```text
Plan
→ Implement
→ Run
→ Review
→ Fix
→ Commit
```

## Commit Strategy

Example:

```text
feat(ui): add shared app button components
feat(auth): complete email authentication
feat(events): add public event listing
feat(events): add event detail screen
feat(registration): add attendee registration flow
feat(checkin): implement QR check-in
```

---

# Development Rules

## Mandatory Rules

### Reuse Existing Components
Never create:
- duplicate buttons
- duplicate forms
- duplicate cards
- duplicate modal patterns

Always reuse shared UI infrastructure.

### Keep Backend Simple
- One FastAPI backend only
- No microservices
- No unnecessary async complexity

### Operational Simplicity
Optimize for:
- predictable workflows
- obvious admin actions
- graceful degradation
- understandable UI

### Componentization
All new work should be componentized:
- frontend
- backend
- documentation
- architecture

### Documentation Discipline
Maintain continuously:
- master plan
- sprint plan
- progress report
- architecture notes
- engineering rules

---

# Alpha Success Definition

By June 30, 2026, the team should be able to demonstrate:

```text
1. Staff creates event
2. Public user views event list
3. Public user opens event detail
4. Member logs in
5. Member registers
6. Confirmation email is sent
7. Admin views attendee list
8. Admin exports attendee CSV
9. QR badge is generated
10. Volunteer scans attendee QR
11. Attendee is checked in
12. Post-event recording links are visible
```

---

# Post-Alpha (July–September 2026)

The following period should focus on:

- hardening
- testing
- performance
- operational readiness
- volunteer walkthroughs
- security review
- UI refinement
- dry runs
- production deployment readiness

Goal:

```text
September 2026
→ Solid working version
→ Feature-complete
→ Tested
→ Demo-ready
```

---

# Daily Execution & Tracking Plan

## Daily Execution Strategy

Every day should focus on:

```text
1 major feature or component only
→ implement
→ validate
→ review
→ fix
→ commit
```

Avoid parallel unfinished modules.

---

# Daily Tracking Template

## Status Definitions

| Status | Meaning |
|---|---|
| NOT STARTED | Work not yet started |
| IN PROGRESS | Currently being implemented |
| BLOCKED | Waiting for dependency/clarification |
| REVIEW | Ready for review/testing |
| COMPLETED | Finished and validated |

---

# Alpha Delivery Tracking Sheet

| Major Feature | Sub Task | Status | Comments | Approver Status | Approver Comments |
|---|---|---|---|---|---|
| Shared UI Foundation | Create AppScaffold | NOT STARTED |  | PENDING |  |
| Shared UI Foundation | Create AppPrimaryButton | NOT STARTED |  | PENDING |  |
| Shared UI Foundation | Create AppSecondaryButton | NOT STARTED |  | PENDING |  |
| Shared UI Foundation | Create AppTextField | NOT STARTED |  | PENDING |  |
| Shared UI Foundation | Create AppCard | NOT STARTED |  | PENDING |  |
| Shared UI Foundation | Create Loading/Error/Empty States | NOT STARTED |  | PENDING |  |
| Shared UI Foundation | Refactor existing screens to shared UI | NOT STARTED |  | PENDING |  |
| Authentication | Email login implementation | NOT STARTED |  | PENDING |  |
| Authentication | Google Sign-In implementation | NOT STARTED |  | PENDING |  |
| Authentication | Route guards | NOT STARTED |  | PENDING |  |
| Authentication | Session persistence validation | NOT STARTED |  | PENDING |  |
| Authentication | Logout validation | NOT STARTED |  | PENDING |  |
| Backend Foundation | FastAPI structure stabilization | NOT STARTED |  | PENDING |  |
| Backend Foundation | PostgreSQL events_db schema | NOT STARTED |  | PENDING |  |
| Backend Foundation | Database migrations | NOT STARTED |  | PENDING |  |
| Backend Foundation | Firebase token verification | NOT STARTED |  | PENDING |  |
| Backend Foundation | Health APIs | NOT STARTED |  | PENDING |  |
| Event Management | Event CRUD APIs | NOT STARTED |  | PENDING |  |
| Event Management | Event creation UI | NOT STARTED |  | PENDING |  |
| Event Management | Public event listing | NOT STARTED |  | PENDING |  |
| Event Management | Event detail page | NOT STARTED |  | PENDING |  |
| Event Management | Publish/unpublish flow | NOT STARTED |  | PENDING |  |
| Registration | Member registration flow | NOT STARTED |  | PENDING |  |
| Registration | Alumni autofill integration | NOT STARTED |  | PENDING |  |
| Registration | Registration confirmation screen | NOT STARTED |  | PENDING |  |
| Registration | Registration email service | NOT STARTED |  | PENDING |  |
| Attendee Management | Admin attendee list | NOT STARTED |  | PENDING |  |
| Attendee Management | Search/filter attendees | NOT STARTED |  | PENDING |  |
| Attendee Management | CSV export | NOT STARTED |  | PENDING |  |
| Sessions & Tracks | Session CRUD | NOT STARTED |  | PENDING |  |
| Sessions & Tracks | Track support | NOT STARTED |  | PENDING |  |
| Sessions & Tracks | Event agenda UI | NOT STARTED |  | PENDING |  |
| QR Check-In | QR generation | NOT STARTED |  | PENDING |  |
| QR Check-In | QR scan flow | NOT STARTED |  | PENDING |  |
| QR Check-In | Volunteer check-in UI | NOT STARTED |  | PENDING |  |
| QR Check-In | Check-in backend update | NOT STARTED |  | PENDING |  |
| Post Event | Recording links | NOT STARTED |  | PENDING |  |
| Post Event | Photo gallery URLs | NOT STARTED |  | PENDING |  |
| Hardening | Flutter analyze/test stabilization | NOT STARTED |  | PENDING |  |
| Hardening | API validation | NOT STARTED |  | PENDING |  |
| Hardening | HAR/performance analysis | NOT STARTED |  | PENDING |  |
| Hardening | Bug fixing | NOT STARTED |  | PENDING |  |
| Documentation | Sprint progress updates | NOT STARTED |  | PENDING |  |
| Documentation | API documentation | NOT STARTED |  | PENDING |  |
| Documentation | Setup/deployment docs | NOT STARTED |  | PENDING |  |

---

# Daily Workflow Rules

## Mandatory Rules

### Rule 1 — One Stable Component At A Time

Do NOT develop:
- multiple unfinished modules simultaneously
- overlapping UI patterns
- duplicate business logic

Finish one component fully before moving to the next.

---

### Rule 2 — Reuse Existing Components

Claude/Codex must:
- reuse existing buttons
- reuse existing forms
- reuse existing cards
- reuse existing layouts
- reuse existing APIs/services

Never reinvent UI patterns.

---

### Rule 3 — Every Change Requires Validation

After every implementation:

```text
flutter analyze
flutter test
flutter run
```

Backend:

```text
pytest
API validation
manual verification
```

---

### Rule 4 — Every Stable Step Requires Commit

Example:

```text
feat(auth): complete email login
feat(events): add public event listing
feat(checkin): implement QR check-in
```

---

### Rule 5 — Documentation Must Stay Updated

Always update:
- sprint plan
- progress status
- architecture notes
- implementation decisions
- review comments

---

# Alpha Success Criteria

By June 30, 2026, the team should demonstrate:

```text
1. Staff creates event
2. Public user views event list
3. Public user opens event detail
4. Member logs in
5. Member registers
6. Confirmation email sent
7. Admin views attendee list
8. Admin exports attendee CSV
9. QR badge generated
10. Volunteer scans attendee QR
11. Attendee successfully checked in
12. Post-event recording links visible
```

---

# Final Principle

This platform is not intended to become a generic SaaS product.

The objective is:

```text
Build a stable, maintainable, operationally sustainable
NITKSAA Event Platform.
```

Operational simplicity, consistency, and institutional maintainability are more important than architectural cleverness.

