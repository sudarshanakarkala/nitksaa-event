# NITKSAA Event App – Information Architecture & Navigation (Alpha)

## 1. Roles and Access

### Roles
- **Public user**: Not logged in.
- **Member**: Logged-in alumnus with attendee privileges.
- **Volunteer / Staff**: Logged-in user with additional event-operations permissions.

### Access Summary
- Public:
  - Can see: Splash, Login, **Event List (public view)**.
  - Cannot see: Event Detail, Registration, My Events, QR Badge, Volunteer tools.
- Member:
  - Can see: All public screens + Event Detail, Registration, Registration Success, My Events, Registration Detail, QR Badge, Post-Event content.
- Volunteer / Staff:
  - Can see: Everything a Member can see + Volunteer Home, Event Operations, QR Scanner, Attendee List & Export.

---

## 2. Top-Level Route Map (Indicative)

| Section               | Route (example)                               | Access           | Entry From                                |
|----------------------|-----------------------------------------------|------------------|-------------------------------------------|
| Splash               | `/splash`                                     | Public           | App launch                                |
| Login                | `/login`                                      | Public           | Event List (CTA) / blocked routes         |
| Event List (public)  | `/events`                                     | Public           | Splash → auth check                       |
| Event List (authed)  | `/events`                                     | Member/Volunteer | Login success / Shell                     |
| Event Detail         | `/events/:id`                                 | Member/Volunteer | Event List (authed)                       |
| Registration Form    | `/events/:id/register`                        | Member           | Event Detail (Register CTA)               |
| Registration Success | `/events/:id/register/success`                | Member           | Registration Form (submit)                |
| My Events            | `/my-events`                                  | Member           | Shell tab / drawer                        |
| Registration Detail  | `/my-events/:eventId`                         | Member           | My Events                                 |
| QR Badge             | `/my-events/:eventId/qr`                      | Member           | Registration Detail / Success             |
| Volunteer Home       | `/volunteer`                                  | Volunteer        | Shell tab / deep link                     |
| Event Operations     | `/volunteer/events/:eventId`                  | Volunteer        | Volunteer Home                            |
| QR Scanner           | `/volunteer/events/:eventId/scan`             | Volunteer        | Event Operations                          |
| Attendee List        | `/volunteer/events/:eventId/attendees`       | Volunteer        | Event Operations                          |
| Settings/Profile     | `/settings`                                   | Member/Volunteer | Shell / drawer                            |

Route guards:
- Public-only: none (all public routes visible to everyone).
- Auth guard: `/events/:id`, `/events/:id/register*`, `/my-events*`, `/volunteer*`, `/settings`.
- Volunteer guard: `/volunteer*` requires staff/volunteer flag.

---

## 3. Public User IA (No Event Detail)

### Splash → Event List
- **Splash**
  - Checks Firebase auth.
  - If not logged in → go to **Event List (public)**.

### Event List (Public View)
- Content:
  - Upcoming and past events with title, date/time, location, basic tags.
- Actions:
  - Scroll/search/filter.
  - Tap Event Card → **Login / Continue as Member** (NOT Event Detail).

### Login
- Email/password + Google Sign-In.
- On success:
  - If user came from Event Card tap → go to **Event List (authed)**.
  - Otherwise → default to Event List (authed) or My Events.

---

## 4. Member IA

### 4.1 Home Shell (Authed Event List)
- **Event List (authed)**
  - Same list as public, but member context.
  - Actions:
    - Tap Event Card → **Event Detail (authed)**.
    - Navigate to My Events / Volunteer / Settings via shell.

### 4.2 Event Detail & Registration
- **Event Detail (authed)**
  - Sections:
    - Event summary: title, description, date/time, location, virtual/physical.
    - Agenda: sessions & tracks.
    - Speakers & sponsors.
    - Post-Event section (when available).
    - CTA region: Register / View Registration / Registration closed.
- **Registration Form**
  - Reached from Event Detail Register CTA.
  - Prefilled from alumni/refid where possible; fields for badge name & contact.
  - On submit: calls registration API (creates registration, generates `qrtoken`, triggers confirmation email).
- **Registration Success**
  - Shows confirmation message and email-sent info.
  - Actions: View QR Badge, Go to My Events.

### 4.3 My Events & Registration Detail
- **My Events**
  - List of events member registered for; each card shows event + status (Registered / Checked-in / Past).
- **Registration Detail (per event)**
  - Shows event summary + registration status.
  - Actions: View QR Badge, Go to Event Detail (Past/Upcoming).
- **QR Badge Screen**
  - Shows QR code generated from `qrtoken` + attendee badge name.

### 4.4 Post-Event Content
- **Event Detail (Past)**
  - Adds Post-Event tab/section:
    - Recording links list.
    - Photo gallery URLs.
  - Reachable from My Events or Event List (authed) for past events.

---

## 5. Volunteer / Staff IA

### 5.1 Volunteer Home
- Visible only if user has volunteer/staff role.
- Shows events where user has operations rights.
- Actions:
  - Select Event → Event Operations.

### 5.2 Event Operations (Per Event)
- Central hub for event-day workflows.
- Actions:
  - Open Scanner → QR Scanner.
  - View Attendee List → Attendee List Screen.
  - Download Attendee List → CSV/Export.

### 5.3 QR Scanner & Check-In
- **QR Scanner**
  - Camera scan of attendee QR.
  - Calls verify API → if valid & not checked-in, calls check-in API and logs attempt.
  - Shows success / duplicate / invalid states with strong visual feedback.

### 5.4 Attendee List & Export
- **Attendee List Screen**
  - Shows list of attendees for the event with search/filter.
  - Action: Export / Download CSV (or open Admin Portal export if that remains web-only).

---

## 6. Cross-Cutting Navigation Patterns

- **Route Guards**
  - Public vs authed: enforced via GoRouter + Firebase auth.
  - Volunteer routes further guarded by role flag.
- **Back Navigation**
  - From Login: on success, return to intended flow (typically Event List (authed)).
  - From Registration Success: back to Event Detail; primary CTA to My Events.
- **Shared States**
  - Loading, error, and empty states implemented via shared widgets on list/detail screens.

This IA and navigation map should be enough to configure your GoRouter routes, define feature modules, and align backend endpoint usage per screen for the Alpha release.