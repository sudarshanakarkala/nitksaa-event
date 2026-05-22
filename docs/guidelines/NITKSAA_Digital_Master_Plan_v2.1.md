# NITKSAA Digital Ecosystem — Master Plan
**Version:** 2.1 · **Date:** April 2026  
**Framing:** "The digital operating system for the NITK community"

---

## 1. Actual State — April 2026

Three streams of work are live or underway. The ecosystem is further along than it looks from any single app.

### Admin Portal — Live, Production

FastAPI + React · Cloud Run · PostgreSQL (`alumni_db`) · 49,861 records

| Capability | Status |
|---|---|
| Directory, search, filters, card + table view | ✅ |
| Role-aware record editing (staff / super admin) | ✅ |
| Alumni self-service (profile + privacy toggles) | ✅ |
| Firebase auth — Google OAuth + magic link | ✅ |
| Admin TOTP 2FA | ✅ |
| Export CSV with purpose + audit | ✅ |
| Audit log viewer | ✅ |
| Admin user management | ✅ |
| Alumni map (zoom layer, static geocache) | ✅ |
| Dark / light theme | ✅ |
| Self-registration | ❌ |
| Registration review queue | ❌ |
| Alumni-to-alumni contact | ❌ |
| Operational dashboard | ❌ |
| Campaign / bulk email builder | ❌ |

**Handover status:** Association inherits operational responsibility. GCP ownership transfer pending (not time-boxed to Jun 29 — transfer when governance is ready, upgrade billing before free trial expires).

---

### Website — Live, Deployed, Actively Being Built

FastAPI + React · Cloud Run · PostgreSQL (`website_db` + read from `alumni_db`)

This is a separate app, separate Cloud Run service, separate DB, same Firebase project, same Cloud SQL instance.

| Module | Status |
|---|---|
| Identity & Auth (Firebase, JWT, route guards) | ✅ |
| Alumni Directory (search, filters, PersonCard, PersonModal) | ✅ |
| Communities (batch years, chapters, SIGs — 76 seeded, 49K+ memberships) | ✅ |
| Stories / Articles (feed, editor, review workflow, 79-tag system) | ✅ |
| Mentorship (complete: schema, API, full frontend, flag/close workflow) | ✅ |
| Career Opportunities (backend + frontend complete) | ✅ |
| Contact Requests (alumni peer-to-peer contact, 30-day connection window) | ✅ |
| Navigation redesign (six primary links, More ▾, shield, bell, avatar) | ✅ |
| Dark / light theme | ✅ |
| Sticky filters across all directory pages | ✅ |
| Own-card visual treatment across all card types | ✅ |
| Non-Alumni Directory | ❌ |
| Alumni profile self-editing (blocked on Alumni Service) | ❌ |
| Startup / Innovation Ecosystem | ❌ |
| Ecosystem Initiatives | ❌ |
| Website Administration (unified admin area + ops dashboard) | ❌ |
| Navbar Notifications (proper notifications system) | ❌ |
| "Me" Page (unified personal activity view) | ❌ |
| Enterprise Foundation (security, audit, email stubs, NITIKA stub, 404/footer) | ❌ |

**Design principle** (from guiding doc, governs all decisions): The website is *connective tissue* — verified identity, trusted discovery, structured first contact. Once a connection is made, work moves to email / WhatsApp / LinkedIn. The website records that the connection happened; it does not host what follows.

---

### Event App — Starting Now

New team (2 resources). Greenfield build.  
**Target:** Solid working version by **Sep 2026**. Production go-live **Feb 2027**.  
**Goal:** Replace Dreamcast (white-labelled for NITKonnect 2026) for NITKonnect 2027 and all future events.

Status: Planning. No code yet.

---

## 2. Architecture — Where This Is Heading

The three apps share one Firebase project (identity anchor), one Cloud SQL instance (two DBs now, three eventually), and will share one services layer once the Alumni Service is extracted.

```
┌─────────────────────────────────────────────────────────────────┐
│                      NITK Community                             │
│        Alumni · Students · Faculty · Partners · Public          │
└───────────┬──────────────────┬──────────────────┬──────────────┘
            │                  │                  │
      ┌─────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐
      │ Admin App  │    │   Website   │    │  Event App  │
      │            │    │             │    │             │
      │ Internal   │    │ Member hub  │    │ NITKonnect  │
      │ operations │    │ + public    │    │ Breakfast   │
      │ & data mgmt│    │ face        │    │ Webinars    │
      └─────┬──────┘    └──────┬──────┘    └──────┬──────┘
            │                  │                  │
            └──────────────────┼──────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                    Alumni Service (planned)                      │
│   Sole owner of alumni_db. Enforces AAA on every operation.     │
│   All apps call via HTTP — no direct DB connections to alumni_db │
│                                                                  │
│   Cut-over point: backend/src/services/alumni.py                │
│   (fetch_alumni_info already extracted — single file changes)   │
└──────────────────────────────┬──────────────────────────────────┘
                               │
           ┌───────────────────┼──────────────────┐
     ┌─────▼──────┐     ┌──────▼──────┐     ┌─────▼──────┐
     │ alumni_db  │     │ website_db  │     │ events_db  │
     │ (current)  │     │ (current)   │     │ (new)      │
     └────────────┘     └─────────────┘     └────────────┘
```

### Identity — One Anchor Across All Apps

`firebase_uid` is already the stable auth anchor for both the Admin Portal (alumni) and the Website. The Event App will use the same Firebase project. An alumnus logs in once via Google OAuth or magic link; all three apps recognise the same UID without re-authentication.

JWT claims evolve over time:
- **Today** (portal): `firebase_uid`, `role`, `alumni_id`  
- **Today** (website): `firebase_uid`, `user_type`, `ref_id`, `graduation_year`, `is_admin`, `is_content_editor`
- **Target** (unified): `firebase_uid`, `role`, `ref_id`, `graduation_year`, `app_permissions[]`

Reconciling the two JWT shapes is a mid-term task — not blocking for any current work.

### The Alumni Service — The Key Unifier

The Alumni Service is the planned extracted backend that becomes the sole owner of `alumni_db`. It enforces authentication, authorisation, and audit logging on every operation. Currently both apps read `alumni_db` directly (portal's `alumni.py` router, website's `fetch_alumni_info()` function).

The cut-over point on the website is already isolated: `backend/src/services/alumni.py`. When the Alumni Service is built, that one file changes — no other module is affected. The portal's router-level access to `alumni_db` will need a similar refactor but is less isolated today.

**The Alumni Service is not blocking any current work.** It becomes necessary when:
- Alumni need to self-edit profiles from the website (write path to `alumni_db` needs AAA)
- The Event App needs to resolve alumni identity
- The audit log needs a unified cross-app view of alumni record changes

---

## 3. The Three Apps in Detail

### 3a. Admin Portal — What's Left to Build

The portal is functionally complete for internal operations. Three features are needed before it can be opened to alumni as `directory.nitkalumni.in`.

**Phase 1 additions (in priority order):**

**1. Self-registration** — An alumnus not yet in the DB can submit their details. The submitted record enters a `Pending` state. The admin sees it in the review queue. On approval, the record transitions to `Active` and the alumnus can log in.

Design decisions needed:
- What fields does the self-registration form collect? (Suggest: name, graduation year, branch, degree, email, LinkedIn — enough to match against existing records)
- What happens if the submitted email already exists in `alumni_db`? (Suggest: treat as a login attempt, not a new registration)
- Is there a matching/deduplication step before the record enters the queue? (Suggest: fuzzy match on name + year and surface potential duplicates to the reviewing admin)

**2. Registration review queue** — An admin-facing page showing all `Pending` records. Per-record actions: approve (→ `Active`), reject (with reason), merge with existing record (for duplicates).

**3. Alumni-to-alumni contact** — Members can send a message to a peer whose record shows `show_email = true`. Implementation:
- "Contact" button on alumni cards (visible only to logged-in alumni, only when recipient has opted in)
- Backend endpoint sends email via NITKSAA's domain — the sender never sees the raw email address
- Email arrives at recipient with reply-to pointing to sender — reply goes direct, NITKSAA is not in the loop after the introduction
- Rate-limited (5 outbound contact requests per member per day)
- Logged in audit trail
- No new DB tables needed

**Phase 1 additions (after portal opens):**

**4. Operational dashboard** — A second dashboard view showing platform activity rather than data statistics. Key panels: registration queue depth, login activity (new + returning), recent audit events, export activity, campaign delivery status. All sourced from existing tables — no new infrastructure.

**5. Campaign / bulk email builder** — The `campaigns` and `campaign_recipients` tables were created in the original DB migration and have been sitting empty. The admin portal is the right place to build the cohort selector, compose view, and send trigger. A mail service (SendGrid or equivalent) needs to be wired before this can go live.

**Governance — GCP and ownership:**  
The GCP free trial expires Jun 29 2026. The right response is not to rush the handover — it is to upgrade the billing account before that date (a 5-minute task) so the services continue running without interruption. The actual ownership transfer (GCP project, Firebase project, GitHub repo, domain DNS) is a governance milestone that happens when the association has the right people in place to receive it. Do not let an infrastructure billing date drive a governance decision.

---

### 3b. Website — What's Being Built Next

**Enterprise foundation (before next feature module):**
Security hardening, email stubs, website audit log, content reporting, analytics events table, NITIKA stub, 404 page + footer + legal placeholders. See Planning doc Sections 19–25 and Architecture doc Section 9 for detail.

**Then: Navbar Notifications (Section 17)**
Proper notifications system replacing the contact-count stopgap on the bell icon.

**Then: Startup / Innovation Ecosystem (Section 8)**
Alumni entrepreneurship visibility. Founder directory, startup showcase, investor connections, advisory opportunities. New tables: `startups`, `startup_founders`. Nav placeholder already in place.

**Then: Website Administration (unified, Section 13)**
The action queue today is distributed across pages. A unified admin area aggregates all open items. The ops dashboard gives NITKSAA leadership a platform-health view.

**Deferred (needs Alumni Service first):**
- Alumni profile self-editing from the website
- Consistent cross-app audit trail for alumni record changes

**Design decisions still open:**
- Non-alumni directory (faculty, partners) — scope and privacy rules undefined
- Ecosystem Initiatives — scope boundary with Research & Ventures needs definition before building
- Research & Ventures — Phase 3, no schema yet

---

### 3c. Event App — Build Plan

**What we're replacing:** Dreamcast, white-labelled for NITKonnect 2026. The replacement must cover everything Dreamcast did plus be integrated with NITKSAA identity so alumni don't need a separate account.

**Milestones:**
- **Sep 2026** — solid working version (feature-complete, tested, demo-ready)
- **Feb 2027** — production go-live (NITKonnect 2027 planning cycle starts)

**Events to support:** NITKonnect · Bangalore Breakfast Club · Webinars · Chapter events · Reunions · Future initiatives

**Minimum viable for Sep:**

| Capability | Notes |
|---|---|
| Event creation by staff / chapter coordinators | Title, description, date, location (physical or virtual), capacity, registration deadline |
| Public event listing page | No login required to view |
| Event detail page | Schedule, speakers, sponsors, registration CTA |
| Member registration | Login required; autofill from `alumni_db` via Alumni Service (or direct read initially) |
| Registration confirmation email | Via mail service |
| Attendee list (admin view) | With export |
| Session / track support | NITKonnect has parallel tracks |
| QR code check-in | Mobile-friendly — this is used on the day |
| Post-event: recording links + photo gallery | Simple link list, not a media host |

**What can wait for Feb:**

| Capability | Notes |
|---|---|
| Payment / ticketed events | Only if a paid event is planned before Feb |
| Chapter-specific event series | Admin can manage manually until this is built |
| Waitlist management | Manual process initially |
| Speaker / sponsor management portal | Managed in a spreadsheet until this is built |
| Event analytics dashboard | Post-event reporting |

**Identity:** Same Firebase project. An alumnus authenticated on the website is automatically authenticated on the event app — same UID, same JWT issuer. No separate credentials.

**Database:** New `events_db` on the same Cloud SQL instance. Key tables: `events`, `sessions`, `registrations`, `attendees`, `check_ins`.

**Cross-app reference:** `registrations.ref_id` stores the `alumni_db.alumni_id` for verified alumni registrations. This is a value reference (not a FK across DBs) — the pattern established by the website.

**Tech stack recommendation:** Same pattern as Admin Portal and Website — FastAPI backend, React frontend, Cloud Run, same Cloud SQL instance. The two new resources should study the website's patterns (CSS layer architecture, FilterSidebar, useFilters, the modal shell) so the three frontends feel cohesive.

---

## 4. Phased Delivery Timeline

```
APR 2026         MAY 2026         JUN 2026         SEP 2026         FEB 2027
    │                │                │                │                │
    ├── ADMIN PORTAL ─────────────────────────────────────────────────────
    │   Self-registration ────┤
    │   Review queue     ────┤
    │   Contact feature  ─────────┤
    │   Portal opens to alumni        ◆ directory.nitkalumni.in
    │   Ops dashboard    ─────────────────┤
    │   Campaign builder ─────────────────────┤
    │
    ├── WEBSITE ──────────────────────────────────────────────────────────
    │   Enterprise foundation ───┤
    │   Notifications + Me page ──────┤
    │   Startup module   ─────────────────┤
    │   Admin area (unified) ─────────────────────┤
    │   Alumni Service   ──────────────────────────────────────┤ (after Phase 2 stable)
    │
    ├── EVENT APP ────────────────────────────────────────────────────────
    │   Foundation + auth             ◆ start
    │   Event creation + listing ──────────────┤
    │   Registration + check-in ────────────────────┤
    │   Working version              ◆ Sep 2026
    │   Hardening + event content ─────────────────────────────┤
    │   NITKonnect 2027 go-live                               ◆ Feb 2027
    │
    └── GCP / INFRA ──────────────────────────────────────────────────────
        Billing account upgrade ─┤ (before Jun 29)
        Domain setup         ─────────┤
        Ownership transfer   ──────────── (when governance is ready, no hard date)
```

---

## 5. The Alumni Service — When and How

This is the most architecturally significant piece and the one most likely to be deferred too long or rushed at the wrong time.

**Don't build it yet.** The website's `fetch_alumni_info()` pattern (isolated in `alumni.py`, shared by mentorship, career, and contact modules) is the right interim approach. It is a clean seam. The Admin Portal's direct `alumni_db` access is messier but not broken.

**Build it when one of these is true:**
- Alumni need to self-edit their profile from the website (requires a write path with AAA)
- The Event App needs alumni identity at a scale where direct DB reads become a problem
- A fourth app needs alumni data and adding a third direct DB connection feels wrong

**What it looks like:**
A FastAPI service, deployed on Cloud Run, that owns `alumni_db` exclusively. All other apps call it via authenticated HTTP. The website's cut-over is `backend/src/services/alumni.py` — `fetch_alumni_info()` changes from "query alumni_db directly" to "call Alumni Service API." No other module changes.

**The Admin Portal's refactor** is more involved because the portal's alumni endpoints are the Alumni Service in embryonic form — they do search, edit, export, and audit. The eventual shape is: Admin Portal becomes a thin client, and its current `alumni.py` router becomes the Alumni Service.

---

## 6. What Each Team Focuses On

### Padmanand (solo, Admin Portal + Website + Architecture)

Near-term (April–June):
1. Website: enterprise foundation (Sections 19–25 in website planning doc)
2. Admin Portal: self-registration + review queue
3. Admin Portal: alumni-to-alumni contact
4. Website: notifications + Me page
5. GCP billing account upgrade before Jun 29

Mid-term (June–September):
6. Admin Portal opens at `directory.nitkalumni.in`
7. Website: startup / innovation ecosystem
8. Admin Portal: operational dashboard
9. Event App: architecture guidance + shared identity setup for new team

### Event App Team (2 new resources)

Month 1 (April): Setup + foundation
- GCP / Cloud Run project setup (under same project or new — decide)
- Firebase integration (same project, same auth)
- `events_db` schema design and first migration
- Event CRUD API + basic listing page

Month 2–3 (May–June): Core features
- Event detail page
- Member registration flow
- Registration confirmation email
- Admin attendee list + export

Month 4–5 (July–August): Production features
- Session / track support
- QR code check-in (mobile-friendly)
- Post-event content (recording links, gallery)
- End-to-end test of NITKonnect-scale event

September: Working version milestone
- Feature-complete demo
- Load tested
- Admin walkthrough for NITKSAA team

October–January: Hardening, content, NITKonnect prep
- Real event content loaded
- Volunteer / speaker flow if needed
- Integration with website event listing (Phase 3, section 11 in website planning doc)

February 2027: Go-live

---

## 7. Cross-Cutting Decisions

### Contact Each Other — Which App Owns It?

The Admin Portal has the email data. The Website has the member-to-member interaction model. The website has now built contact requests (peer-to-peer, firebase_uid keys, privacy-gated). The portal will build a simpler version (email-based, rate-limited, no new DB tables) to unblock the portal opening to alumni. Keep the two implementations consistent in privacy behaviour even if the UI differs.

### Feature Flags and Engagement Levels

The guiding doc references user tiers (Public / Registered / Verified Alumni) which is a simple three-level gate. As more features ship, a richer engagement model becomes useful — features unlocking as alumni participate.

Don't build a feature flag system now. Do track the concept so that when the website admin area is built, there's a place to put it. The engagement level idea (profile complete → directory opt-in → attended event OR contributed story → mentor or chapter volunteer) is the right model. Implement it as a computed field in the Alumni Service when that is built.

### The Map

The Admin Portal has the map. The Website's alumni directory does not yet have a map view. The right destination is the website — integrated as a view toggle on the directory, not a separate page, with map results respecting active search filters.

When the website map is built: reuse the geocache approach and zoom-layer architecture from the portal (it works well). Add Leaflet.markercluster for city-level density. Remove the map from the Admin Portal (or keep it as a lightweight admin-only view of the same data).

### Domains

Target state:
- `nitkalumni.in` or `nitksaa.in` — website (public face)
- `directory.nitkalumni.in` — Admin Portal, phase 1 (alumni directory access)
- `events.nitkalumni.in` — Event App

All domains need to be in Firebase authorized domains and in CORS `allow_origins`. Set this up once when the domain is decided — don't change it more than once.

### Unified Audit Log

Today: two separate audit logs (portal's `audit_log` table in `alumni_db`; website has no unified audit log — module-level audit via `reviewed_by` fields).

Two steps:
1. Add `source_app VARCHAR(32)` column to `audit_log` in `alumni_db` (nullable, defaults to `'admin_portal'`). One-line migration that positions the audit log to receive events from all three apps.
2. Build `website_audit_log` in `website_db` for website-level admin actions (story publish/reject, role grants, member removal, flag reviews). Distinct from `alumni_db.audit_log` which covers alumni record changes.

Do step 1 before building the operational dashboard. Step 2 is part of the website enterprise foundation (Planning Section 21).

### NITIKA — AI Discovery Layer

NITIKA (NITK Intelligent Knowledge Assistant) is the planned AI assistant for the ecosystem. Not a general chatbot — a discovery and recommendation engine over verified alumni data. "Find me alumni working in quantum computing in Bangalore", "Who should I connect with for a fundraising round?"

The website will build a stub first (endpoint + UI entry point + context schema). The real AI layer is a separate service. See Planning doc Section 24.

---

## 8. Principles

**The alumni database is the foundation.** Every architecture decision is evaluated against: does this risk data quality, privacy, or security of 49K records? If yes, it waits.

**Connective tissue, not a destination.** The website and event app exist to make connections happen. Once a connection is made, the platform gets out of the way. Don't replicate LinkedIn, WhatsApp, or Zoom.

**One identity, everywhere.** Same Firebase UID across all three apps. An alumnus should never create a second account.

**Build for handover.** Keep the architecture comprehensible by a small volunteer team. Each "service" is a module in a shared repo until there is a concrete reason to separate it.

**Don't build services-layer concerns in the monolith.** Rate limiting, full-text search, email delivery, AI backend, and background jobs have a natural home in the services layer. Building them in the monolith means doing them twice.

**GCP ownership transfer is a governance decision, not a technical one.** The billing upgrade is urgent (before Jun 29). The project transfer happens when the association has the right people in place.

**The Sep 2026 / Feb 2027 event app timeline is the hard external constraint.** NITKonnect happens whether the app is ready or not — Feb 2027 is the deadline that doesn't move.
