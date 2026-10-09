# Events UI Alignment: Handover (updated 9 Oct 2026, end of day)

For the next Claude Code cloud session, and for Padmanand and Sudarshana.
Background and analysis: `docs/ui/website-alignment.md` (on `ui/analysis`).

## 1. Where things stand

**Repos**
- Target: `sudarshanakarkala/nitksaa-event`. Claude pushes only to `ui/*` branches, never to `main`.
- Reference: `pwarrier108/nitksaa-website`. Read-only.
  - Design tokens: `frontend/src/styles/tokens.css` and `global.css`.
  - Shell: `components/core/{AppLayout,Navbar,Footer,FilterSidebar}.jsx`.
  - List-page pattern: `pages/StoriesPage.jsx`.

**Baseline:** `main` @ `34c9f16`. The only commit since `8e83a1e` is docs-only and doesn't overlap the UI work.

**Branches (all pushed)**

| Branch | Contains |
|---|---|
| `ui/analysis` | Mapping doc `docs/ui/website-alignment.md` |
| `ui/theme-tokens` | Bundled fonts (Crimson Pro, DM Sans); `lib/theme/*`: website palette, type scale, component themes, `AppPalette` (`context.palette`), dark default remembered in Hive |
| `ui/web-shell` | Tab title, meta, favicon, app icons, manifest |
| `ui/header-footer` | `SiteHeader`, `SiteFooter`, `PageHeader`, `SitePage`, `site_links.dart`; logo assets |
| `ui/policies` | `assets/policies/*.md`, `PolicyScreen`, built-in `SimpleMarkdown` |
| `ui/feedback` | `FeedbackScreen`, stubbed `POST /api/v1/feedback`; **routes commit** for `/privacy /terms /refund /disclaimer /feedback` |
| `ui/beta-preview` | All of the above + `beta` hosting target in `firebase.json` |
| **`ui/full-ui`** | `ui/beta-preview` + everything in section 3. **This is the branch to merge.** Last deployed to beta and smoke-tested 9 Oct, signed out and as a regular user. Head: see `git log -1 origin/ui/full-ui`. |

The branches stack in this order: `theme-tokens` → `header-footer` → `policies` → `feedback` → `beta-preview` (+ `web-shell`) → `full-ui`.

**Beta:** https://nitksaa-events-beta.web.app. The app uses hash URLs, e.g. `/#/privacy`. After each deploy, open beta in a private window: the Flutter service worker caches hard.

## 2. Decisions (Padmanand)

- **Theme:** dark by default; light uses the website's cream palette. One switch, in the header.
- **Look and structure:** follow the website, but diverge where events need it or where the website has no mobile design.
- **Web only.** No native iOS or Android app, to avoid store certification overhead. Web always uses the main (Material) layout, including Safari on iPhone. The Cupertino code stays unused until Sudarshana decides whether to delete it.
- **Navigation, website Stories pattern:**
  - The header nav is just **Events**.
  - "My Events" is a **filter** ("Registered by me"), also reachable from the account menu.
  - "Manage Events" and "Create Event" are **admin buttons** on the Events page.
  - Upcoming/Past is a **filter**.
  - Volunteer and More are removed: they were placeholders with no page.
- **Rails:**
  - Filters sit in a collapsible left rail at 900px and wider.
  - Below 900px, a funnel icon opens a bottom sheet.
  - A right-rail slot is ready for **NITiKa, which comes in the next pass** (no longer out of scope).
- **Policies:**
  - Terms and Privacy pages are one-line links to `https://www.nitkalumni.in/site/tos.dz` and `/site/privacy.dz`.
  - Refund keeps the generic interim text until the official policy exists.
  - Disclaimer is unchanged.
- **Website link:** the footer points to production, `https://www.nitkalumni.in`.
- **Feedback form:** like the website, same contact (`nitksaa.infra@gmail.com`). The UI is stubbed until the backend endpoint exists.
- **Logos:** the NITKSAA Events logo set (gold on dark, navy on light; favicon; app icons).

## 3. What was done on `ui/full-ui`

The rules were: visual and structural changes only, checkout colours only, and no changes to providers, repositories, payment or the auth flow. Nav changes were made only where Padmanand asked.

### Shell and theme
- **One app shell** (`shared/widgets/app_shell.dart`, a `ShellRoute` in `app_router.dart`) around every attendee page. Splash, login, foundation and developer stay outside it. `RouteGuards` is unchanged.
  - **Sticky header and footer;** only the page scrolls between them.
  - **Header:** NITKSAA Events logo, website-style pill nav (active page gold), theme toggle, account menu (My Events, Sign out). Below 900px, a menu button opens a side drawer.
  - **Footer:** one 52px row. Below 1100px it scrolls sideways, with a fade at the right edge; touch and mouse dragging both work.
  - **Tab title per page,** e.g. "NITKSAA Events · My Events".
  - **Right-rail slot for NITiKa:** a 320px rail from 1200px; below that, a floating chat button opening a side panel or full-height sheet. Empty for now.
  - The old sidebar and bottom bar are deleted.
- **Theme toggle:** the floating toggle is removed from `main.dart`.
- **Colours:** palette colours on every screen, one commit per file. Snackbars use `AppPalette.tinted`.
- **Fonts:** headings use Crimson Pro 600, like the website's h1–h4; text uses DM Sans. The Cupertino text theme uses the same fonts.
- **Login and splash:**
  - Login: a navy card with the emblem in a gold ring and a serif title.
  - Splash: the same emblem.
  - On web, login always uses the Material layout.

### Event list (website Stories / Directory pattern)
- **`ListPage` frame** (`shared/widgets/list_page.dart`):
  - Toolbar: eyebrow, serif title, subtitle, search.
  - **Cards / Table** toggle from 600px; phones get cards only.
  - Count row with actions.
- **Filter rail** like the website's `FilterSidebar`:
  - Header: "Filters" with an active-count badge, a plain "Clear all" link and a collapse chevron.
  - Muted gold section labels and chip toggles.
  - Result count at the bottom.
  - Sections:
    - **When** (Upcoming / Past);
    - **My Registrations** ("Registered by me", signed in only);
    - **Date range** and **Timeline**;
    - **Event mode** and **Registration status**.
  - It starts open from 900px.
  - Below 900px, a funnel icon (with count badge) and a clear-filters icon open and reset the same panel as a bottom sheet.
- **Cards:**
  - Sized to their content in equal-height rows, up to 4 columns of about 320px.
  - Website badges.
  - **Your registered events** get the gold "own" tint, a "Registered" badge and an **Unregister** button while `canCancel` allows it. It's the same dialog and `cancelRegistration` call as the My Events page.
- **Table:** sortable by title, date, mode and registration; clicking a row opens the event.
- **Admins:** "Manage Events" and "Create Event" buttons ("⋯" menu on phones). Create Event opens `/manage-events?new=1`, which opens the existing form.
- **`/my-events` still works** as a fallback; the account menu now opens `/home?mine=1`.

### Other
- **Policies:** Terms and Privacy pages became website links.
- **Logos:** the NITKSAA Events logo set (header logo, gold/navy emblem, favicon, app icons). `nitksaa-logo.png` is kept for the website item in section 6.
- **Guardrail:** `bash frontend/tool/check_colors.sh` (Git Bash on Windows) fails if `Color(0x…)` appears outside `lib/theme/`. The developer screen is allowlisted. Run it before every UI commit.

### Checks
- **Analyzer:** `flutter analyze` shows 75 issues, all pre-existing. The 6 errors are in `razorpay_payment_io.dart`, a mobile-only import that isn't compiled for web.
- **Build:** `flutter build web --release` succeeds on Flutter 3.38.10.
- **Smoke test on beta (Padmanand, 9 Oct):** passed, signed out and as a regular user, at desktop, Surface Pro, iPad and phone widths. Details in section 4.

## 4. Pending

### Blocked on Sudarshana (do together)
1. **Signed-in deep test:**
   - event detail (banners, Register, QR badge);
   - "Registered by me", own-card tint and **Unregister**;
   - account menu → My Events;
   - checkout with a **₹1 test payment**.
2. **Admin flows:**
   - Manage Events and Create Event (the form should open straight away);
   - Registrations page;
   - the phone "⋯" menu.
3. **Event card bug:** the known `RenderBox was not laid out` error on event cards in release builds. It's his to fix; check whether the new row layout changed it.
4. **Cupertino code:** decide whether to delete the iOS layouts now that web never uses them.
5. **"Registered by me" data:** it combines the public list with your registrations, so a registration whose event isn't in the public list (cancelled or unpublished) won't show. Confirm whether that can happen. `/my-events` is kept until then.

### Next UI round (after Sudarshana's review and fixes)
1. **Event card redesign:**
   - banner or gradient band with a date tile;
   - badges: mode, price, registration;
   - capacity bar for admins.
2. **The same `ListPage` frame and card on My Events and Manage Events.**
3. **NITiKa** in the right-rail slot.
4. Remove the `/my-events` fallback once item 5 above is confirmed.

### Smoke-test items already passed (re-run after the merge)
- **Header and nav:** pills, menu drawer below 900px, theme toggle that survives a refresh, account menu.
- **Event list:**
  - search;
  - When chips;
  - rail filters, badge count and Clear all;
  - collapsing and reopening the rail;
  - phone funnel and clear icons;
  - Cards/Table toggle;
  - card rows at all widths.
- **Shell:**
  - sticky header and footer;
  - footer fade and drag-scroll;
  - tab titles;
  - fonts;
  - logos and favicon in both themes;
  - login card.
- **Pages:** policy pages and their links, Feedback page, footer links to the production website. **About Us** points to `https://www.nitkalumni.in/about`; check that the page exists.

## 5. Deploy to beta (Padmanand, Windows)

One-time setup is done: Developer Mode on, `npm i -g firebase-tools`, `firebase login`, and a local `.firebaserc` beta target (keep it uncommitted).

```powershell
cd C:\Users\padma\Projects\nitksaa-event
git fetch origin
git checkout ui/full-ui
git pull
cd frontend
flutter pub get
firebase use project-d22bed42-f302-4e23-8dc
flutter build web --release --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
firebase deploy --only hosting:beta
git checkout -- pubspec.lock analysis_options.yaml linux macos windows   # discard local pub-get edits
```

If beta still shows the old app, open it in a private window (Ctrl+Shift+N). To check that a build contains the latest code, search `build\web\main.dart.js` for a recent string, e.g.:

```powershell
Select-String -Path build\web\main.dart.js -Pattern "Registered by me" -Quiet
```

## 6. Merge plan (avoid conflicts with Sudarshana)

`ui/full-ui` changes most screen files, and Sudarshana's open issues touch the same files. **Merge the UI work to `main` before he starts his next fix.**

1. Deep test with Sudarshana on beta (section 4).
2. Open **one PR** `ui/full-ui` → `main`. It contains all the earlier `ui/*` branches. The `beta` target in `firebase.json` is harmless and can stay.
3. Sudarshana reviews the PR, mainly:
   - the routes and shell (`app_router.dart`, `app_shell.dart`);
   - the nav changes (section 2);
   - `pubspec.yaml` and `web/`;
   - that checkout logic is unchanged (its commit is colours only);
   - the event list changes, which move UI but keep provider calls.

   Then he merges.
4. Sudarshana runs `git checkout main && git pull` **before** any new work. Local uncommitted fixes: `git stash`, pull, `git stash pop`, then resolve.
5. **If he already has local commits on a screen file:** rebase onto the new `main`. Keep his logic lines and re-apply the palette colours on the lines he touched.
6. **Going forward:** new code uses `context.palette` and theme colours, never `Color(0x…)`. `tool/check_colors.sh` catches mistakes.
7. **If the PR can't merge before he resumes,** he tells Padmanand which screen he's on. That screen's commits are reverted from the PR and redone after his fix.

**WhatsApp to Sudarshana:** "UI branch `ui/full-ui` restyles the app to match the website: shared header/footer shell, filters and admin buttons on the Events page, colours and fonts. No provider or payment logic changes. Let's deep-test it together on beta (admin flows and ₹1 checkout), then please review and merge it to main before your next fix. Details: docs/ui/HANDOVER.md."

## 7. Open items for others

**Sudarshana (backend)**
- `POST /api/v1/feedback` in `backend/app/` (not `backend/src/`, which is a copy of the website backend):
  - Body `{area, category, message, source}`, with Bearer auth.
  - Validation: message 10–2000 characters.
  - Emails `nitksaa.infra@gmail.com` like the website's `src/api/feedback.py`. Returns 204, or 502 on mail failure.
  - Needs SMTP (go-live S10).
- Policy links on checkout (S11), after his payment issues close.

**Padmanand (website repo)**
- Load Crimson Pro and DM Sans with a Google Fonts `<link>` in `frontend/index.html`.
- Define `--surface-ch` in `tokens.css`; `footer.css` uses it but it's undefined.
- Replace `frontend/src/assets/nitksaa-logo.png`, which has the "Assocation" typo, with the fixed `frontend/assets/images/nitksaa-logo.png` from the events repo.
- Provide the official refund policy text, to replace `frontend/assets/policies/Refund_and_Cancellation_Policy.md`.
