# NITKSAA Event App — Architecture Review Observations
**Reviewed:** Architecture Review v1.0
**Status:** 3 items requiring action, 2 minor observations

---

## Overall Assessment

The architecture is sound. Identity model, database separation, JWT exchange pattern, API-first approach, and deferred role model are all correct decisions. The weekly delivery plan is concrete and the explicit deferred list is a strength. No structural rework needed.

---

## Items Requiring Action

### 1. Remove `DELETE /api/v1/events/{event_id}`

**What:** Section 11.3 includes a hard delete endpoint for events. Open Question 7 asks whether to use hard delete, soft delete, or archive — but the endpoint already exists in the API spec.

**Why this matters:** Events are not isolated records. Once an event has registrations, confirmation emails, audit log entries, and potentially payment records attached, hard-deleting the event breaks all of them. Registrations lose their parent. Payment reconciliation becomes impossible. Audit history disappears. This directly contradicts the audit and privacy requirements in Sections 18 and 19.

Even for events with zero registrations, hard delete removes the creation and publishing history from the audit log.

**Recommendation:** Remove the DELETE endpoint now, before any admin discovers and uses it in staging. Events should only ever move to a `cancelled` or `archived` status — the record stays, the status changes, nothing downstream breaks. If there is a genuine need to purge empty draft events created during testing, that is a separate, explicitly guarded admin-only operation — not a general API endpoint.

**Resolve Open Question 7 as:** Soft state only. No hard delete.

---

### 2. API lifecycle does not reflect `Published → Registration Open` distinction

**What:** Requirements v1.2 (Section 6.4) defines a four-state event lifecycle: `Draft → Published → Registration Open → Archived/Cancelled`. Publishing makes an event visible but does not open registration. Opening registration is a separate deliberate action.

The architecture's publish flow (Section 16.2) goes directly from draft to published-and-registerable. The PATCH `/status` endpoint and the `events` table status field do not account for the intermediate state.

**Why this matters:** This is a real operational need, not a theoretical one. Event managers will want to announce NITKonnect or the Global Convention weeks before registration opens — visibility and registration are different decisions. If the status model is not built correctly now, adding this state later is a breaking API change for the Website, which will be consuming these public APIs directly.

**Recommendation:** Add `registration_open` as a distinct event status alongside `draft`, `published`, and `cancelled`. The PATCH `/status` endpoint should support the transition. This is a small addition now and a significant problem if deferred.

---

### 3. Close Open Question 2 — email confirmation in staging

**What:** Open Question 2 asks whether confirmation email is mandatory for demo acceptance or can be logged/stubbed locally.

**Why this matters:** Leaving this open going into Week 3 risks the deliverable being accepted with email only stubbed, which then becomes a problem the first time a real event runs. Email is not a nice-to-have — it is the primary confirmation channel for attendees and is explicitly required in the requirements.

**Recommendation:** Close this now. Email must work end-to-end in staging using an approved transactional email provider (SendGrid or equivalent). Local development may stub or log email. This is not a demo acceptance question — it is a Week 3 definition of done.

---

## Minor Observations

### 4. `event_members` table is undefined in the document

The DB schema in Section 9.2 lists `event_members` as a Week 1 migration table but it is not referenced or explained anywhere else in the document. The team will have to guess its purpose when they get there.

**Recommendation:** Add a one-line note clarifying its intent — whether it is for volunteer assignment, chapter-scoped event access, or something else. No structural change needed, just documentation.

---

### 5. Developer Diagnostics must be environment-gated

Section 17 correctly describes a useful diagnostics layer. No explicit guard against it running in production is mentioned.

**Recommendation:** Add a simple environment check so diagnostics endpoints are only available when `ENV != production`. One line of middleware. Worth doing in Week 2 before it becomes habit to leave it on.

---

## Decision Log — Recommended Resolutions

| Open Question | Recommended Resolution |
|---|---|
| Q2 — Email mandatory for demo? | Yes. Must work in staging. May be stubbed locally only. |
| Q7 — Hard delete vs soft delete? | Soft state only. No hard delete endpoint. |
| Others (Q1, Q3, Q4, Q5, Q6) | No blocker. Resolve at start of relevant week. |
