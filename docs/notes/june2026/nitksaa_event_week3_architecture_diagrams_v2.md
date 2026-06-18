# NITKSAA Event App — Week 3 Architecture Diagrams v2.0

**Version:** 2.0  
**Status:** Revised for approval before coding  
**Sprint:** Week 3 — Registration, Confirmation Email, Protected Join Link, Diagnostics UI

---

## 1. System Context

```text
┌────────────────────────┐
│ Firebase Authentication │
└───────────┬────────────┘
            │ Firebase ID token
            ▼
┌────────────────────────┐
│ FastAPI Auth API        │
│ POST /api/v1/auth/firebase
└───────────┬────────────┘
            │ backend JWT
            ▼
┌──────────────────────────────────────────────────────────┐
│ Flutter Event App — Developer Diagnostics                │
│ Registration Flow reference UI                           │
│ - Autofill preview                                       │
│ - Eligibility state                                      │
│ - Register action                                        │
│ - Confirmation preview                                   │
│ - Join-link reveal preview                               │
└───────────┬──────────────────────────────────────────────┘
            │ /api/v1 protected APIs
            ▼
┌──────────────────────────────────────────────────────────┐
│ FastAPI Event Backend                                    │
│ - Alumni API                                             │
│ - Registration API                                       │
│ - Email service                                          │
│ - Diagnostics API                                        │
└───────────┬───────────────────────┬──────────────────────┘
            │                       │
            ▼                       ▼
┌─────────────────────┐   ┌─────────────────────┐
│ events_db            │   │ alumni_db            │
│ events               │   │ alumni profile       │
│ event_users          │   │ active status        │
│ registrations        │   │ batch/branch/phone   │
│ event_audit_log      │   └─────────────────────┘
└───────────┬─────────┘
            │
            ▼
┌─────────────────────┐
│ Email Provider       │
│ log/sendgrid/etc.    │
└─────────────────────┘
```

---

## 2. Registration Flow

```text
User logged in
    │
    ▼
GET /api/v1/alumni/me
    │
    ├── 403 alumni_required ─────▶ Show alumni-only message
    ├── 403 alumni_not_active ───▶ Show contact support message
    └── 200 alumni profile
            │
            ▼
GET /api/v1/events/{event_id}/registration-eligibility
            │
            ├── event_full ──────────────▶ Disable register
            ├── registration_closed ─────▶ Disable register
            ├── registration_not_open_yet ▶ Disable register
            ├── already_registered ──────▶ Show registered state
            └── can_register
                    │
                    ▼
          User confirms profile
                    │
                    ▼
POST /api/v1/events/{event_id}/register
                    │
                    ├── 409 duplicate/full/closed
                    │       └── Show matching UI state
                    │
                    └── 201 registration created
                            │
                            ▼
                  Send confirmation email
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
          email sent              email failed
                │                       │
                ▼                       ▼
Show confirmation       Show confirmation + email warning
```

---

## 3. Protected Join-Link Flow

```text
Public event detail
GET /api/v1/events/public/{event_id}
        │
        ▼
Returns event details
Does NOT return virtual_url/join_url

Authenticated registered user
GET /api/v1/events/{event_id}/my-registration
        │
        ├── no active registration
        │       └── join_url = null
        │
        └── active registration + virtual event
                └── join_url = event.virtual_url
```

---

## 4. Database Interaction

```text
RegistrationService.register_for_event()
    │
    ├── read current_user from JWT
    │
    ├── read event_user from events_db
    │
    ├── read alumni profile from alumni_db
    │
    ├── validate active alumni
    │
    └── transaction in events_db
            │
            ├── lock event row
            ├── count active registrations
            ├── validate capacity
            ├── validate duplicate
            ├── insert registration snapshot
            └── commit
                    │
                    ▼
             EmailService.send()
                    │
                    ▼
          update email status
```

---

## 5. Email Flow

```text
Registration committed
        │
        ▼
Build email payload
        │
        ├── Physical event
        │       └── include venue/map details
        │
        └── Virtual event
                ├── include join link if approved
                └── otherwise say link is available after login
        │
        ▼
EmailService
        │
        ├── EMAIL_MODE=log
        │       └── write local log / diagnostics result
        │
        └── EMAIL_MODE=send
                └── send through provider
        │
        ▼
Update registration email status
```

---

## 6. Developer Diagnostics UI Flow Map

```text
Developer Diagnostics
└── Registration Flow
    ├── Alumni Autofill
    │   └── GET /api/v1/alumni/me
    ├── Eligibility
    │   └── GET /api/v1/events/{event_id}/registration-eligibility
    ├── Registration Screen Preview
    │   └── profile + event summary
    ├── Register Action
    │   └── POST /api/v1/events/{event_id}/register
    ├── Confirmation Screen Preview
    │   └── registration number + event summary
    ├── Email Result
    │   └── sent / failed / logged
    ├── My Registration
    │   └── GET /api/v1/events/{event_id}/my-registration
    ├── Join Link Reveal
    │   └── registered virtual event only
    └── Negative States
        ├── already registered
        ├── event full
        ├── registration closed
        ├── registration not open yet
        └── alumni inactive
```

---

## 7. Week 3 vs Week 4 Boundary

```text
Week 3
├── Backend registration APIs
├── Alumni autofill API
├── Confirmation email
├── Protected join-link reveal
├── Diagnostics UI reference flows
└── No production React Admin attendee screens

Week 4
├── Admin attendee list
├── Search/filter attendees
├── CSV export UI
├── Staff walkthrough
└── Demo hardening
```
