# Events UI Alignment: Closed (10 Oct 2026)

Final record of the work to make the events attendee app look and behave like the NITKSAA website. It merges the original plan (`EVENTS_UI_ALIGNMENT_HANDOFF`, 8 Oct) with what was delivered.
- Merged to `main` in **PR #2** (`ui/full-ui`, merge commit `78e09ce`) on 10 Oct 2026, and deployed to beta and the live site.
- Analysis and mapping: `docs/ui/website-alignment.md` (branch `ui/analysis`).

**Only open item:** a full admin-flow pass. Sudarshana does it while working through his fixes; see section 4.

## 1. Plan vs. done

| Step (original plan) | Status | Notes |
|---|---|---|
| 0. Setup: repo access, beta target | Done | Claude GitHub App on both repos; `beta` hosting target in `frontend/firebase.json` |
| 1. Agree routes, `pubspec.yaml`, ISSUE-022 split with Sudarshana | Done | Routes and packages reviewed in PR #2; visual half of ISSUE-022 done |
| 2. Analysis and mapping doc | Done | `docs/ui/website-alignment.md` |
| 3. Theme | Done | Website palette, Crimson Pro and DM Sans bundled, component themes, `AppPalette` (`context.palette`); dark by default, cream light theme, choice remembered |
| 4. Web shell | Done | Tab title, meta, favicon, app icons, manifest; Razorpay script and caching untouched |
| 5. Header and footer | Done, extended | One `AppShell` (`ShellRoute`) round every attendee page: sticky header (logo, Events nav, theme toggle, account menu, drawer below 900px), sticky footer, right-rail slot for NITiKa. Old sidebar, bottom bar and floating theme toggle removed |
| 6. Policy pages | Done | Refund (interim generic text) and Disclaimer in-app; Terms and Privacy link to the website's pages. Policy links on checkout (go-live S11) still Sudarshana's |
| 7. Feedback form | UI done | Website form, same contact. `POST /api/v1/feedback` is stubbed; the backend endpoint is Sudarshana's (section 5) |
| 8. Screen-level polish | Done (colours), next round (redesign) | Hard-coded colours replaced on every screen, one commit per file; Events page rebuilt on the website list pattern. Card redesign is a follow-up |
| 9. Admin app (React) restyle | Not started | Optional; moved to Padmanand's TODO (admin dashboard and audit) |

## 2. Decisions (Padmanand)

- **Theme:** dark by default; light uses the website's cream palette. One switch, in the header.
- **Web only.** No native iOS or Android app. Web always uses the Material layout, including Safari on iPhone. The Cupertino code stays unused until Sudarshana decides whether to delete it.
- **Navigation, website Stories pattern:**
  - The header nav is just **Events**.
  - My Events is a filter ("Registered by me") and an account-menu item.
  - Manage Events and Create Event are admin buttons.
  - Upcoming/Past is a filter.
  - Volunteer and More were removed.
- **Filters:** a collapsible left rail at 900px and wider; a bottom sheet below that.
- **Unregister** stays on event cards so ISSUE-004/005 gets fixed (it currently uses the wrong cancel endpoint).
- **Logos:** the NITKSAA Events set (gold on dark, navy on light, favicon, app icons). The fixed website logo ("Association" typo) is in `frontend/assets/images/nitksaa-logo.png`.
- **Website link:** the footer points to production, `https://www.nitkalumni.in`.

## 3. Verification

- `flutter test`: **110/110 pass** on `main`, including the ISSUE-001/002/003/006 regression tests. Commit `f4fa237` fixed the one failure the UI work introduced: the theme provider opened Hive inside `build()`.
- `flutter build web --release` succeeds; `bash frontend/tool/check_colors.sh` passes.
- **Beta smoke test** (Padmanand, 9 Oct): signed out and as a regular user, at desktop, Surface Pro, iPad and phone widths.
- **Manual re-check of ISSUE-001/002/003/006 on beta** (Sudarshana, 10 Oct).
- **₹1 test checkout** passed (10 Oct), including the Razorpay popup and return inside the shell.
- **Admin:** sign-in, Create Event and Publish work. Publish needs capacity; see section 5.

## 4. Remaining: full admin pass (Sudarshana, with his fixes)

1. Manage Events (Draft and Published tabs), Create Event, Edit, Publish/Unpublish, Delete.
2. Registrations page and attendee export.
3. The phone "⋯" admin menu.
4. Unregister on a free and on a paid event, once his ISSUE-004/005 fix lands.
5. Event detail Register and the QR badge, signed in.
6. Check whether the release-build `RenderBox was not laid out` card error still reproduces with the new row layout.
7. Confirm whether a registration whose event isn't public (cancelled or unpublished) can exist. If not, remove the `/my-events` fallback.

## 5. Known issues and follow-ups

**Sudarshana:**
- **ISSUE-004/005:** Unregister calls `DELETE /api/v1/events/{id}/my-registration`; the correct call is `POST /api/v1/registrations/{id}/cancel`, which also starts the refund.
- **`POST /api/v1/feedback`** in `backend/app/` (not `backend/src/`):
  - Body `{area, category, message, source}`, Bearer auth.
  - Validation: message 10–2000 characters.
  - Emails `nitksaa.infra@gmail.com` like the website's `src/api/feedback.py`; returns 204, or 502 on mail failure.
  - Needs SMTP (go-live S10).
- Policy links on checkout (go-live S11).
- Decide whether to delete the Cupertino code.
- **Railway:** the `splendid-elegance` project auto-deploys on every push to `main` and failed on `78e09ce`. Disconnect it if `api-events-test.itelematics.com` is no longer used.

**Padmanand (admin dashboard and audit):**
- Create Event form: make **Capacity** required. Publish refuses events without it (`422 missing_fields_for_publish: capacity`).
- Show the backend's error message instead of the raw DioException.
- `/manage-events?new=1` reopens the Create form on a refresh; drop `?new=1` once the form opens.
- Manage Events lists only events that haven't started yet, so a draft with a past start time is invisible.

**Next UI round:**
- Event card redesign (banner band, date tile, badges, capacity bar for admins).
- The same list frame and card on My Events and Manage Events.
- NITiKa in the right-rail slot (design: project doc `NITIKA_SERVICE_DESIGN.md`).

**Website repo (Padmanand):**
- Load Crimson Pro and DM Sans with a Google Fonts `<link>`.
- Define `--surface-ch` in `tokens.css`.
- Replace the logo with the typo-fixed version.
- Provide the official refund policy text.

## 6. Operational notes

**Admin access:** two places, both needed.
- **App:** `event_users.user_type = 'admin'` in `event_db`. Alumni accounts reset to `alumni` on every login, so admin accounts must be non-alumni.
- **Backend:** the account's Firebase UID in the `PLATFORM_ADMIN_FIREBASE_UIDS` env var on Cloud Run `nitksaa-events-api`. Updating it replaces the whole list.
- Current admins: `pwarrier108@hotmail.com` (email/password) and `sudarshana.karkala@gmail.com` (Google).
- An email/password account created in the Firebase console must be marked verified, because the backend rejects unverified emails.

**Deploys:**
- A **Cloud Build trigger redeploys the backend on every push to `main`**, so backend changes go live on merge.
- The frontend is deployed by hand:
  - beta: `firebase deploy --only hosting:beta --project project-d22bed42-f302-4e23-8dc`;
  - live, from `main` only: `hosting:events`.

**Colour guardrail:** new code uses `context.palette` and theme colours, never `Color(0x…)`. Run `bash frontend/tool/check_colors.sh` before committing.
