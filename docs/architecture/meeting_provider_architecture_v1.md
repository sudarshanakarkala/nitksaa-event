# Meeting Provider Integration — Architecture v1

**Date:** 2026-06-22
**Status:** ARCHITECTURE DOCUMENT — OAuth integration must not be implemented in Week 4 or Alpha
**Depends on:** migrations 001–009 (existing), events table
**Related decisions:** `week4_feedback_architecture_decisions.md` Decision 3

---

## Problem Statement

Virtual events require a join link so attendees can attend online. Currently the `events` table
has a `virtual_link` column (free-text URL). An organizer manually pastes a Zoom or Meet URL
at event creation time.

This works for the Alpha. It does not scale when:

1. **Links must be generated automatically** — For large events, generating a Zoom meeting
   manually and pasting the URL is error-prone. The system should be able to create the meeting
   programmatically via the provider's API.

2. **Links must be protected** — A Zoom link in a public event detail response is accessible to
   anyone. Protected links (available only to registered attendees after registration) require
   the system to know *which* provider issued the link and how to validate access.

3. **Multiple providers are in use** — Different events may use Zoom (formal conferences),
   Google Meet (informal meetups), or Microsoft Teams (corporate-organized sessions). The schema
   must support all three without hard-coding a provider assumption.

This document defines the schema for meeting provider integration and the future OAuth flow.

---

## Current Schema State

```sql
CREATE TABLE events (
    event_id       SERIAL   PRIMARY KEY,
    ...
    virtual_link   TEXT,    -- free-text URL; NULL for in-person events
    ...
);
```

The `virtual_link` is a plain URL. No provider tracking, no token storage, no creation API.

---

## Proposed Schema Changes

These columns are added in a future migration. No migration is created in Week 4.

```sql
ALTER TABLE events
  ADD COLUMN meeting_provider       VARCHAR(20)
             CHECK (meeting_provider IN ('ZOOM', 'GOOGLE_MEET', 'TEAMS', 'CUSTOM')),
             -- NULL for in-person events; 'CUSTOM' for manually pasted URLs
  ADD COLUMN meeting_id             TEXT,
             -- Provider-issued meeting ID (e.g., Zoom meeting_id, Meet meeting code)
             -- NULL for CUSTOM links and in-person events
  ADD COLUMN meeting_passcode       TEXT,
             -- Zoom passcode or equivalent; stored encrypted at rest
             -- NULL for providers that do not require a passcode
  ADD COLUMN meeting_host_url       TEXT,
             -- Host join URL (admin-only, never returned in public API)
             -- NULL for CUSTOM links
  ADD COLUMN meeting_created_via    VARCHAR(20)
             CHECK (meeting_created_via IN ('MANUAL', 'API'));
             -- MANUAL: admin pasted the URL; API: created via provider OAuth
             -- NULL for in-person events
```

The existing `virtual_link` column is retained. For CUSTOM links, `virtual_link` remains the
join URL and no other meeting columns are populated. For provider-created meetings, `virtual_link`
is populated from the provider API response so all existing consumers continue to work.

---

## Provider Support Matrix

| Provider | Meeting creation API | OAuth scope | Passcode support | Host URL |
|---|---|---|---|---|
| Zoom | `POST /v2/users/me/meetings` | `meeting:write` | Yes | Yes |
| Google Meet | Google Calendar API (creates event with Meet link) | `https://www.googleapis.com/auth/calendar` | No | Via Calendar |
| Microsoft Teams | Microsoft Graph `onlineMeetings` | `OnlineMeetings.ReadWrite` | No | Yes |
| Custom | N/A — admin pastes URL manually | N/A | Optional (manual entry) | N/A |

---

## Future `org_meeting_credentials` Table

Stores OAuth credentials for the NITKSAA organization's meeting provider accounts. One row per
provider. Admin-managed. Created when OAuth integration is approved.

```sql
CREATE TABLE org_meeting_credentials (
    credential_id    SERIAL        PRIMARY KEY,
    provider         VARCHAR(20)   NOT NULL UNIQUE
                     CHECK (provider IN ('ZOOM', 'GOOGLE_MEET', 'TEAMS')),
    access_token     TEXT          NOT NULL,  -- encrypted at rest
    refresh_token    TEXT,                    -- encrypted at rest; NULL if provider uses long-lived tokens
    token_expires_at TIMESTAMPTZ,
    scopes           TEXT,                    -- space-separated OAuth scopes granted
    account_email    TEXT,                    -- the organizer account that granted access
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ
);
```

This table stores the org-level OAuth tokens. It is not per-event and not per-user. NITKSAA
authorizes one Zoom account (or one Meet account), and all events use that account to create
meetings.

**Security rule:** `access_token` and `refresh_token` must be encrypted at rest using a key
stored outside the database (e.g., KMS or an env var). They must never appear in API responses
or logs.

---

## Meeting Creation Flow (when implemented)

```
Admin creates event with virtual=true, provider=ZOOM
    │
    ▼
POST /api/v1/admin/events/{id}/meeting/create
    │
    ├── Load org credentials for ZOOM from org_meeting_credentials
    ├── Refresh access_token if expired (using refresh_token)
    ├── Call Zoom API: POST /v2/users/me/meetings
    │     { topic: event_title, start_time: start_datetime, duration: minutes,
    │       settings: { join_before_host: false, waiting_room: true } }
    │
    ├── On success:
    │   UPDATE events SET
    │     virtual_link = response.join_url,
    │     meeting_provider = 'ZOOM',
    │     meeting_id = response.id,
    │     meeting_passcode = response.password,
    │     meeting_host_url = response.start_url,
    │     meeting_created_via = 'API'
    │
    └── Return { join_url, meeting_id, passcode } to admin
```

The `meeting_host_url` (Zoom `start_url`) is stored but never returned in the public API.
It is available to the admin portal only, so the event host can start the meeting.

---

## Protected Join Link Pattern (future)

For events where the join link must not be publicly visible:

1. `virtual_link` is not returned in the public event detail API (`GET /api/v1/events/public/{id}`)
2. A separate endpoint returns the join link only to confirmed registered attendees:

```
GET /api/v1/events/{id}/my-registration/join-link
    Authorization: Bearer <backend JWT>
    →  { "join_url": "https://zoom.us/j/...", "passcode": "abc123" }
    →  404 if not registered or registration cancelled
```

This pattern is not needed for Alpha — all Alpha events use manually pasted public links.

---

## OAuth Setup Flow (admin-level, future)

```
Admin navigates to Admin Portal → Settings → Meeting Providers
    │
    ▼
Clicks "Connect Zoom Account"
    │
    ▼
Backend generates OAuth authorization URL with state parameter
Admin redirected to Zoom OAuth consent page
    │
    ▼
Zoom redirects to /api/v1/admin/oauth/zoom/callback?code=...&state=...
    │
    ▼
Backend exchanges code for access_token + refresh_token
INSERT INTO org_meeting_credentials (provider='ZOOM', access_token=..., refresh_token=...)
    │
    ▼
Admin sees "Zoom Connected" status in Settings
```

The OAuth callback endpoint requires admin authentication. The `state` parameter prevents CSRF.

**Must not be implemented in Week 4.** OAuth setup requires:
1. A registered OAuth app with the provider (Zoom Marketplace, Google Cloud Console, Azure AD)
2. A production callback URL (https — not localhost)
3. Credentials review and approval (Zoom: app review; Google: verification for sensitive scopes)
4. Encrypted credential storage infrastructure

None of these are available in the Alpha environment.

---

## Alpha Decision

**All Alpha and Jun 30 beta virtual events use `meeting_provider = 'CUSTOM'` and `meeting_created_via = 'MANUAL'`.**

The organizer pastes the join URL into the event creation form. `virtual_link` is stored as-is.
No provider API calls. No OAuth tokens. No credential table.

The schema additions are deferred until the first event requiring automated meeting creation.

---

## Implementation Recommendation

**Do not implement OAuth or provider API calls in Week 4 or Alpha.**

Implement in this order when approved:
1. Schema migration: add `meeting_provider`, `meeting_id`, `meeting_passcode`, `meeting_host_url`, `meeting_created_via` to `events`
2. Schema migration: create `org_meeting_credentials` table with encrypted token columns
3. Admin portal: Settings → Meeting Providers page with OAuth connect flow
4. Backend: OAuth callback endpoint, token refresh logic
5. Backend: meeting creation endpoint (`POST /admin/events/{id}/meeting/create`)
6. Optional: protected join link endpoint for registered attendees only

Step 1 is low-risk and can be applied independently (all new nullable columns). Steps 2–6
require production OAuth app credentials and must not be attempted in the Alpha environment.
