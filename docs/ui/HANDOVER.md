# Events UI Alignment: Handover (9 Oct 2026)

For the next Claude Code cloud session, and for Padmanand and Sudarshana.
Background and analysis: `docs/ui/website-alignment.md` (on `ui/analysis`).

## 1. Where things stand

**Repos**
- Target: `sudarshanakarkala/nitksaa-event`. Claude pushes only to `ui/*` branches, never to `main`.
- Reference: `pwarrier108/nitksaa-website`. Read-only. Its design tokens are in `frontend/src/styles/tokens.css` and `global.css`; the shell is in `components/core/{AppLayout,Navbar,Footer}.jsx`.

**Baseline:** `main` @ `8e83a1e`. No new commits on `main` as of 9 Oct.

**Branches (all pushed)**

| Branch | Contains |
|---|---|
| `ui/analysis` | Mapping doc `docs/ui/website-alignment.md` |
| `ui/theme-tokens` | Bundled fonts (Crimson Pro, DM Sans); `lib/theme/*` rewritten: website palette, type scale, component themes, `AppPalette` extension (`context.palette`), dark default remembered in Hive |
| `ui/web-shell` | Tab title "NITKSAA Events", meta, favicon, app icons from the emblem, manifest |
| `ui/header-footer` | New `SiteHeader`, `SiteFooter`, `PageHeader`, `SitePage`, `site_links.dart`; logo assets (typo-fixed wordmark, emblem) |
| `ui/policies` | `assets/policies/*.md` (Privacy, Terms, Disclaimer copied unchanged from the website; interim generic Refund policy); `PolicyScreen`; built-in `SimpleMarkdown` (no package) |
| `ui/feedback` | `FeedbackScreen` (website form, same contact), stubbed `POST /api/v1/feedback`; **routes commit** adding `/privacy /terms /refund /disclaimer /feedback`, public in `route_guards.dart` |
| `ui/beta-preview` | All of the above + `ui/web-shell` + `beta` hosting target in `firebase.json`. **Deployed to beta 9 Oct; works.** |
| `ui/full-ui` | `ui/beta-preview` + section 3 done: shared app shell, header-only theme toggle, palette colours on every screen, badges/cards restyled, login card and splash, `tool/check_colors.sh`. **Not yet on beta.** |

The branches stack in this order: `theme-tokens` → `header-footer` → `policies` → `feedback` → `beta-preview` (+ `web-shell`) → `full-ui`.

**Beta:** https://nitksaa-events-beta.web.app. The app uses hash URLs, e.g. `/#/privacy`, `/#/feedback`.

## 2. Decisions (Padmanand)

- **Theme:** dark by default; light mode uses the website's cream palette.
- **Look and structure:** follow the website pattern, including one app shell with a header theme switch.
  - Remove the floating theme toggle in `main.dart`.
  - Replace hard-coded colours with theme colours on all screens.
- **Feedback form:** exactly like the website, same contact (`nitksaa.infra@gmail.com`). The UI is stubbed until the backend endpoint exists.
- **Refund policy:** generic interim text (refunds are event dependent). To be replaced by the association's official policy.
- **App icon:** use the website emblem.
- **NITiKa:** out of scope.
- **Sudarshana is not coding today.** UI work proceeds on branches and beta. We merge before he continues (see section 5).

## 3. Full UI scope (branch `ui/full-ui`, from `ui/beta-preview`) — done 9 Oct

What was done is summarised in **3a** below. The original brief follows unchanged.

Visual and structural changes only. **No changes to business logic, API calls, providers, repositories, payment services, auth flow, or nav item lists.**

1. **Shared app shell (website `AppLayout` pattern).**
   - Add a `ShellRoute` in `routes/app_router.dart` wrapping every attendee route except splash, login, foundation and developer.
   - The shell provides:
     - `SiteHeader`, with its theme toggle on
     - the menu: the existing `AppSidebar` at ≥ 900px wide, `AppBottomNav` below 900px, with the same items as today
     - `SiteFooter` at the end of the scrolling content
     - a content area
   - Remove each screen's own sidebar and bottom-nav wiring. Keep screen bodies unchanged.
   - `SitePage` then stops adding its own header and footer.
   - Keep `RouteGuards` behaviour identical.
2. **Theme switch.**
   - Delete the floating toggle in `main.dart` (the `builder:` Stack).
   - Header toggle only. Keep `ThemeNotifier` as is.
3. **Replace hard-coded colours** with `context.palette.*` or `Theme.of(context).colorScheme/textTheme`, one commit per file.
   - Map by meaning: background, card, text primary/secondary/muted, border, primary (gold), success, warning, error, info.
   - Remove local `isDark ? X : Y` colour pairs where the palette already covers them.
   - Counts before the work (`Color(0x…)` or `Colors.*`); see 3a for after:
     - `event_detail_screen.dart` 125
     - `event_list_screen.dart` 71
     - `manage_events_screen.dart` 70
     - `splash_screen.dart` 21
     - `event_registrations_screen.dart` 18
     - `app_sidebar.dart` 16
     - `my_events_screen.dart` 16
     - `checkout_screen.dart` 15
     - `main.dart` 6
     - `login_screen.dart` 4
     - `widgets/material/*` and `widgets/shared/*` (a few each)
   - Skip `developer_diagnostics_screen.dart`. It's a dev tool and Sudarshana's.
   - `Colors.transparent`, `Colors.white` on images or overlays, and the avatar gradient may stay.
   - The native-iOS Cupertino layout in `event_list_screen.dart`: replace its colours too; keep its structure.
4. **Restyle using theme components where the screen already has them** (cards → website card look, chips → website badges, status pills → success/warning/error tints).
   - Don't restructure layouts.
   - **Checkout: colours only.**
5. **Login and splash:** restyle to the website login card look: serif title, gold ring emblem, navy card. Visual only.
6. **Guardrail:** add `tool/check_colors.sh`, which fails if `Color(0x` appears outside `lib/theme/` (with an allowlist for the developer screen). Document it in this file.
7. Update the counts above and section 1 of this doc when done.

### 3a. Done on `ui/full-ui`

- **Shell:** `shared/widgets/app_shell.dart`, a `ShellRoute` in `app_router.dart` around home, my-events, manage-events, registrations, event detail, checkout, policies and feedback. Splash, login, foundation and developer stay outside. The footer appears when the page's own scroll reaches its end, or straight away if the page doesn't scroll. Screens keep their bodies; only their sidebar/bottom-nav wiring was removed (event registrations had its own inline `NavigationBar` with the same three items; it now uses `AppBottomNav`). `AppBottomNav` clamps its selected index because a non-admin on `/manage-events` now sees the nav.
- **Theme switch:** floating toggle removed from `main.dart`; header toggle only. `MaterialApp.title` is now "NITKSAA Events", so the web tab title no longer reverts to "NITKSAA Event".
- **Colours:** one commit per file. Mapping used: gold → `primary`; navy/white text → `textPrimary`; slate/grey text → `textSecondary`/`textMuted`; borders/dividers → `border`; card fills → `card`; green/red/orange/blue → `success`/`error`/`warning`/`info`. Old navy CTA buttons are now gold `primary` (website primary button). Status snackbars use the new `AppPalette.tinted(tone)`.
- **Restyle:** badges are tinted fill + 30% border in the same tone; cards are flat (no shadow) with the palette border; headings that asked for the unbundled `Fraunces` now use `CrimsonPro`. `AppPrimaryButton` labels use the button's foreground colour.
- **Login/splash:** login form sits in a navy card with the emblem in a gold ring (`shared/widgets/emblem_ring.dart`) and a serif "Sign in" title. Splash uses the same emblem and a serif "NITKSAA".
- **Checkout:** colour lines only (plus `const` removals the colour change forces).
- **Counts after** (`Color(0x…)` outside `lib/theme/`): **0**, except `developer_diagnostics_screen.dart` (39 `Color(0x…)`/`Colors.*`, allowlisted). Remaining `Colors.*` are allowed ones: `Colors.transparent`, the QR code's black on white in `event_detail_screen.dart`, the white logo tint in `site_header.dart` and `emblem_ring.dart`, and the avatar.
- **Guardrail:** `bash frontend/tool/check_colors.sh` (Git Bash on Windows). It exits 1 and lists the lines when `Color(0x` appears outside `lib/theme/`; the developer screen is allowlisted inside the script. Run it before every UI commit.
- **Checked here:** `flutter analyze` adds no new issues (the 6 errors in `razorpay_payment_io.dart` are pre-existing: mobile-only import, not compiled for web); `flutter build web --release` succeeds with Flutter 3.38.10; screenshots of list, login, splash, policy pages in dark and light at 1280px and 390px with a mocked API. Event detail, My Events, Manage and checkout were not seen signed in.

**Known bug, don't fix:** release build `Bad state: RenderBox was not laid out` on event list cards. It's Sudarshana's to fix. If a colour edit touches the offending widget, leave the layout alone.

**Build check:** the cloud environment may not be able to install Flutter (`storage.googleapis.com` is blocked by the proxy). If it can't:
- Review the code against the Flutter 3.38 API.
- Keep every edit small.
- Padmanand builds and deploys to beta, and pastes any errors back.

## 4. Deploy to beta (Padmanand, Windows)

One-time setup is already done: Developer Mode on, `npm i -g firebase-tools`, `firebase login`.

```powershell
cd C:\Users\padma\Projects\nitksaa-event
git fetch origin
git checkout <branch>        # e.g. ui/full-ui
git pull
cd frontend
flutter pub get
firebase use project-d22bed42-f302-4e23-8dc
flutter build web --release --dart-define=BACKEND_BASE_URL=https://nitksaa-events-api-246773894709.asia-south1.run.app
firebase deploy --only hosting:beta
git checkout -- pubspec.lock analysis_options.yaml   # discard local pub-get edits
```

**Check on beta**, desktop and phone width, dark and light:
- events list
- event detail
- My Events
- checkout (do a **₹1 test payment**)
- policy pages and feedback
- sign-in and sign-out
- a hard refresh on `/#/privacy`

## 5. Merge plan (avoid conflicts with Sudarshana)

The UI branches change most screen files, and Sudarshana's open issues (004, 005, 007–013, 016–023) touch the same files. The rule is **merge the UI work to `main` before he starts his next fix**, then he works on top of it.

1. Padmanand approves `ui/full-ui` on beta.
2. Open **one PR** `ui/full-ui` → `main`. It contains all the earlier `ui/*` branches. `ui/beta-preview`'s `firebase.json` beta target can be kept; it's harmless.
3. Sudarshana reviews the PR, mainly the routes commit, `pubspec.yaml`, the `web/` changes, and that checkout logic is unchanged. Then he merges it.
4. Sudarshana runs `git checkout main && git pull` **before** any new work. Any of his local uncommitted fixes: `git stash`, pull, `git stash pop`, then resolve.
5. **If he already has local commits on a screen file:** rebase onto the new `main`. Conflicts will be colour lines vs. his logic lines.
   - Keep his logic.
   - Re-apply the palette colour on the lines he touched.
6. Going forward: new code uses `context.palette` and theme colours, never `Color(0x…)`. `bash frontend/tool/check_colors.sh` catches mistakes.
7. **If the UI PR can't merge before he resumes**, he tells Padmanand which screen he's on, and that screen's colour commit is reverted from the PR and redone after his fix.

**WhatsApp to Sudarshana before he resumes:** "UI branch `ui/full-ui` restyles all screens (colours and shared shell only, no logic). Please review and merge it to main before your next fix, then pull main. Details: docs/ui/HANDOVER.md section 5."

## 6. Open items for others

**Sudarshana (backend)**
- `POST /api/v1/feedback` in `backend/app/` (not `backend/src/`, which is a copy of the website backend).
  - Body: `{area, category, message, source}`; Bearer auth.
  - Validation: message 10–2000 chars.
  - Emails `nitksaa.infra@gmail.com` like the website's `src/api/feedback.py`. Return 204, or 502 on mail failure.
  - Needs SMTP (go-live S10). Padmanand grants the secret to the events API service account (P6 lockdown).
- Policy links on checkout (S11). His file; after his payment issues close.

**Padmanand (website repo)**
- Load fonts: add a Google Fonts `<link>` for Crimson Pro and DM Sans in `frontend/index.html`. Today the live site falls back to Georgia and the system font.
- Define `--surface-ch` in `tokens.css`. It's used by `footer.css` but undefined.
- Replace `frontend/src/assets/nitksaa-logo.png` with the typo-fixed logo ("Assocation" → "Association"). The fixed file is in the events repo at `frontend/assets/images/nitksaa-logo.png`.
- Official refund policy text, to replace `frontend/assets/policies/Refund_and_Cancellation_Policy.md`.
