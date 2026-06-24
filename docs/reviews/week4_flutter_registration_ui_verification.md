# Week 4 — Flutter Production Registration UI Verification

Date: 2026-06-24

## Verdict

**PASS — Registration UI implemented. `flutter analyze lib/` → No issues.**

---

## Summary

The production registration flow is now complete for alumni users. The "Registration will be available in Week 3" placeholder has been replaced with a working end-to-end flow.

---

## Files Created

| File | Purpose |
|---|---|
| `lib/features/registration/domain/alumni_profile.dart` | Alumni profile domain model (`AlumniProfile`) |
| `lib/features/registration/domain/registration.dart` | Registration domain model (`Registration`, `RegistrationEventSummary`) |
| `lib/features/registration/services/registration_service.dart` | `RegistrationService` + `registrationErrorMessage()` helper |
| `lib/features/registration/presentation/register_screen.dart` | `RegisterScreen` — alumni profile + note + confirm |
| `lib/features/registration/presentation/confirmation_screen.dart` | `ConfirmationScreen` — success state with all registration details |
| `lib/features/registration/presentation/my_registrations_screen.dart` | `MyRegistrationsScreen` — `GET /api/v1/my/registrations` list |

## Files Modified

| File | Changes |
|---|---|
| `lib/routes/app_routes.dart` | Added `registerForEvent(int)`, `registrationConfirmation`, `myRegistrations` routes |
| `lib/routes/app_router.dart` | Added `GoRoute` entries for register, confirmation, my-registrations screens |
| `lib/features/events/presentation/event_detail_screen.dart` | Replaced static "Register" snackbar with smart `_RegistrationCta` widget + `_CancelledBanner` |

---

## Feature: Event Detail Registration CTA

### CTA States

| `event.status` | `isAuthenticated` | `event.registrationStatus` | CTA |
|---|---|---|---|
| `cancelled` | any | any | Cancelled banner + "Registration Unavailable" (disabled) |
| any | `false` | any | "Sign in to Register" → pushes to login |
| any | `true` | `open` | "Register" → pushes to register screen |
| any | `true` | `full` | "Event Full" (disabled) |
| any | `true` | `closed` | "Registration Closed" (disabled) |
| any | `true` | `not_open_yet` | "Registration Opens Soon" (disabled) |
| any | `true` | other | "Registration Unavailable" (disabled) |

### Auth check

Uses `AuthController.instance.isAuthenticated` via the existing `isAuthenticated` parameter pattern (testable via widget injection). Tapping "Sign in to Register" calls `context.push(AppRoutes.login)`.

### Navigation to register

Route: `GET /events/:eventId/register?title=<encoded_title>`

Event title is URL-encoded and passed as a query parameter so `RegisterScreen` can display it without needing an extra API call.

---

## Feature: Register Screen

**Route:** `/events/:eventId/register`

### Flow

```
initState
  ↓ GET /api/v1/alumni/me
  → AlumniProfile loaded

User sees:
  - Event title card
  - Read-only alumni profile (name, email, phone, batch year, branch)
  - Alumni active/inactive badge
  - Optional attendee note (max 500 chars)
  - Error card if previous attempt failed
  - "Confirm Registration" button

Tap Confirm:
  ↓ POST /api/v1/events/:eventId/register
  → Registration object returned
  → context.pushReplacement(AppRoutes.registrationConfirmation, extra: registration)
```

### Error handling

| Backend `detail` | User message |
|---|---|
| `alumni_only` | "This event is for alumni only." |
| `alumni_not_active` | "Your alumni profile is inactive. Contact the registrar." |
| `alumni_profile_not_found` | "Alumni profile not found. Contact the registrar." |
| `event_full` | "This event is full. Registration is no longer available." |
| `already_registered` | "You are already registered for this event." |
| `registration_closed` | "Registration for this event has closed." |
| `event_not_published` | "This event is not currently accepting registrations." |
| Connection error | "Check your connection and try again." |
| Other `4xx/5xx` | "Registration failed ({status}). Please try again." |

Error shown in a red error card above the Register button. The button re-enables after error so the user can retry or correct the issue.

### Not authenticated path

`RegistrationService._authOptions()` reads from `AuthSessionStore`. If no token is stored, it throws `StateError('Not signed in. Please sign in to continue.')`. This maps to the `StateError` branch in `registrationErrorMessage()`, showing "Not signed in. Please sign in to continue." in the error card.

---

## Feature: Confirmation Screen

**Route:** `/registration/confirmation` (extra: `Registration` object)

Shows:
- Green success banner ("You're registered!")
- Registration Details card: registration number, name, email, join link (virtual events only)
- Event card: title, date, time, venue or "Online"
- Email status card: `sent` / `failed` / `skipped` with icon
- "View My Registrations" → `context.go(AppRoutes.myRegistrations)`
- "Back to Events" → `context.go(AppRoutes.events)`

Join link is only shown when `registration.joinUrl != null` (backend sets this for virtual + registered + published events).

---

## Feature: My Registrations Screen

**Route:** `/my-registrations`

**API:** `GET /api/v1/my/registrations`

### States

| Condition | UI |
|---|---|
| Loading | `AppLoadingView` with spinner |
| Error | `AppErrorView` with retry button |
| Empty list | `AppEmptyView` with "Browse Events" button |
| Non-empty list | `ListView` of `_RegistrationCard` |

### Registration Card

- Event title (or "Event #{id}" if event summary not returned)
- Registration number (monospace)
- Status badge: green "Registered", red "Cancelled", neutral otherwise
- Event date + time (from `event.startDateTime`)
- Event location or "Online"
- Join link (SelectableText, shown only when: `status=registered`, `isVirtual=true`, `joinUrl != null`)

Pull-to-refresh supported.

---

## Routing

```
AppRoutes.events/:eventId/register?title=<encoded>
  → RegisterScreen(eventId: id, eventTitle: decoded_title)

AppRoutes.registrationConfirmation
  → ConfirmationScreen(registration: state.extra as Registration)
  → Fallback: _MissingRegistrationFallback (if extra missing)

AppRoutes.myRegistrations
  → MyRegistrationsScreen()
```

---

## Verification Checklist

### Event Detail CTA

| Check | Method | Expected |
|---|---|---|
| Not signed in → "Sign in to Register" | Open event detail while not authenticated | Button shows "Sign in to Register" |
| Tap "Sign in to Register" → Login | Tap button | Navigates to /login |
| Signed in + open → "Register" | Sign in, open event with status=open | "Register" button active |
| Full event → disabled | Open event with status=full | "Event Full" disabled button |
| Closed event → disabled | Open event with status=closed | "Registration Closed" disabled |
| Not open yet → disabled | Open event before registration_opens_at | "Registration Opens Soon" disabled |
| Cancelled event → banner | Open event with status=cancelled | Red banner + disabled button |

### Register Screen

| Check | Method | Expected |
|---|---|---|
| Alumni profile loads | Tap Register on open event | Profile shown, name/email/batch/branch |
| Profile load error → retry | Open with backend offline | Error shown with Retry button |
| Note field accepts text | Type in note field | Text appears, counter shows |
| Note max 500 chars | Type 501 chars | Capped at 500 |
| Already registered → error | Tap Register when already registered | "You are already registered" error card |
| Event full → error | Tap Register when event is full | "This event is full" error card |
| Success → confirmation | Tap Register successfully | Navigates to confirmation screen |
| Cancel → back | Tap Cancel | Pops to event detail |

### Confirmation Screen

| Check | Method | Expected |
|---|---|---|
| Registration number shown | Complete registration | NITKSAA-YYYY-XXXXXX visible |
| Join link shown (virtual) | Register for virtual event | Join URL in confirmation |
| No join link (physical) | Register for in-person event | Join link section absent |
| Email status shown | Any registration | sent/failed/skipped message |
| View My Registrations | Tap button | Navigates to /my-registrations |
| Back to Events | Tap button | Navigates to /events |

### My Registrations Screen

| Check | Method | Expected |
|---|---|---|
| Lists registrations | Open after registering | Registration card visible |
| Empty state | Open with no registrations | "No registrations yet" with Browse Events |
| Status badge | Registered row | Green "Registered" badge |
| Join link shown | Virtual registered event | Join URL visible in card |
| No join link | Physical or cancelled event | No join URL shown |
| Pull to refresh | Pull down | Re-fetches from API |
| Not authenticated error | Clear session, open | Error card shown |

---

## Known Limitations

- **"Already registered" is not pre-detected** — the event detail screen shows "Register" for all `open` events regardless of whether the user is already registered. The register screen handles the `already_registered` backend error gracefully with an error card. A future enhancement would call `GET /events/{id}/registration-eligibility` on event detail load.
- **No cancellation UI** — users cannot cancel registrations from the app. This requires a separate cancel flow.
- **Confirmation screen loses data on back nav** — `pushReplacement` is used to prevent going back to the in-progress register screen. If the user navigates away from confirmation, the registration object is lost. The My Registrations screen is the persistent record.
- **Event title in register route via query param** — if the query string is missing or malformed, "Event Registration" is shown as fallback. The event is still looked up correctly by ID.
