# NITKSAA Event App — Architecture Alignment Reference

This document consolidates all architecture questions, product owner answers, final decisions, and implementation action items for future reference.

## Q1 — Primary Auth Contract

### Product Owner Answer
Use website-style contract.
Do not use portal role taxonomy.
Add permissions[].
Retire role.

### Final Decision
Use:
- firebase_uid
- ref_id
- user_type
- is_admin
- permissions[]

### Action Items
- Align Event App auth with website
- Remove role dependency
- Reuse website JWT philosophy

---

## Q2 — Event Admin Access Source

### Product Owner Answer
Use website is_admin.
Do not use portal staff_admin/super_admin.
Scoped permissions later if needed.

### Final Decision
Alpha:
- is_admin only

### Action Items
- Use simple binary admin access
- Defer scoped delegation

---

## Q3 — Alumni Identity Rule

### Product Owner Answer
ref_id = alumni_db.alumni.alumni_id
Value reference only.
No cross-database foreign keys.

### Final Decision
Use value references only.

### Action Items
- Keep alumni_db separate
- Keep events_db separate

---

## Q4 — Non-Alumni Registration Policy

### Product Owner Answer
Alumni only for Alpha.

### Final Decision
Verified alumni only.

### Action Items
- Defer public/non-alumni registration

---

## Q5 — User Status Rules

### Product Owner Answer
Only active verified alumni.
Blocked/pending/inactive/deceased denied.

### Final Decision
Enforce active alumni only.

### Action Items
- Validate during auth/JWT issuance

---

## Q6 — Required JWT Fields

### Product Owner Answer
Match website shape.
Do not normalize role.
Do not include is_content_editor.

### Final Decision
JWT fields:
- firebase_uid
- ref_id
- user_type
- permissions
- is_admin

### Action Items
- Keep JWT minimal and website-aligned

---

## Q7 — Token Ownership Strategy

### Product Owner Answer
Firebase exchange → internal JWT.
Do not reuse website JWT.

### Final Decision
Each backend owns its JWT lifecycle.

### Action Items
- Build auth exchange flow later

---

## Q8 — Event Admin Application Scope

### Product Owner Answer
Flutter for attendees.
React Admin Portal for operations.

### Final Decision
Separate attendee and admin experiences.

### Action Items
- Keep operational tooling in React

---

## Q9 — QR Check-In Flow

### Product Owner Answer
Online-only.
Duplicate prevention.
Admin override.
Log every scan attempt.

### Final Decision
Add scan audit logging.

### Action Items
Create check_in_attempts logging.

---

## Q10 — Event Data Ownership

### Product Owner Answer
alumni_db = identity
events_db = event business data
Firebase = auth

### Final Decision
Strict ownership boundaries.

### Action Items
- Do not extend alumni_db with event data

---

## Q11 — Deployment Model

### Product Owner Answer
Use same stack:
- Cloud Run
- Cloud SQL
- Firebase
- Secret Manager

### Final Decision
Reuse existing infrastructure patterns.

### Action Items
- Avoid infra divergence

---

## Q12 — API Standardization

### Product Owner Answer
Reuse existing FastAPI response envelope.

### Final Decision
Keep API style consistent.

### Action Items
Success:
{ "status": "ok" }

Error:
{ "detail": "message" }

---

## Q13 — UI / Theme Alignment

### Product Owner Answer
Maintain cohesion, not pixel-perfect parity.
Use website spacing/card philosophy as reference.

### Final Decision
Flutter should feel consistent while remaining Material-native.

### Action Items
- Reuse tone and density patterns
- Avoid CSS-style duplication

---

# Approved Alpha Scope

Approved:
- events_db schema
- FastAPI backend
- event CRUD
- registration flow
- QR token flow
- QR check-in flow
- scan attempt logging
- curl/Postman proof-of-flow

---

# Deferred Items

Deferred:
- payments
- waitlist
- analytics dashboard
- non-alumni support
- offline sync
- push notifications
- microservices

---

# Recommended Immediate Next Step

1. Backend vertical slice
2. events_db schema
3. FastAPI proof-of-flow
4. curl/Postman validation
5. Then Flutter + React integration
