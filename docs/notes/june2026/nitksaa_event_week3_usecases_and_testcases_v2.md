# NITKSAA Event App — Week 3 Use Cases and Test Cases v2.0

**Version:** 2.0  
**Status:** Revised for approval before coding  
**Sprint:** Week 3 — Registration, Confirmation Email, Protected Join Link, Diagnostics UI

---

## 1. Actors

| Actor | Description |
|---|---|
| Public visitor | User browsing events without login |
| Authenticated alumni | Firebase-authenticated user mapped to active alumni record |
| Non-alumni user | Firebase-authenticated user with `user_type = other` |
| Inactive alumni | Alumni record exists but is inactive/suspended/not eligible |
| Event admin | Admin user; production Week 3 UI not required |
| Frontend developer | Uses Developer Diagnostics UI as registration flow reference |

---

## 2. Use Cases

### UC-01 — Alumni Profile Autofill

**Goal:** Alumni profile loads from `alumni_db`.

Flow:

```text
User logs in
→ Developer Diagnostics opens Registration Flow
→ GET /api/v1/alumni/me
→ API returns name, email, phone, batch year, branch
→ Diagnostics shows read-only registration profile card
```

Acceptance:

- `fullname` shown
- `email` shown
- `batch_year` shown
- `branch` shown
- inactive/non-alumni blocked

---

### UC-02 — Successful Physical Event Registration

Flow:

```text
Active alumni opens Breakfast Club event
→ Eligibility says can_register
→ User confirms profile
→ POST /events/{id}/register
→ Registration created
→ Registration number generated
→ Confirmation email sent/logged
→ Venue/map link shown
```

Expected UI:

```text
You're registered.
Registration number: NITKSAA-2026-000101
Venue: Bangalore
Map: visible if available
Add to calendar prompt: visible
```

---

### UC-03 — Successful Virtual Event Registration

Flow:

```text
Active alumni opens Webinar event
→ Eligibility says can_register
→ User confirms profile
→ POST /events/{id}/register
→ Registration created
→ Confirmation email sent/logged
→ Join link becomes visible from authenticated endpoint
```

Expected UI:

```text
You're registered.
Join link visible.
Add to calendar prompt visible.
```

Public API must still hide join link.

---

### UC-04 — Duplicate Registration Guard

Flow:

```text
Registered alumni clicks Register again
→ Backend detects active registration
→ 409 already_registered
or eligibility returns already_registered
```

Expected UI:

```text
You're already registered.
View Registration
```

---

### UC-05 — Event Full

Flow:

```text
capacity = registered_count
→ User attempts registration
→ 409 event_full
```

Expected UI:

```text
Event is full.
Register button disabled.
```

---

### UC-06 — Registration Closed

Flow:

```text
current time > registration_closes_at
→ User attempts registration
→ 409 registration_closed
```

Expected UI:

```text
Registration closed.
Register button disabled.
```

---

### UC-07 — Registration Not Open Yet

Flow:

```text
current time < registration_opens_at
→ User attempts registration
→ 409 registration_not_open_yet
```

Expected UI:

```text
Registration opens soon.
Register button disabled.
```

---

### UC-08 — Draft/Cancelled Event Blocked

Flow:

```text
event.status != published
→ User attempts registration
→ 409 event_not_published
```

Expected UI:

```text
Event is not available for registration.
```

---

### UC-09 — Non-Alumni Blocked

Flow:

```text
user_type = other
→ GET /alumni/me or POST /register
→ 403 alumni_required
```

Expected UI:

```text
Only NITKSAA alumni can register for this event.
```

---

### UC-10 — Inactive Alumni Blocked

Flow:

```text
alumni record inactive
→ POST /register
→ 403 alumni_not_active
```

Expected UI:

```text
Your alumni profile is not active for registration. Please contact support.
```

---

### UC-11 — Confirmation Email Sent

Flow:

```text
Registration saved
→ Email provider sends confirmation
→ registration.confirmation_email_status = sent
```

Expected diagnostics:

```text
Email status: sent
Provider: log/sendgrid
Sent at: timestamp
```

---

### UC-12 — Confirmation Email Failed But Registration Saved

Flow:

```text
Registration saved
→ Email provider fails
→ registration remains registered
→ email status failed
```

Expected UI:

```text
You're registered.
Confirmation email could not be sent.
Please save your registration number.
```

---

### UC-13 — My Registration Detail Shows Join Link

Flow:

```text
Registered user calls GET /events/{id}/my-registration
→ Event is virtual
→ join_url returned
```

Expected:

- Registered user sees join link.
- Unregistered user does not see join link.
- Public API never shows join link.

---

### UC-14 — My Registrations List

Flow:

```text
User opens My Registrations diagnostics
→ GET /my/registrations
→ API returns event summaries and access data
```

Expected:

- List shows event title/date/status.
- Virtual registered event includes join link.
- Physical registered event includes venue/map.

---

### UC-15 — Developer Diagnostics as UI Reference

Flow:

```text
Developer opens diagnostics
→ Runs each registration scenario
→ Sees API + sample UI state
```

Expected:

- Frontend developer can implement production theme from diagnostics examples.
- Diagnostics remains debug/development-only.

---

## 3. Test Cases

| ID | Test Case | Preconditions | Steps | Expected |
|---|---|---|---|---|
| TC-001 | Alumni autofill success | Active alumni logged in | GET `/alumni/me` | 200 with name/email/batch/branch |
| TC-002 | Alumni autofill non-alumni | Non-alumni logged in | GET `/alumni/me` | 403 `alumni_required` |
| TC-003 | Inactive alumni blocked | Inactive alumni logged in | POST `/register` | 403 `alumni_not_active` |
| TC-004 | Register physical event | Published physical event open | POST `/register` | 201 registered, map link available |
| TC-005 | Register virtual event | Published virtual event open | POST `/register` | 201 registered, join link in access |
| TC-006 | Public virtual detail hides join | Virtual event published | GET public detail | 200 without `virtual_url`/`join_url` |
| TC-007 | Registered virtual detail reveals join | User registered | GET `/my-registration` | 200 with `join_url` |
| TC-008 | Unregistered virtual detail hides join | User not registered | GET `/my-registration` | 200, `join_url = null` |
| TC-009 | Duplicate registration blocked | User already registered | POST `/register` again | 409 `already_registered` |
| TC-010 | Capacity full blocked | count == capacity | POST `/register` | 409 `event_full` |
| TC-011 | Registration closed blocked | current time after close | POST `/register` | 409 `registration_closed` |
| TC-012 | Registration not open blocked | current time before open | POST `/register` | 409 `registration_not_open_yet` |
| TC-013 | Draft event blocked | event status draft | POST `/register` | 409 `event_not_published` |
| TC-014 | Cancelled event blocked | event status cancelled | POST `/register` | 409 `event_not_published` |
| TC-015 | Dynamic registered count | Event has registrations | GET public/admin event | count from active registrations |
| TC-016 | Email sent | Email mode send/log configured | POST `/register` | email status `sent` or logged |
| TC-017 | Email failure safe | Provider forced fail | POST `/register` | 201 registration, email status `failed` |
| TC-018 | My registrations list | User has registrations | GET `/my/registrations` | 200 list |
| TC-019 | Diagnostics route guarded | Production env | GET diagnostics | 404/403 |
| TC-020 | Diagnostics visible in dev | Development env | GET diagnostics | 200 |
| TC-021 | Race condition capacity | One seat left, two users | concurrent register | one success, one `event_full` |
| TC-022 | Registration number unique | Multiple registrations | POST `/register` | unique numbers |
| TC-023 | Audit registration created | Successful registration | inspect audit | action recorded |
| TC-024 | Audit email failed | Forced email failure | inspect audit | failure recorded, no token/PII leak |
| TC-025 | Add to calendar payload | Successful registration | inspect response | calendar metadata present |

---

## 4. Manual Demo Script

### Demo A — Breakfast Club

```text
1. Open diagnostics.
2. Select Breakfast Club event.
3. Run alumni autofill.
4. Run eligibility.
5. Confirm profile.
6. Register.
7. Show confirmation number.
8. Show email status.
9. Show venue/map.
10. Show Add to Calendar prompt.
```

### Demo B — Webinar

```text
1. Select Webinar event.
2. Run alumni autofill.
3. Register.
4. Show confirmation email status.
5. Call my-registration.
6. Show join link visible.
7. Call public detail.
8. Confirm join link hidden publicly.
```

### Demo C — Negative Cases

```text
1. Duplicate registration.
2. Full event.
3. Registration closed.
4. Non-alumni blocked.
5. Email failure handled.
```
