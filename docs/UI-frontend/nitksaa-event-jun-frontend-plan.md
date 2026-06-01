# NITKSAA Event Management App – Frontend (Flutter) Implementation Plan (June 2026)

## 1. Context and Assumptions

- Backend event vertical slice is implemented in FastAPI with PostgreSQL and exposes endpoints for events, sessions, registrations, and check-ins.
- Alpha delivery plan (June 2026) already defines product scope and weekly milestones on the backend and platform level.
- Flutter app foundation is in place:
  - Firebase connected
  - Hive initialized
  - Riverpod configured
  - GoRouter configured
  - Material 3 theme system completed
  - Logger framework completed
  - Developer diagnostics screen completed
- This document focuses on the **mobile Flutter app** for members and volunteers:
  - Event discovery (public)
  - Member registration
  - QR badge display
  - Volunteer check-in tools
  - Minimal attendee visibility for operations

---

## 2. Frontend Alpha Scope (Flutter)

### 2.1 Authentication & Shell

- Splash, login (email/password + Google), logout, session persistence, route guards.
- Shared app shell: scaffold, app bar, navigation, error/loading/empty states.

### 2.2 Public Event Discovery

- Event list screen: upcoming/past events with basic search/filter, accessible without login.
- Event detail screen: schedule, speakers, sponsors, registration CTA.

### 2.3 Member Registration

- Authenticated registration flow tied to Firebase UID and alumni reference (refid).
- Registration success screen and registration state display (registered, checked-in, etc.).
- Triggering of backend event **registration confirmation email** after successful registration and communicating its status to the user in the UI.

### 2.4 QR Badge & Check-in

- QR badge screen for each registration using backend-provided `qrtoken`.
- Volunteer check-in screen (scanner) to verify and check-in attendees.

### 2.5 Minimal Attendee Visibility

- Event-scoped attendee list with basic search/filter for volunteers/staff.

### 2.6 Post-Event Content

- Simple UI for recording links and photo gallery URLs per event (read-only).

---

## 3. Technical Foundations (Flutter Stack)

- **State management**: Riverpod for feature-based providers (auth, events, registration, check-in).
- **Routing**: GoRouter with guarded routes for authenticated areas.
- **Persistence**: Hive for lightweight local caching.
- **Networking**: One HTTP client abstraction (e.g., Dio/http) with interceptors for auth headers using Firebase ID token and dev headers during Alpha.
- **Design system**: Material 3 + shared widgets (`AppScaffold`, `AppCard`, `AppPrimaryButton`, `AppSecondaryButton`, `AppTextField`, `AppLoadingView`, `AppErrorView`, `AppEmptyView`).
- **Folder structure**: Feature-first (e.g., `features/events`, `features/registration`, `features/checkin`, `shared/widgets`, `shared/network`).

All new screens must reuse shared widgets and follow the design system to avoid duplication.

---

## 4. Week-by-Week Frontend Plan (June 2026)

### Week 1 (Jun 1–7) — Shared UI + Authentication Completion

**Goal:** Stabilize the design system and fully close authentication flows using shared widgets and route guards.

#### 4.1 User Stories

- As a user, I can log in using email/password or Google and stay logged in across app restarts.
- As a user, I see consistent buttons, text fields, and cards across all screens.
- As a developer, I can build new screens quickly using shared scaffolds and widgets.

#### 4.2 Implementation Tasks

1. **Shared UI Components (`shared/widgets`)**
   - Implement:
     - `app_scaffold.dart` (app bar, safe area, background, snackbar support).
     - `app_card.dart`.
     - `app_primary_button.dart`, `app_secondary_button.dart`.
     - `app_text_field.dart` (validation, error text, focus handling).
     - `app_loading_view.dart`, `app_error_view.dart`, `app_empty_view.dart`.
   - Wire up global theme tokens (colors, typography, spacing) into these widgets.

2. **Refactor Existing Screens to Shared UI**
   - Migrate the following screens to use shared components only:
     - `SplashScreen`
     - `LoginScreen`
     - `HomePlaceholderScreen`
     - `DeveloperDiagnosticsScreen`
     - `FoundationReadyScreen`
   - Remove duplicate, screen-local button/form styles and enforce single source of truth.

3. **Authentication Completion**
   - Finish email/password login wiring to Firebase Auth.
   - Implement Google Sign-In (Android + iOS configs, plugin wiring).
   - Implement route guards using GoRouter and Riverpod:
     - Public routes: event list, event detail.
     - Protected routes: registration, QR badge, volunteer tools.
   - Implement session persistence:
     - Auto-restore user on app start.
     - Handle token refresh and error states gracefully.
   - Finalize logout flow:
     - Clear tokens/session.
     - Navigate to login.
     - Reset relevant Riverpod providers.

#### 4.3 Testing & Success Criteria

- `flutter analyze` and `flutter test` pass with no new warnings.
- All auth routes properly protected; manual verification for "open protected route while logged out".
- No duplicate button or form implementations remain.

---

### Week 2 (Jun 8–14) — Public Event Listing & Event Detail

**Goal:** Deliver read-only event discovery experience: list and detail screens backed by real APIs.

#### 4.4 User Stories

- As an unauthenticated user, I can see a list of upcoming and past events.
- As a user, I can open an event to see schedule, speakers, sponsors, and a registration CTA.

#### 4.5 Implementation Tasks

1. **Event Domain Models and API Client**
   - Create Flutter models mapping to backend schemas:
     - `Event` (id, title, description, datetime, location, virtual/physical flag, capacity, status, window fields, etc.).
     - `Session` (id, eventId, track, title, start/end time, location, speaker, sort order).
   - Implement event API client:
     - `fetchEvents({statusFilter, search, page})` → `GET /api/v1/events`.
     - `fetchEventDetail(eventId)` → `GET /api/v1/events/{id}`.
     - `fetchEventSessions(eventId)` → `GET /api/v1/events/{id}/sessions`.

2. **Event List Screen**
   - UI:
     - Segmented control or tabs: Upcoming / Past.
     - Search bar (by title) and basic filters (e.g., virtual/physical).
     - Cards per event using `AppCard`, showing title, date, location, and capacity snippet.
   - State:
     - Riverpod providers: `eventsListProvider`, `eventFiltersProvider`.
     - Use `AppLoadingView`, `AppErrorView`, `AppEmptyView` for states.
   - Routing:
     - Tap on event card → navigate to event detail route with `eventId`.

3. **Event Detail Screen**
   - UI:
     - Event summary (title, description, date/time, location, virtual/physical flag).
     - Schedule section listing sessions and tracks.
     - Speakers and sponsors sections (basic labels/fields).
     - Call-to-Action area:
       - "Register" if event is published and within registration window.
       - "Registration closed" or disabled state otherwise.
   - State:
     - `eventDetailProvider(eventId)` combining event + sessions calls.
   - Behaviour:
     - Reflect backend state fields (published/draft/closed, capacity, opens_at/closes_at) in UI instead of duplicating logic.

#### 4.6 Testing & Success Criteria

- Unauthenticated user can browse events and open details on device against dev backend.
- UI reflects backend state correctly (e.g., full/closed events not open for registration).
- Unit tests for event list provider and basic event detail rendering.

---

### Week 3 (Jun 15–21) — Registration Flow, Confirmation Email & Registration State

**Goal:** Deliver end-to-end member registration, tied to Firebase UID and alumni reference, with clear UI states and confirmation email to the registrant.

#### 4.7 User Stories

- As a logged-in member, I can register for a published event.
- As a member, I see success confirmation and my registration status.
- As a member, I receive a **registration confirmation email** after successful registration.
- As a member, I cannot register twice for the same event.

#### 4.8 Implementation Tasks

1. **Registration Models and API Client**
   - Define models matching backend tables:
     - `Registration` (id, eventId, attendeeId, status, qrtoken, timestamps, etc.).
     - `Attendee` (id, name, email, phone, type, refid, etc.).
   - Implement registration client:
     - `registerForEvent(eventId, payload)` → `POST /api/v1/events/{eventId}/register`.
     - `getRegistration(eventId, registrationId)` → `GET /api/v1/events/{eventId}/registrations/{registrationId}` (or equivalent).

2. **Registration Form Screen**
   - Entry:
     - From Event Detail CTA "Register" → `EventRegistrationScreen`.
   - UI:
     - Prefill fields using alumni/refid data when available.
     - Fields: badge name, email, phone, optional notes, attendee type (if needed).
     - Validation using `AppTextField`.
   - Behaviour:
     - Disable submit when event is full/closed as per event detail flags.
     - Surface backend errors:
       - Duplicate registration (HTTP 409).
       - Capacity exceeded.
       - Registration window closed.

3. **Triggering Confirmation Email (Backend Integration)**
   - Ensure `registerForEvent` call hits the backend flow that:
     - Creates registration and attendee.
     - Generates `qrtoken`.
     - Triggers the **registration confirmation email** via backend mail service.
   - UI behaviour:
     - On successful registration, show a message such as "Registration successful. A confirmation email has been sent to <email>.".
     - If the backend indicates email failure, show a non-blocking warning (registration remains valid but email could not be delivered) and log for diagnostics.

4. **Registration Success & "My Events"**
   - `RegistrationSuccessScreen`:
     - Show event summary, registration status, and a "View QR Badge" action.
     - Confirm that a registration email has been sent (based on API response).
   - "My Events" section:
     - List events the user is registered for with status chips (Registered / Checked-in / Cancelled).
   - Providers:
     - `myRegistrationsProvider` to load user registrations (per UID or derived pattern).

5. **Error Handling & State Refresh**
   - Map backend error codes to friendly strings.
   - Ensure event detail CTA changes from "Register" to "View Registration" after successful registration.
   - Handle transient network errors on form submission with retry guidance.

#### 4.9 Testing & Success Criteria

- Member can register end-to-end on device against dev backend.
- Duplicate registration is blocked with clear messaging.
- On successful registration, the UI clearly communicates that a confirmation email has been (or will be) sent.
- Unit tests for:
  - Registration service and `myRegistrationsProvider`.
  - Handling of success vs error responses related to email sending (e.g., flag in API response).

---

### Week 4 (Jun 22–28) — QR Badge & Volunteer Check-In UI

**Goal:** Enable event-day operations: QR badge for attendees and scanner UI for volunteers/admin on mobile devices.

#### 4.10 User Stories

- As a registered attendee, I can display my QR badge for scanning.
- As a volunteer, I can scan QR codes and check in attendees, with immediate feedback.

#### 4.11 Implementation Tasks

1. **QR Badge Screen (Attendee)**
   - Use `qrtoken` from registration response to generate QR code on device.
   - UI:
     - Event summary + attendee badge name + QR image.
     - Instructions for scanning.
   - Data:
     - Ensure secure storage or retrieval of `qrtoken` for each registration.

2. **Volunteer Check-In Screen (Scanner)**
   - Access:
     - Route guard for volunteer/admin role (for Alpha, via dev-only toggle or role flag).
   - Features:
     - Camera-based scanner using QR plugin.
     - On scan:
       - Call verify endpoint to validate token.
       - On success, call check-in endpoint to mark attendance.
     - Show states:
       - Success: attendee name, status, and optional session.
       - Duplicate: "Already checked in" feedback.
       - Invalid/unauthorized: error state.
   - UX:
     - Large visual feedback (green success, amber duplicate, red error).
     - Retry and manual input options.

3. **Minimal Attendee List for Volunteers**
   - `EventAttendeeListScreen`:
     - List checked-in and not-yet-checked-in attendees.
     - Search by name/email.
   - Use appropriate admin/attendee list endpoint.

#### 4.12 Testing & Success Criteria

- Attendee can display a scannable QR badge.
- Volunteer can scan valid QR and mark attendee as checked-in, and see duplicate feedback on second scan.
- Basic test coverage of QR flow with mocks.

---

### Week 5–6 (Jun 29–30 and Buffer) — Sessions/Tracks UI, Post-Event Content & Hardening

**Goal:** Surface multi-track schedules, support post-event content, and harden the app for Alpha demos.

#### 4.13 User Stories

- As an attendee, I can see the event agenda with multiple tracks and sessions.
- As an attendee, I can later find recording links and photos for events I attended.
- As a stakeholder, I can experience the full Alpha flow smoothly during demos.

#### 4.14 Implementation Tasks

1. **Sessions/Track UI**
   - Extend Event Detail with agenda:
     - Group sessions by track.
     - Display time, title, room, and speaker.
   - Layout:
     - Tabs per track or grouped list with track headers.

2. **Session-Aware Check-In (Optional for Alpha)**
   - If backend supports session-specific check-ins:
     - Add session selection to volunteer check-in flow.
   - Otherwise, design UI in a way that can be extended later.

3. **Post-Event Content Screens**
   - Extend Event Detail or add "Post-Event" tab:
     - Recording links (list of URLs with labels).
     - Photo gallery URLs (links, no heavy gallery component in Alpha).
   - Indicate in "My Events" when post-event content is available.

4. **UI/UX Cleanup & Performance**
   - Ensure consistent spacing, typography, and color usage.
   - Review empty/error states across all screens.
   - Add small UX improvements (pull-to-refresh, skeletons where needed).
   - Performance:
     - Cache event list data in Hive.
     - Minimize unnecessary rebuilds (Riverpod `select`, proper widget decomposition).

5. **Demo Data & Scripts**
   - Coordinate with backend to seed demo events:
     - NITKonnect sample event
     - Breakfast Club sample event
     - Webinar sample event
   - Prepare demo scripts:
     - Script 1: Public discovery + member registration + QR badge.
     - Script 2: Volunteer check-in after scanning.
     - Script 3: Post-event content viewing.

6. **Documentation (Frontend-Focused)**
   - Architecture notes: feature modules, providers, routing, and design system.
   - API integration notes: mapping endpoints to services and screens.
   - Setup instructions: Firebase config, environment variables, dev/prod endpoint config.
   - Link to overall Alpha documentation and sprint plan.

#### 4.15 Testing & Final Success Criteria

By June 30, the Flutter app should support the following Alpha demo sequence:

1. Staff (via Admin Portal) creates event.
2. Public user opens app, views event list, and opens event detail.
3. Member logs in and registers for the event.
4. Registration success is visible in the app and a confirmation email is sent to the registrant.
5. Member can open their QR badge in the app.
6. Volunteer uses the app to scan the QR and check-in attendee.
7. Post-event recording links and photo URLs are visible in the app.

---

## 5. Daily Execution Rules (Frontend Emphasis)

Reusing the platform’s daily workflow rules, adapted for Flutter:

- Focus on **one major UI feature or component per day** (e.g., event list cards, registration validation, QR scanner feedback).
- After every change:
  - Run `flutter analyze`, `flutter test`, `flutter run` on relevant flows.
- Never create duplicate buttons, forms, or card patterns; always route through shared widgets.
- Every stable step results in a commit with clear messages, for example:
  - `feat(ui): add shared app button components`
  - `feat(events): add public event listing`
  - `feat(checkin): implement QR check-in`

This keeps the Flutter frontend aligned with the overall NITKSAA Event Platform Alpha architecture and delivery principles.
