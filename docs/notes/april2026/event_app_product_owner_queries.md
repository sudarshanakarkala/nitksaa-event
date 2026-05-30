# Event App — Product Owner Queries

## Objective

Before implementation of the NITKSAA Event App proceeds further, we need to finalize a few architectural and operational decisions to ensure:

- consistency across products
- identity alignment
- reusable backend contracts
- maintainable authorization
- stable long-term architecture

The Event App must align with:
- NITKSAA Website
- NITKSAA Admin Portal
- Shared Firebase Identity
- Shared Cloud SQL Infrastructure

---

# 1. Primary Authentication Contract

Currently we have two different auth/JWT philosophies:

## Portal

- role
- alumni_id

## Website

- user_type
- ref_id
- is_admin

### Query

Which contract should become the canonical/shared contract for the Event App?

### Recommended Direction

Prefer Website-style contract:

```json
{
  "firebase_uid": "",
  "ref_id": "",
  "user_type": "alumni",
  "permissions": [],
  "is_admin": false,
  "display_name": "",
  "graduation_year": ""
}
```

This can later be mapped consistently across:
- Website
- Portal
- Event App

---

# 2. Event Admin Access Source

How should Event Admin permissions be managed?

## Options

### Option A
Reuse Website:
- is_admin
- permissions

### Option B
Reuse Portal:
- staff_admin
- super_admin

### Option C
Introduce scoped event permissions:
- event_admins table
- event-scoped permissions only

### Recommendation

Start with:
- staff_admin
- super_admin

Then introduce scoped event permissions only if required.

---

# 3. Alumni Identity Rule

Please confirm:

```text
ref_id = alumni_db.alumni.alumni_id
```

and:

- registrations.ref_id is a VALUE reference only
- no cross-database foreign keys
- no duplication of alumni identity tables

---

# 4. Non-Alumni Registration Policy

Can non-alumni users register for events?

## Options

### Option A
Alumni only

### Option B
Alumni + invited guests

### Option C
Public registration

### Recommendation for Alpha

Alumni only.

This simplifies:
- identity
- authorization
- attendee validation
- event operations

---

# 5. User Status Rules

Which alumni states should be allowed to register?

## Possible Rules

- Active only
- Unregistered allowed
- Pending allowed
- Blocked denied
- Deceased denied
- Inactive denied

### Recommendation

Allow:
- Active verified alumni only

Deny:
- Pending
- Blocked
- Deceased

---

# 6. Required JWT/User Context Fields

Please confirm the required user context for Event App APIs.

## Proposed Standard

```json
{
  "firebase_uid": "",
  "ref_id": "",
  "email": "",
  "display_name": "",
  "user_type": "",
  "role": "",
  "permissions": [],
  "graduation_year": "",
  "is_admin": false
}
```

---

# 7. Token Ownership Strategy

How should backend authentication work?

## Options

### Option A
Event backend issues its own internal JWT after Firebase token exchange

### Option B
Reuse Website JWT directly

### Option C
Validate Firebase token on every API request

### Recommendation

Use:
- Firebase token exchange
- internal backend JWT

Reason:
- backend consistency
- controlled expiration
- reduced Firebase verification overhead
- alignment with existing architecture

---

# 8. Event Admin Application Scope

Should Event Admin workflows be:

## Option A
Inside Flutter Event App

## Option B
Separate React Admin Portal

## Recommendation

Recommended:
- Flutter = attendee-facing app
- React Admin Portal = operational/admin workflows

Reason:
- operational simplicity
- better admin productivity
- easier table/export workflows
- easier audit controls

---

# 9. QR Check-In Operational Flow

Please confirm expected operational flow:

## Example Flow

1. Attendee registers
2. QR generated
3. Volunteer scans QR
4. Backend validates attendee
5. Check-in status updated
6. Duplicate scans prevented
7. Manual override supported

### Questions

- Should duplicate check-ins be blocked?
- Should admins override check-in?
- Should volunteers have restricted permissions?
- Should offline fallback exist for Alpha?

### Recommendation

For Alpha:
- online-only check-in
- duplicate scan prevention
- manual override for admins

---

# 10. Event Data Ownership

Please confirm source-of-truth ownership:

| Data Type | Source of Truth |
|---|---|
| Alumni identity | alumni_db |
| Event data | events_db |
| Sessions | events_db |
| Registrations | events_db |
| Check-ins | events_db |
| Auth identity | Firebase |

---

# 11. Deployment Model

Please confirm deployment direction:

## Proposed

- Flutter Event App
- FastAPI Event Backend
- Cloud Run
- Same Cloud SQL instance
- Same Firebase project
- Same Secret Manager strategy

---

# 12. API Standardization

Please confirm if Event APIs should follow existing FastAPI conventions:

## Existing Style

### Success
```json
{
  "status": "ok"
}
```

### Error
```json
{
  "detail": "message"
}
```

### Recommendation

Reuse existing API response style for consistency.

---

# 13. UI/Theme Alignment

The Event App will remain a separate Flutter application.

However:
- theme
- spacing
- typography
- navigation philosophy
- cards
- filters
- admin workflows

should remain visually cohesive with:
- nitksaa-website
- nitksaa-portal-v2

Reference inspiration:
- Dreamcast event experience
- Existing NITKSAA product ecosystem

---

# Final Goal

The Event App should:

Replace Dreamcast (white-labelled for NITKonnect 2026)
for NITKonnect 2027 and all future events.

while remaining:
- operationally simple
- architecturally maintainable
- identity-consistent
- reusable across future NITKSAA initiatives
