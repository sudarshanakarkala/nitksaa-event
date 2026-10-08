# Events UI ↔ Website Alignment — Analysis and Mapping (Step 2)

**Status:** Draft for Padmanand's review. No code changed.
**Sources analysed:**
- Website `pwarrier108/nitksaa-website` @ `24d9905` (read-only)
- Events `sudarshanakarkala/nitksaa-event` @ `8e83a1e` (latest `main`, 8 Oct 2026)

**Sudarshana's status at this commit** (`git log` + `docs/issues/`): ISSUE-001, 002, 003 and 006 have commits and test reports. Everything else is open. No new commits since the handoff was written.

---

## 0. Read this first: three findings that change the plan

1. **The theme alone will not restyle the event screens.**
   - The main screens hard-code their colours instead of reading the theme: about **490** `Color(0x…)` / `Colors.*` uses across `features/`.
     - `event_detail_screen.dart`: 125
     - `event_list_screen.dart`: 71
     - `manage_events_screen.dart`: 70
     - `my_events_screen.dart`: 16
     - `checkout_screen.dart`: 15
   - They also **don't use** `core/widgets/` at all. Only `login_screen.dart` uses the older `widgets/material/` set.
   - Step 3 (theme) will change scaffold backgrounds, app bars, Material buttons, inputs, dialogs, snackbars and chips that aren't overridden. Cards, text colours and accents inside the screens stay as they are until Step 8.
   - **The gap is smaller than it sounds.** The screens already use a navy and gold palette close to the website: navy `#0D1B3E` vs `#0f2744`, gold `#C9952A` vs `#c9a84c`. After Step 3 the app will look related to the website, not identical.
2. **There is no shared app shell.** Each screen builds its own scaffold with `AppSidebar` (width ≥ 900) or `AppBottomNav`. The four screens that do this are list, my events, manage and registrations.
   - Putting a website header and footer on every page therefore needs one of two things:
     - **(a)** a `ShellRoute` in `routes/app_router.dart`. This clashes with ISSUE-021.
     - **(b)** edits to every screen. This is in the Wait list.
   - **Recommendation:** ask Sudarshana to add the `ShellRoute` as part of the agreed routes commit, or to do it with ISSUE-021. Until then, header and footer can only be built and shown on the new pages (policies, feedback).
3. **The website has no Refund policy.**
   - Its policy files are Privacy & Cookies, Terms of Use and Website Disclaimer, plus About Us.
   - None of them mention payments, Razorpay, cancellation or refunds.
   - Razorpay live mode and go-live item S11 need a refund/cancellation policy.
   - Someone has to **write** it. There is nothing to copy. → Padmanand / association.

Two website-side bugs worth fixing in the website itself (Padmanand). Events should copy the *intended* values, not the bugs:
- **Fonts are never loaded.** `tokens.css` names `'Crimson Pro'` and `'DM Sans'`, but nothing loads them: no Google Fonts link, no `@font-face`, no package. The live site renders in **Georgia** and the **system sans** fallback.
  - Fix: one `<link>` in `frontend/index.html`.
- **`--surface-ch` is used but never defined.** It appears in `footer.css` and the detail-panel close button. Those `rgba(var(--surface-ch), …)` colours are invalid, so the footer text and border fall back to inherited or none.

---

## 1. Design tokens from the website

Source: `frontend/src/styles/tokens.css` and `global.css`. **Dark is the default theme** (`useTheme.js`, stored in localStorage key `nitksaa-theme`). Light is applied with `[data-theme="light"]`.

### 1.1 Colours

| Role | Token | Dark (default) | Light |
|---|---|---|---|
| Page background (body) | `--navy-deep` | `#09192e` | `#f5f0e6` |
| Canvas (sticky headers, detail pages) | `--bg-canvas` | `#070f1c` | `#e8e2d4` |
| Brand navy (fixed) | `--navy` | `#0f2744` | `#0f2744` |
| Raised panel / modal | `--navy-mid` | `#162f52` | `#ede8d8` |
| Navy light / muted | `--navy-light` / `--navy-muted` | `#1e3f6e` / `#2a5298` | `#ddd5c3` / `#4a6090` |
| Nav and footer bar | `--bg-nav` | `rgba(9,25,46,0.92)` + 12px blur | `rgba(245,240,230,0.95)` |
| **Primary (gold)** | `--gold` | `#c9a84c` | `#8a6010` |
| Gold hover | `--gold-light` | `#e2c97e` | `#a07520` |
| Gold dim (chips in light) | `--gold-dim` | `#8a6e2f` | `#8a6e2f` |
| Gold pale | `--gold-pale` | `#f5ecd4` | — |
| On-primary (text on gold button) | `--navy-deep` | `#09192e` | `#f5f0e6`¹ |
| Text primary | `--text-primary` | `#f0e6c8` (warm cream) | `#1c2b3a` |
| Text secondary | `--text-secondary` | `#9db4d0` | `#4a6278` |
| Text muted | `--text-muted` | `#5a7a9a` | `#7a8898` |
| Surface (cards, inputs) | `--surface` | `rgba(255,255,255,0.04)` | `rgba(0,0,0,0.04)` |
| Surface hover | `--surface-hover` | `rgba(255,255,255,0.07)` | `rgba(0,0,0,0.07)` |
| Card (alumni/entity) | `--bg-card-alumni` | `rgba(15,39,68,0.55)` | `rgba(255,255,255,0.65)` |
| Border | `--border` | `rgba(201,168,76,0.18)` (gold tint) | `rgba(160,120,40,0.22)` |
| Border hover / focus | `--border-hover` | `rgba(201,168,76,0.45)` | `rgba(160,120,40,0.50)` |
| Modal overlay | `--bg-overlay` | `rgba(5,14,28,0.88)` | `rgba(10,20,40,0.55)` |
| Success | badge / status | `#6ee7b7` / `#4ade80` | `#166534` / `#15803d` |
| Warning / pending | badge | `#fcd34d` | `#92400e` |
| Error / danger | badge, `.error-msg`, `.btn-danger` | `#f87171` | `#991b1b` |
| Info | notice | `#93c5fd` | `#1e3a8a` |

¹ In light mode `--navy-deep` becomes cream, so the gold button text turns cream on dark gold. That is intended on the website.

Status fills use the colour at **8% alpha**, with a border at **30%** (badges) or **25%** (notices).

### 1.2 Typography

| Use | Font | Size | Weight | Other |
|---|---|---|---|---|
| Headings h1–h4 (global) | **Crimson Pro** (serif), fallback Georgia | — | 600 | line-height 1.2 |
| Page heading (`.dash-heading`) | Crimson Pro | 2.2rem = **35px** | 600 | — |
| Login title | Crimson Pro | 1.75rem = 28px | 600 | — |
| Detail / modal title | Crimson Pro | 1.25–1.35rem = 20–22px | 600 | — |
| Brand name in nav | Crimson Pro | 16px | 600 | letter-spacing 0.02em |
| Body | **DM Sans**, fallback system-ui | 14–16px | 400 | `p` line-height 1.65 |
| Nav link / button | DM Sans | 14px | 500 | button letter-spacing 0.02em |
| Input text | DM Sans | 14.4px | 400 | — |
| Field label | DM Sans | 12px | 500 | UPPERCASE, letter-spacing 0.08em, muted colour |
| Eyebrow (above page title) | DM Sans | 11.5px | 600 | UPPERCASE, 0.14em, gold |
| Badge / chip | DM Sans | 11.5–11.8px | 500 | — |
| Footer | DM Sans | 11.5px | 400 | — |
| Policy prose `h2` / `h3` / `p` | DM Sans | 15.2 / 13.1 (upper) / 14px | 500 / 600 / 400 | `p` line-height 1.75, secondary colour |

### 1.3 Shape, spacing, elevation, layout

| Token | Value |
|---|---|
| Radius sm / md / lg | **6 / 12 / 20 px** (buttons and inputs 6, cards 12, login card 20); pills 100px |
| Shadow sm / md / lg (dark) | `0 2 8 /.35`, `0 6 24 /.45`, `0 16 48 /.55` black |
| Shadow (light) | same offsets, alpha .08 / .12 / .20 |
| Button padding | 10 × 22 px |
| Input padding | 10 × 14 px; 1px border; focus = gold border + surface-hover fill |
| Card padding | 24px (`.card`), 16px (entity card); hover lifts −2px + shadow-sm |
| Container | max-width **1520px**, side padding **40px** |
| Nav height | **68px** (topbar 56px) |
| Footer height | 48–52px |
| Rails | left 260px, right 320px (not needed in events) |
| Breakpoints | Ad hoc only: 640 / 700 / 800 / 1100px for some grids. **No responsive navbar.** The website is effectively desktop-first. |
| Motion | 0.15–0.2s ease transitions; `fadeUp` 0.45s on page enter |
| Decoration | gold divider (48×2px, gold → transparent gradient) under page titles; faint gold circle "geo" background |

### 1.4 Ready-to-use Flutter values (for Step 3)

```dart
// Dark (default)
const navyDeep   = Color(0xFF09192E); // scaffold
const canvas     = Color(0xFF070F1C);
const navy       = Color(0xFF0F2744);
const navyMid    = Color(0xFF162F52); // dialogs, menus
const gold       = Color(0xFFC9A84C); // primary
const goldLight  = Color(0xFFE2C97E);
const textPri    = Color(0xFFF0E6C8);
const textSec    = Color(0xFF9DB4D0);
const textMuted  = Color(0xFF5A7A9A);
const surface    = Color(0x0AFFFFFF); // 4% white
const border     = Color(0x2EC9A84C); // gold @ 18%
const borderHov  = Color(0x73C9A84C); // gold @ 45%
const success = Color(0xFF6EE7B7), warning = Color(0xFFFCD34D),
      error   = Color(0xFFF87171), info    = Color(0xFF93C5FD);

// Light
const lBg = Color(0xFFF5F0E6), lCanvas = Color(0xFFE8E2D4), lPanel = Color(0xFFEDE8D8);
const lGold = Color(0xFF8A6010), lGoldLight = Color(0xFFA07520);
const lTextPri = Color(0xFF1C2B3A), lTextSec = Color(0xFF4A6278), lTextMuted = Color(0xFF7A8898);
const lBorder = Color(0x38A07828); // rgba(160,120,40,.22)
const lSuccess = Color(0xFF166534), lWarning = Color(0xFF92400E), lError = Color(0xFF991B1B), lInfo = Color(0xFF1E3A8A);
```

---

## 2. Components inventory (website)

| Component | Website file | What it looks like |
|---|---|---|
| **Header / navbar** | `components/core/Navbar.jsx`, `styles/navbar.css` | Fixed, 68px, translucent navy + blur, gold-tint bottom border. **Left:** logo (`assets/nitksaa-logo.png`, 34px high, made white in dark mode with `filter: brightness(0) invert(1)`) + "NITKSAA" in Crimson Pro 16/600. **Centre:** text links; the active one is gold text on 8% gold fill. **Right:** 34×34 square icon buttons (radius 6, surface fill, border) for theme toggle, bell (with badge), admin shield; then a round initials avatar (navy gradient, gold ring) opening a menu (Me, Profile, Sign out). **When logged out:** brand only, no links or actions. |
| **Footer** | `components/core/Footer.jsx`, `styles/footer.css` | One 52px strip, nav background, top border. **Left:** "© {year} NITK Surathkal Alumni Association". **Right:** links separated by "·": Home · About Us · Privacy & Cookies · Terms of Use · Disclaimer · Feedback (signed-in only). 11.5px, hover = gold. |
| **Page header** | `components/core/PageHeader.jsx` | Optional gold eyebrow, Crimson Pro 35px title, gold divider, optional subtitle (15px, secondary). Sits in a sticky canvas-coloured zone. |
| **Buttons** | `global.css` `.btn*` | **Primary:** gold fill, navy text, hover lighter gold + lift + gold glow. **Ghost:** transparent, secondary text, 1px border. **Danger:** red 12% fill, red text and border. Disabled 40% opacity. Radius 6, 14px/500. |
| **Tab / segmented** | `.tab-btn` | Small pill-ish buttons; active = gold text, gold 6% fill, gold 40% border. |
| **Cards** | `.card`, `entity-card.css` | Surface fill, gold-tint border, radius 12; hover = stronger border and lift. |
| **Form fields** | `global.css` `input, select, textarea, label, .field*` | Surface fill, 1px border, radius 6, focus gold border. Labels above, uppercase muted 12px. Custom chevron on selects. Char counter right-aligned. |
| **Badges / chips** | `.badge*`, `.expertise-chip`, `.detail-status*` | Pills; status colour text, 8% fill, 30% border. Gold chips for tags. |
| **Notices / errors** | `.notice--info/pending/warning`, `.error-msg`, `.form-error` | Rounded 6, tinted fill and border. |
| **Modals** | `.modal-backdrop`, `.modal-dialog`, `.detail-panel` | Dark overlay with blur; navy-mid panel, radius 12–16, shadow-lg, slide-up. |
| **Empty / loading** | `.empty-state`, `.spinner`, `.skeleton-line` | Muted centred text; gold-topped ring spinner; gold shimmer skeleton. |
| **Toggle switch** | `.toggle-*` | 40×22 track; on = gold 20% track, gold thumb. |
| **Page width** | `.container` | 1520 max, 40px gutters. Policy and feedback pages use the same container (no narrow reading width). |

---

## 3. Policies and feedback form (website)

### 3.1 Policies

| Page | Route | Source file | Header subtitle |
|---|---|---|---|
| Privacy & Cookie Policy | `/privacy` | `webdocs/Privacy_and_Cookie_Policy.md` (52 lines) | "How we collect, use, and protect your information." |
| Terms of Use | `/terms` | `webdocs/Terms_of_Use.md` (44 lines) | "The rules and conditions governing use of this platform." |
| Website Disclaimer | `/disclaimer` | `webdocs/Website_Disclaimer.md` (11 lines) | — |
| About Us | `/about` | `webdocs/About_Us_NITKSAA.md` (70 lines) | (page component, not reviewed in depth) |
| **Refund / Cancellation** | — | **does not exist** | — |

- **How they're loaded:** each page imports the `.md` at build time (`import content from '../../../webdocs/X.md?raw'`), so they're bundled into the JS. There's no runtime fetch.
- **How they're rendered:** `components/core/MarkdownRenderer.jsx` passes the text to `react-markdown` inside `<div class="prose">`. `.prose` styles are in `global.css` (§1.2).
- **Page layout:** each page has a `PageHeader` with the title and subtitle, then `.container` with the prose. All three are **public** (no login).
- **Document title:** `"NITKSAA · <Page>"`.
- **Linked from:** the footer only.
- **Content shape:** `## Summary`, then `## Detailed Policy` or `## Terms` with `###` subsections, and contact information at the end. It's simple markdown (headings, paragraphs, bullet lists, bold), so `flutter_markdown` will render it faithfully.
- **Content gap for events:** the text describes the *alumni website*. It doesn't mention event registration, payments via Razorpay, QR badges or attendee data shared with organisers. The handoff decision is to copy unchanged now. Just note that Privacy and Terms may need event-specific additions before live payments. That's a content/legal decision, not UI.

### 3.2 Feedback form

- **Page:** `pages/FeedbackPage.jsx`, `styles/feedback-modal.css`, route `/feedback`. **Requires login** (`RequireAuth`, footer link only shown when signed in).
- **Fields:**
  - **Area:** select. Directory, Communities, Stories, Mentorship, Career Central, Connections, My Account / Profile, General / Platform. Default General.
  - **Type:** select. Something is broken (`bug`, default), Suggestion / feature request, My data is wrong, Other.
  - **Message:** textarea, 8 rows, autofocus, max **2000** chars, live "N characters remaining" counter (gold under 100).
- **Validation:** Send is disabled until the trimmed message is **≥ 10 chars**. The server re-checks 10–2000 and coerces unknown area or category to defaults.
- **States:**
  - **idle**
  - **sending:** spinner in button, fields disabled
  - **done:** green ✓ circle, "Thanks — feedback received", "We'll look into it and follow up if needed.", Go back button
  - **error:** red box, "Could not send — please email us at nitksaa.infra@gmail.com"
- **Buttons:** Cancel (ghost, goes back) and Send feedback (primary).
- **How it submits:**
  1. The page calls `POST /api/v1/feedback` on the **website's own backend** with JSON `{area, category, message}` and the user's Firebase token. The route is `backend/src/api/feedback.py`.
  2. The backend sends an HTML and plain-text email via **Gmail SMTP** (`smtp.gmail.com:587`, STARTTLS) from and to **`nitksaa.infra@gmail.com`**. It uses the Gmail App Password in Secret Manager `nitk-gmail-app-password` (env `GMAIL_APP_PASSWORD`).
  3. The subject is `[NITKSAA Website Feedback] <Area> — <Category>`. The body includes the user's email, role and ID.
  4. It returns 204 on success and 502 if SMTP fails.
- **No third-party form.**

**What this means for events (Step 7):**
- The events API (`backend/app`, deployed via `Dockerfile` → `app.main`) has **no feedback endpoint**.
- It does have an SMTP email service (`app/services/email_service.py`), currently `EMAIL_MODE=log`; wiring it is go-live item S10.
- A `/api/v1/feedback` endpoint there would be small once S10 is done. → **Sudarshana**. The secret: reuse the same Gmail app password or its S10 SMTP secret. → **Padmanand**, and note that the P6 secret lockdown means the events API service account needs an explicit grant.
- Area options for events would change to something like: Events list, Event details, Registration / payment, My Events / QR badge, Account, General.
- **Interim (recommended):** ship the form UI, and have Send open a pre-filled `mailto:nitksaa.infra@gmail.com`. That needs no backend and no secret, and switches to the endpoint later.

Note: `backend/src/` in the events repo is a **copy of the website backend** (same `notify.py`, `GMAIL_APP_PASSWORD` settings). It is not what Cloud Run runs. Don't build on it by mistake.

---

## 4. Current events attendee UI (`frontend/`)

### 4.1 Theme (`lib/theme/`)

| File | Today |
|---|---|
| `app_colors.dart` (19 lines) | Generic blue palette. Light: bg `#F7F8FA`, primary `#2563EB`. Dark: bg `#0B0D10`, primary `#5B8DEF`. **No navy or gold.** |
| `app_text_styles.dart` | 7 styles (headlineLarge 32/700 … labelSmall 11/500), **no font family** (Roboto default; on web, CanvasKit's bundled font). |
| `app_theme.dart` | `ColorScheme.fromSeed` + `copyWith` primary/onPrimary/onSurface/secondary, M3. **No component themes** (no button, input, card, app-bar, dialog, chip or nav-bar themes). |
| `theme_provider.dart` | Riverpod `ThemeNotifier`, default **`ThemeMode.system`**, toggle dark ↔ light, **not persisted**. |

**Theme toggle today:** `main.dart` draws a **floating circular toggle button** over every screen, using a `Stack` in `MaterialApp.builder`, bottom-right, raised above the bottom nav on phones. It uses its own hard-coded greys.

### 4.2 Shared widgets

| Set | Files | Used by |
|---|---|---|
| `core/widgets/` | app_card, app_empty_view, app_error_view, app_loading_view, app_primary_button (FilledButton), app_secondary_button (OutlinedButton.icon), app_text_field (OutlineInputBorder), app_scaffold | **No event screen.** All theme-driven, so they restyle for free in Step 3. |
| `widgets/material/`, `widgets/cupertino/`, `widgets/shared/` | Older duplicates (scaffold, card, buttons, info/shared screens, theme_toggle, status_row) | `login_screen.dart`, developer screen, placeholder screens |
| `shared/widgets/app_sidebar.dart` (489 lines) | Desktop sidebar, 240px (72px collapsed). Gold icon + "NITKSAA" text brand. Items: Events, My Events, Volunteer (`/volunteer` placeholder), Manage Events (admin), More (`/more` placeholder). Hard-coded colours: dark bg `#0E1726`, light `#F8F9FD`, active `#1C2A40` / `#EEF3FA`, gold `#C9952A`. | list, my events, manage, registrations |
| `shared/widgets/app_bottom_nav.dart` (146 lines) | Phone bottom nav: Events, My Events, Manage (admin) / Login. Gold `#C9952A` active. | list, my events, manage |

### 4.3 Screens

| Screen | Lines | Hard-coded colours | Theme refs |
|---|---|---|---|
| `event_detail_screen.dart` | 2,019 | 125 | 9 |
| `event_list_screen.dart` | 1,919 | 71 | 19 |
| `manage_events_screen.dart` | 3,282 | 70 | 13 |
| `event_registrations_screen.dart` | 913 | 18 | 8 |
| `my_events_screen.dart` | 548 | 16 | 6 |
| `checkout_screen.dart` | 478 | 15 | 2 |
| `auth/…/splash_screen.dart` | 263 | 21 | 3 |
| `auth/…/login_screen.dart` | 290 | 4 | 13 |

- **Layout switch:** screens check `MediaQuery.width >= 900`. Wide screens get the sidebar; narrow screens get the bottom nav.
- `event_list_screen.dart` also has a separate **Cupertino (iOS-style) layout** for native iOS only (`!kIsWeb && iOS`). Web isn't affected.
- **Dark and light:** screens branch on `Theme.of(context).brightness` and pick their own colours, e.g. list bg `#000000` / `#F2F2F7`, card `#1C1C1E` / `#FFFFFF`, iOS-like greys.
- Most-used colours: gold `#C9952A` (47×), navy `#0D1B3E` (18×), red `#8A1B1B`, slate greys.

### 4.4 Web shell (`frontend/web/`)

- `index.html`: title **`event_app`**, meta description "A new Flutter project.", apple title `event_app`, `favicon.png` (Flutter default). The Razorpay `checkout.js` is included **twice** (head and body). That's Sudarshana's part of ISSUE-022.
- `manifest.json`: name and short_name `event_app`, colours `#0175C2` (Flutter blue), default Flutter icons 192, 512 and maskable.
- **No web fonts loaded.**
- **No `assets:` section** in `pubspec.yaml`; the app ships no images.

### 4.5 Admin app (for Step 9)

`admin/event_admin/src/styles/tokens.css` already uses the **same token names** as the website, with slightly different values:
- navy-deep `#060d1a`
- gold `#c9a94a`
- border slate instead of gold

Fonts there are **Inter + Playfair Display**, loaded from Google Fonts. Aligning it is mostly a value swap plus a font change.

---

## 5. Mapping table

Legend:
- **Match:** **Same** (copy values), **Adapted** (same look, different form or content), **Not needed**.
- **Risk** (from handoff §3b):
  - **Safe**: no overlap with Sudarshana.
  - **Coordinate**: agree first or tiny agreed commit.
  - **Wait**: until his issues on that file close.

| # | Website element | Events equivalent | Match | Files to change | Risk |
|---|---|---|---|---|---|
| 1 | Colour tokens (§1.1) | Navy/gold palette, dark and light | Same | `lib/theme/app_colors.dart` | **Safe** |
| 2 | Crimson Pro + DM Sans type scale | Text theme with the two families | Same | `lib/theme/app_text_styles.dart`, `app_theme.dart` | **Safe** |
| 2a | Font files | Bundle TTFs (`fonts:` in pubspec) or `google_fonts` | — | `frontend/pubspec.yaml`, `frontend/assets/fonts/` | **Coordinate** (agreed pubspec commit; 016/023) |
| 3 | Button, input, card, chip, dialog, app-bar, snackbar, divider, nav-bar styles | `ThemeData` component themes (radius 6 / 12, gold focus, gold-tint borders) | Adapted | `lib/theme/app_theme.dart` | **Safe** |
| 4 | Dark default, toggle, remembered | `ThemeMode.dark` default; persist with Hive | Adapted | `lib/theme/theme_provider.dart` | **Safe** (decision D1) |
| 5 | `.btn-primary` / `.btn-ghost` | AppPrimaryButton / AppSecondaryButton | Same | `core/widgets/app_primary_button.dart`, `app_secondary_button.dart` (theme does most of it) | **Safe** |
| 5a | `.btn-danger` | New `AppDangerButton` | Same | new `core/widgets/app_danger_button.dart` | **Safe** |
| 6 | `.card` | AppCard | Same | `core/widgets/app_card.dart` | **Safe** |
| 7 | Inputs + uppercase labels | AppTextField (label above, not floating) | Adapted | `core/widgets/app_text_field.dart` | **Safe** |
| 8 | `.error-msg`, `.notice*` | AppErrorView + new AppNotice | Adapted | `core/widgets/app_error_view.dart`; new `app_notice.dart` | error view **Coordinate** (018); notice **Safe** |
| 9 | `.empty-state`, `.spinner` | AppEmptyView, AppLoadingView | Same | `core/widgets/app_empty_view.dart`, `app_loading_view.dart` | **Safe** |
| 10 | `PageHeader` (eyebrow, serif title, gold line) | New `PageHeader` widget | Same | new `shared/widgets/page_header.dart` | **Safe** |
| 11 | Navbar | New `SiteHeader`: logo + "NITKSAA Events", theme toggle, avatar menu (My Events, Sign out) or **Sign in** button when signed out | Adapted | new `shared/widgets/site_header.dart` | **Safe** (file); placing it on every page **Coordinate**: needs the ShellRoute (finding 2) |
| 12 | (Website has no sidebar) | Keep `AppSidebar` on desktop; restyle to tokens; swap text brand for logo | Adapted | `shared/widgets/app_sidebar.dart` (colours and brand only, not items) | **Coordinate** (021, 022) |
| 13 | (No mobile nav on website) | Keep `AppBottomNav` on phones; restyle | Adapted | `shared/widgets/app_bottom_nav.dart` (colours only) | **Coordinate** (021, 022) |
| 14 | Footer | New `SiteFooter`: © line + Privacy · Terms · Refund · Disclaimer · Feedback · "NITKSAA website ↗". Wraps to two lines on phones. | Adapted | new `shared/widgets/site_footer.dart` | **Safe** (file); placement as row 11 |
| 15 | Floating theme toggle (events only) | Move into header; remove floating button | Adapted | `lib/main.dart` (`builder:` block only) | **Coordinate** (app-level file) |
| 16 | Privacy / Terms / Disclaimer pages | Copy `.md` unchanged + source note; `PolicyScreen` rendering `.prose` look | Same | new `frontend/assets/policies/*.md`, new `features/policies/policy_screen.dart`; pubspec `assets:` + `flutter_markdown` | **Safe** (files) + **Coordinate** (pubspec) |
| 16a | Policy routes | `/privacy`, `/terms`, `/refund`, `/disclaimer`, `/feedback` | Same | `routes/app_router.dart`, `routes/app_routes.dart` | **Coordinate** (021 — the agreed tiny commit; now **5** routes, adds `/disclaimer`). `route_guards.dart` lets unlisted routes through when signed out, so policy pages stay public as long as they aren't added to its protected list. |
| 17 | Refund policy | Needs writing | — | new `frontend/assets/policies/Refund_and_Cancellation_Policy.md` | **Blocked on content** (Padmanand) |
| 18 | About Us page | Link out to website `/about` | Not needed (link) | footer only | **Safe** |
| 19 | Feedback page UI | `FeedbackScreen` with event-specific areas | Adapted | new `features/feedback/feedback_screen.dart` | **Safe** |
| 19a | Feedback submit | Interim `mailto:`; later events API `POST /api/v1/feedback` | Adapted | backend (Sudarshana), secret (Padmanand) | **Wait** for backend |
| 20 | Tab title, favicon | "NITKSAA Events", NITKSAA favicon | Adapted | `web/index.html` (title, meta, apple title), `web/favicon.png` | **Coordinate** (022, visual half only) |
| 21 | — | PWA name, colours `#09192e`, icons | Adapted | `web/manifest.json`, `web/icons/*` | **Coordinate** (022) |
| 22 | Login card look | Restyle login (serif title, gold ring, card) | Adapted | `features/auth/presentation/screens/login_screen.dart`, `splash_screen.dart` | **Wait**: `features/auth/` is on the do-not-touch list; ask Sudarshana |
| 23 | `.card` / entity card look | Event list cards | Adapted | `event_list_screen.dart` | **Wait** (layout bug, 011) |
| 24 | Detail panel look | Event detail | Adapted | `event_detail_screen.dart` | **Wait** (013, 019, 008, 020) |
| 25 | Management list look | My Events | Adapted | `my_events_screen.dart` | **Wait** (011, 004, 005, 020) |
| 26 | Form look | Checkout | Adapted | `checkout_screen.dart` (visual only) | **Wait** (007–010, 017) |
| 27 | Admin views | Manage events / registrations inside attendee app | Not needed now | `manage_events_screen.dart`, `event_registrations_screen.dart` | **Wait** / low priority |
| 28 | Website nav links (Directory, Communities…) | Single "NITKSAA website ↗" link | Not needed | — | — |
| 29 | NITiKa rail, filters rail, bell, admin shield | — | Not needed | — | — |
| 30 | Website tokens | Admin app tokens and fonts | Same | `admin/event_admin/src/styles/tokens.css`, `index.html` fonts | **Safe** (Step 9) |

### Revised expectations per step

- **Step 3 (theme):**
  - **Changes:** Material buttons, inputs, app bars, dialogs, snackbars, scaffold background where screens don't override it, the shared `core/widgets`, and the login screen's buttons.
  - **Doesn't change:** event cards, list backgrounds, sidebar and bottom nav. Those keep their current navy/gold/iOS-grey look until rows 12–13 and 23–26.
- **Step 5 (header and footer):** the widgets can be built now and shown on the policy and feedback pages. Showing them on every page needs the `ShellRoute` (Coordinate) or Step 8.
- **Step 8:** much of the real visual alignment lives here. The biggest single win is replacing each screen's local colour constants with theme lookups, one screen at a time.

---

## 6. Intended differences (deliberate, documented)

| Area | Website | Events | Why |
|---|---|---|---|
| Mobile navigation | No responsive nav | **Bottom nav** under 900px; sidebar at 900px and above | Attendees mostly use phones (QR at venue, payments) |
| Primary navigation | Header text links | Sidebar or bottom nav items (Events, My Events, Manage for admins); header holds brand, theme and account only | Few destinations; keeps nav items in Sudarshana's files untouched |
| Signed-out state | Header shows brand only; most pages need login | Event list is public; header shows a **Sign in** button | Public event discovery |
| Brand text | "NITKSAA" | "NITKSAA **Events**" | Tells the two apps apart |
| Feedback link | Signed-in only | Always visible; the form asks for sign-in or uses mailto | Payment problems may happen before sign-in works |
| Policies | Privacy, Terms, Disclaimer | Same **+ Refund & Cancellation** | Required for paid events / Razorpay |
| Event-only screens | — | Checkout, payment status, QR badge, My Events | No website equivalent; use tokens and components only |
| iOS native | — | Cupertino layout on native iOS | Existing behaviour; restyle later, web unaffected |
| Reading width | 1520px container | Cap policy and feedback text at about 760px | Readability on wide screens (small, deliberate deviation) |
| Rails | NITiKa assistant, filter rail | None | Not relevant |

---

## 7. Assets needed

| Asset | Source | Notes |
|---|---|---|
| Logo wordmark | `website: frontend/src/assets/nitksaa-logo.png` (**550×85** PNG) | Copy to `frontend/assets/images/`. Dark mode: tint white (Flutter `ColorFiltered`, or ship a white variant). Light mode: as is. |
| Favicon | `website: frontend/public/favicon.ico` (15 KB) | Flutter web wants `favicon.png`, so convert. |
| **Square app icon** (192, 512, maskable) | **Not available.** The logo is a wide wordmark. | Need a square emblem from Padmanand, or a simple "N" / "NITKSAA" monogram on navy with a gold ring (the login page uses this motif). |
| Fonts | Google Fonts, OFL licence: **Crimson Pro** 600 and 700, **DM Sans** 400, 500, 600 and 700 | **Recommend bundling the TTFs** in `frontend/assets/fonts/` with a pubspec `fonts:` section. This avoids `google_fonts` fetching from fonts.gstatic.com at runtime (offline at the venue, privacy) and adds no package. |
| Policy texts | `website: webdocs/Privacy_and_Cookie_Policy.md`, `Terms_of_Use.md`, `Website_Disclaimer.md` | Copy unchanged; add a source note at the top. |
| Refund & Cancellation policy | **Doesn't exist** | Content needed. The backend already defines refund rules (cancel via `POST /registrations/{id}/cancel`, refund of the paid amount); the text should match them. |

---

## 8. Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | Hard-coded colours in screens (finding 1) | Step 3 looks partial; reviewers may think it failed | Set expectations (§5); do Step 8 screen by screen as his issues close |
| R2 | No shared shell (finding 2) | Header and footer can't appear on existing screens without router or screen edits | Ask Sudarshana for a `ShellRoute` with the agreed routes commit, or with ISSUE-021 |
| R3 | No refund policy (finding 3) | Blocks S11 and Razorpay live | Padmanand to get the text written; UI can ship with Privacy, Terms and Disclaimer first |
| R4 | Website fonts not loaded (live site shows Georgia/system) | Events with real fonts will look *better* than the live site, not identical | Fix the website (one `<link>` in its `index.html`), or accept the difference |
| R5 | Website `--surface-ch` undefined | Footer colours on website differ from intent | Use intended values in events; tell Padmanand |
| R6 | Policy text is website-specific (no payments, events, attendee data) | Legal gap for paid events | Content review before live payments; separate from UI |
| R7 | Feedback endpoint needs backend and secret | Form can't email directly | Interim mailto; endpoint after S10; P6 lockdown means an explicit secret grant |
| R8 | Light-mode default differs: events follows system; website defaults dark | Users on light phones see a very different app | Decision D1: default dark like the website |
| R9 | `pubspec.yaml` edits overlap 016/023 | Merge conflicts | One small agreed commit (fonts + assets + `flutter_markdown`), announced first |
| R10 | `web/index.html` overlaps 022 (duplicate `checkout.js`) | Conflict or accidental payment breakage | Touch only title, meta and icon lines; ₹1 test payment after |
| R11 | Stray `backend/src/` (website backend copy) in events repo | Someone builds the feedback endpoint in the wrong place | Endpoint goes in `backend/app/`; mention to Sudarshana |
| R12 | Bundled fonts increase first-load size (~300–500 KB) | Slower first load on mobile data | Ship only the weights listed; check the beta load time |
| R13 | Logo PNG is 550px wide | Blurry on high-DPI at 34px high | Ask for an SVG, or use 2×/3× variants |

---

## 9. Decisions for Padmanand

| # | Decision | Recommendation |
|---|---|---|
| D1 | Default theme | **Dark**, persisted, like the website |
| D2 | Fonts | **Bundle** Crimson Pro + DM Sans; also fix the website's missing font link |
| D3 | Header and footer on every page | Ask Sudarshana for a **ShellRoute** (with the agreed routes commit) |
| D4 | Disclaimer page | **Include** (`/disclaimer`), so the agreed routes become 5 |
| D5 | Refund policy | Who writes it, and by when (blocks S11) |
| D6 | Feedback submission | **mailto interim**, endpoint after S10 |
| D7 | App icon | Provide a square emblem, or approve a monogram |
| D8 | Floating theme toggle | Move into the header (small `main.dart` edit, agree with Sudarshana) |
| D9 | Login/splash restyle | Ask Sudarshana; `features/auth/` is his |

---

## 10. Suggested message additions for Sudarshana

- **Routes:** 5 routes now, adding `/disclaimer`. Ask if he'd also add a `ShellRoute` so the header and footer wrap all pages.
- **`main.dart`:** OK to replace the floating theme toggle with a header toggle?
- **Login and splash:** OK to restyle visually (in `features/auth/`)?
- **Feedback endpoint:** after S10, in `backend/app/`, not `backend/src/`.
