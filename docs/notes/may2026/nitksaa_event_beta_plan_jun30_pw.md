# NITKSAA Event App — Jun 30 Beta Plan

**Scope:** Auth · Event creation · Public listing · Registration · Confirmation email · Attendee list + export
**Out of scope:** Sessions/tracks · QR check-in

---

## Week 1 — May 29–Jun 6
**Goal: Auth done end-to-end. Backend and DB standing.**

### Flutter (attendee app)
- Complete email/password sign-in in `FirebaseAuthService`
- Implement Google Sign-In
- Wire auth state stream (replace one-shot `currentUser` check with `authStateChanges()`)
- Implement route guards — unauthenticated users redirected to `/login`
- Session persistence validation (token survives app restart)
- Build shared UI component library: `AppScaffold`, `AppCard`, `AppPrimaryButton`, `AppSecondaryButton`, `AppTextField`, `AppLoadingView`, `AppErrorView`, `AppEmptyView`
- Refactor `SplashScreen`, `LoginScreen`, `HomePlaceholderScreen` to use shared components

### FastAPI backend
- Stabilise folder structure: `api/`, `models/`, `schemas/`, `services/`, `repositories/`, `middleware/`
- Create `events_db` schema and first migration: `events`, `registrations`, `attendees` tables
- Add `join_url` and `timezone` fields to `events` table now (avoid migration later)
- Implement Firebase token verification middleware
- Health check endpoint
- Request logging middleware

### React admin portal
- Complete working login (Firebase Google + email)
- Route guard protecting admin pages
- Basic shell layout: sidebar nav, header, content area

### Milestone demo — end of Week 1
Alumni opens the Flutter app → logs in via Google → lands on home screen. Developer diagnostics confirm: Firebase connected, token verified by backend health endpoint, `events_db` migrations applied. Staff logs into admin portal.

---

## Week 2 — Jun 7–13
**Goal: Staff can create events. Public can browse and view details.**

### Flutter (attendee app)
- Public event listing screen (no login required)
  - Upcoming tab, past tab
  - Event card: title, date, type badge (In-person / Virtual), capacity indicator
- Event detail screen
  - Title, description, date/time with timezone display
  - Location (physical) or "Online" with join link hidden until registered
  - Speaker list (simple name + title)
  - Registration CTA button — taps to login if unauthenticated

### FastAPI backend
- Event CRUD endpoints: `POST /events`, `GET /events`, `GET /events/{id}`, `PATCH /events/{id}`, `DELETE /events/{id}`
- Event model fields: title, description, date, timezone, location, virtual/physical flag, join_url, capacity, registration_deadline, status (draft/published)
- Publish/unpublish endpoint: `PATCH /events/{id}/status`
- Public listing endpoint (no auth): returns published events only, excludes join_url

### React admin portal
- Event creation form: title, description, date/time, timezone picker, physical/virtual toggle, venue field (shown when physical), join URL field (shown when virtual), capacity, registration deadline
- Publish/unpublish toggle on event card
- Event list view showing all events with status badges

### Milestone demo — end of Week 2
Staff logs into admin portal → creates a Breakfast Club event (physical, Bangalore venue, capacity 30) → creates a Webinar event (virtual, join URL, IST + listed timezone). Both appear on the Flutter public listing. Opening each shows correct fields — venue for Breakfast Club, "Online" for Webinar (no join link yet — registration required).

---

## Week 3 — Jun 14–20
**Goal: Alumni can register. Confirmation email sent. Join link visible post-registration.**

### Flutter (attendee app)
- Registration screen: autofill name + batch year from `alumni_db`, confirm details, single register tap
- Capacity enforcement: disable CTA and show "Event is full" when capacity reached
- Duplicate registration guard: show "You're already registered" if already registered
- Confirmation screen: registration number, event summary, "Add to calendar" prompt
- Post-registration state on detail screen: join link visible for virtual events, venue map link for physical

### FastAPI backend
- Registration endpoint: `POST /events/{id}/register` — requires auth, validates alumni status (active only), checks capacity, prevents duplicates
- Alumni autofill endpoint: `GET /alumni/me` — direct `alumni_db` read via `fetch_alumni_info()` pattern, returns name, batch year, branch
- Confirmation email: wire transactional email service (SendGrid or equivalent), send on successful registration with event details and registration number
- `GET /events/{id}/my-registration` — returns registration status and reveals `join_url` for virtual events if registered

### React admin portal
- No new screens this week — backend focus. Admin portal changes are in Week 4.

### Milestone demo — end of Week 3
Alumni opens Flutter app → views Breakfast Club event → registers → sees confirmation screen → gets confirmation email. Registers for Webinar → join link appears on detail page post-registration. Second attempt to register shows "Already registered". Staff checks admin portal event view and sees registration counts updating.

---

## Week 4 — Jun 21–27
**Goal: Admin can manage attendees. Full end-to-end stable. Demo-ready.**

### Flutter (attendee app)
- Error state handling across all screens (network errors, session expiry, server errors)
- Loading skeleton states on listing and detail screens
- Empty state on listing when no events published
- Edge case: registration deadline passed — CTA replaced with "Registration closed"
- Edge case: event cancelled — banner on detail page
- `flutter analyze` clean, all warnings resolved

### FastAPI backend
- Attendee list endpoint: `GET /events/{id}/attendees` — admin auth required, returns name, batch year, branch, registration time, status
- Search/filter on attendee list: by name, by batch year
- CSV export endpoint: `GET /events/{id}/attendees/export`
- Load test both events end-to-end

### React admin portal
- Attendee list page: table with name, batch year, branch, registered at
- Search bar (name) and batch year filter
- CSV export button
- Event summary card: registered count vs capacity, registration deadline, event status
- Basic audit trail: who created/published the event

### Milestone demo — end of Week 4
Full walkthrough of both event types back to back:

**Breakfast Club scenario:** Staff creates event (30 capacity) → publishes → alumni register until full → 31st alumni sees "Event full" → staff exports CSV of 30 attendees

**Webinar scenario:** Staff creates event with join link → alumni registers → join link visible on detail page → staff views attendee list → exports CSV

Both demos on mobile (Flutter) and desktop (admin portal).

---

## Jun 30 — Beta Handoff

Three things needed by this date:

1. **Working demo environment** — a deployed staging instance (Cloud Run) with sample data for Breakfast Club and Webinar events, not just localhost
2. **Staff walkthrough doc** — one-page guide covering: create event, publish, view registrations, export CSV
3. **Known issues list** — honest list of what works, what's rough, what's deferred (sessions, QR, payment)

The beta is not a public release. It's a working system that NITKSAA staff can use to run the next Breakfast Club meeting and the next webinar without needing Dreamcast.
