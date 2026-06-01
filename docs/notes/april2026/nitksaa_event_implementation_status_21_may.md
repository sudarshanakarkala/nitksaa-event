# NITKSAA Event Platform — Implementation Status

**As of:** May 22, 2026
**Sprint:** S2 (May 17 – May 30) | Sprint 1 complete

---

## Project Overview

A multi-tenant-ready event operations platform for professional alumni and community events. Two applications on a shared Firebase backend.

| Component | Stack | Status |
|---|---|---|
| Event App | Flutter (iOS + Android) | Foundation complete, auth UI scaffolded |
| Admin Portal | React + Vite + Tailwind | Bootstrapped (basic) |
| Backend | FastAPI + Docker + GCP | Skeleton started |
| Firebase | Auth + Firestore (shared project) | Connected and initialized |

**Target GA:** October 31, 2026 | **Team size:** 3 engineers

---

## What Is Done

### Event App (Flutter)

#### Project Foundation
- Flutter project created, package ID `org.nitksaa.event` (Android + iOS)
- Firebase connected — Android and iOS apps registered, `google-services.json` and `GoogleService-Info.plist` in place
- Firebase Core initializes on startup with error handling; `AppState.firebaseInitialized` flag tracks status
- Hive initialized (`hive_flutter`) for future offline storage
- All foundational packages added to `pubspec.yaml`

#### Architecture & Folder Structure
Feature-first structure under `lib/`:
```
lib/
├── core/
│   ├── app_state.dart          — global initialization flags
│   ├── logger/app_logger.dart  — structured logger (pretty-printer)
│   ├── constants/              — (placeholder)
│   ├── errors/                 — (placeholder)
│   ├── extensions/             — (placeholder)
│   ├── network/                — (placeholder)
│   ├── storage/                — (placeholder)
│   ├── utils/                  — (placeholder)
│   └── widgets/                — (placeholder)
├── features/
│   ├── auth/
│   │   ├── data/               — (placeholder)
│   │   ├── domain/             — (placeholder)
│   │   ├── presentation/
│   │   │   ├── screens/
│   │   │   │   ├── splash_screen.dart
│   │   │   │   ├── login_screen.dart
│   │   │   │   └── auth_wrapper_screen.dart
│   │   │   └── widgets/        — (placeholder)
│   │   └── services/firebase_auth_service.dart
│   ├── developer/
│   │   └── presentation/developer_diagnostics_screen.dart
│   ├── foundation/
│   │   └── presentation/foundation_ready_screen.dart
│   └── home/
│       └── presentation/home_placeholder_screen.dart
├── routes/
│   ├── app_router.dart         — GoRouter config
│   ├── app_routes.dart         — route constants
│   └── route_guards.dart       — (placeholder, guards not yet wired)
├── theme/
│   ├── app_colors.dart
│   ├── app_text_styles.dart
│   ├── app_theme.dart
│   └── theme_provider.dart
├── firebase_options.dart
└── main.dart
```

#### Routing (GoRouter)
Five routes defined:

| Path | Screen | Purpose |
|---|---|---|
| `/` | `FoundationReadyScreen` | Dev-only foundation status page |
| `/splash` | `SplashScreen` | App entry — auto-navigates to `/home` or `/login` |
| `/login` | `LoginScreen` | Auth UI |
| `/home` | `HomePlaceholderScreen` | Post-login placeholder |
| `/developer` | `DeveloperDiagnosticsScreen` | Debug screen (debug mode only) |

Initial location is `/splash`. Route guards file exists but logic is not yet wired.

#### Theme System
- Material 3 (`useMaterial3: true`)
- Light and dark themes fully defined via `AppTheme.light` / `AppTheme.dark`
- Color palette in `AppColors`: light primary `#2563EB`, dark primary `#5B8DEF`
- Typography scale in `AppTextStyles`: headlineLarge → labelSmall
- Theme runtime switching via Riverpod `themeProvider` (`ThemeMode.system` default)
- `ThemeNotifier` (Riverpod `Notifier`) with `setTheme()` method

#### Logging
`AppLogger` wraps the `logger` package with `PrettyPrinter`. Methods: `debug`, `info`, `warning`, `error`. Used throughout app lifecycle and auth flow.

#### Screens Implemented

**SplashScreen** (`/splash`)
- 2-second delay, then checks `FirebaseAuth.instance.currentUser`
- Navigates to `/home` if authenticated, `/login` if not
- UI: brand icon, app name, org name, progress indicator

**LoginScreen** (`/login`)
- Email + password `TextField` controllers with dispose
- Password visibility toggle
- `FilledButton` for email login (handler logs intent, TODO: connect service)
- `OutlinedButton.icon` for Google Sign-In (handler logs intent, TODO: connect service)
- Debug-mode-only link to Developer Diagnostics
- Constrained to `maxWidth: 420` (tablet-safe)

**AuthWrapperScreen**
- `StatefulWidget` that checks auth synchronously on first frame
- Redirects to `/home` or `/login` via `postFrameCallback`
- Shows `CircularProgressIndicator` while resolving

**HomePlaceholderScreen** (`/home`)
- Confirms authentication success visually
- Functional sign-out: calls `FirebaseAuth.instance.signOut()` → navigates to `/login`
- AppBar with logout `IconButton`

**FoundationReadyScreen** (`/`)
- Shows Firebase + Theme status with green/red icons
- Link to Developer Diagnostics

**DeveloperDiagnosticsScreen** (`/developer`)
- Diagnostic rows: App Name, Environment, Firebase status, Hive status, Theme Mode, Platform, Router, Logger, Auth Status
- Logger test buttons (debug / info / warning / error)
- Theme control via `SegmentedButton<ThemeMode>` (light / system / dark)
- Warning banner — not for production UI
- Back navigation with fallback to `/home`

#### Auth Service
`FirebaseAuthService` (abstract, static methods):
- `signInWithEmail(email, password)` — stub, returns `null` (TODO)
- `signOut()` — implemented, calls `FirebaseAuth.instance.signOut()`

#### State Management (Riverpod)
- `ProviderScope` wraps the entire app in `main.dart`
- `themeProvider` (`NotifierProvider<ThemeNotifier, ThemeMode>`) — only active provider
- `ConsumerWidget` used in `DeveloperDiagnosticsScreen` and `FoundationReadyScreen`

#### Dependencies (`pubspec.yaml`)
```yaml
firebase_core: ^4.8.0
firebase_auth: ^6.5.0
flutter_riverpod: ^3.3.1
go_router: ^17.2.3
dio: ^5.9.2
hive: ^2.2.3
hive_flutter: ^1.1.0
logger: ^2.7.0
```

Dev: `build_runner`, `hive_generator`, `flutter_lints`

---

### Admin Portal (React/Vite)

- Repository bootstrapped
- Tailwind CSS configured
- Basic folder structure created
- Login placeholder UI present
- Theme/design foundation started

_(Full detail not in scope of this review — source is in separate repo)_

---

### Backend (FastAPI)

- Repository bootstrap started
- FastAPI skeleton with Poetry + Docker created (basic)
- Firebase project setup complete (shared with Event App)
- Repo branching strategy defined
- CI/CD planning documented

---

### Firebase / Infrastructure

| Item | Status |
|---|---|
| Firebase project created | Done — "NITKSAA Alumni Database" (Blaze plan) |
| Android Firebase app registered | Done — `NITKSAA Event Android` |
| iOS Firebase app registered | Done — `NITKSAA Event iOS` |
| Admin Portal Firebase app | Done — `NITKSAA Event Admin` |
| Firebase Auth providers | Configured (email/password + Google) |
| Firebase Core in Flutter | Initializing successfully |
| Cloud Run / Cloud SQL | Not Started |
| Secret Manager | Not Started |
| Terraform | Not Started |

---

### Documentation

| Document | Location | Status |
|---|---|---|
| Requirements & Design | `docs/event_management_requirement_and_design.md` | Draft |
| Architecture Flow | `docs/nitksaa_event_architecture_flow.md` | Done |
| Sprint Release Plan | `docs/sprint_release_plan.md` | Done (13 sprints defined) |
| Improvement Roadmap | `docs/improvement_roadmap.md` | Done |
| Pre-Kickoff Readiness | `docs/pre_kickoff_readiness.md` | Done |
| Platform Engineering Principles | `docs/guidelines/NITKSAA_Platform_Engineering_Principles_v1.md` | Done |
| Digital Master Plan | `docs/guidelines/NITKSAA_Digital_Master_Plan_v2.1.md` | Done |
| Architecture Review | `docs/guidelines/event_platform_architecture_review.md` | Done |
| Engineer Progress Notes | `docs/notes/skarkala-progress.md` | Active |

---

## What Is NOT Done (Pending)

### Sprint 2 Scope (Current — May 17–30)
- Email/password sign-in logic in `FirebaseAuthService.signInWithEmail()`
- Google Sign-In implementation
- Route guards — redirect unauthenticated users from protected routes
- Auth state stream listener (replace one-shot `currentUser` check)
- Backend: Firebase token verification endpoint
- Admin Portal: working login flow

### Sprint 3+ (Upcoming)
- Event CRUD (create, list, detail) — backend + mobile
- Registration flow (free events)
- Razorpay payment integration
- QR check-in system
- Push notifications
- Offline sync (Hive models and sync logic)
- Session and speaker management
- Role-based access (admin / event manager / volunteer / attendee)
- Reports and analytics dashboard
- Remote Config for multi-brand support
- Localization
- Refund workflow
- Audit log viewer
- Production CI/CD (GitHub Actions → Cloud Build)
- Cloud Run + Cloud SQL provisioning
- Staging and production environments

---

## Current Design

### Navigation Flow
```
App Start
  └── main.dart: Firebase init → Hive init → runApp(ProviderScope)
        └── MaterialApp.router (GoRouter)
              └── /splash (initial)
                    ├── user authenticated → /home
                    └── no user → /login
                          └── (sign-in success) → /home
                                └── sign out → /login
```

### Auth Design (Current State)
One-shot check via `FirebaseAuth.instance.currentUser` on splash. No stream listener yet — auth state changes mid-session are not handled reactively. The `AuthWrapperScreen` exists as a synchronous guard but is not wired to GoRouter's `redirect` callback.

### Theme Design
Material 3 dual-theme. Primary blue (`#2563EB` light / `#5B8DEF` dark). Dark background near-black (`#0B0D10`). No custom fonts — system default. Theme persists only in memory (Riverpod state, not persisted to Hive yet).

### Platform Targets
- Android (`org.nitksaa.event`)
- iOS (`org.nitksaa.event`)
- Dart SDK `^3.10.7`

---

## Firebase Project Configuration

| Item | Value |
|---|---|
| Project Name | NITKSAA Alumni Database |
| Plan | Blaze |
| Android App | `NITKSAA Event Android` — package `org.nitksaa.event` |
| iOS App | `NITKSAA Event iOS` — bundle ID `org.nitksaa.event` |
| Admin App | `NITKSAA Event Admin` — web |

---

## Sprint Timeline Summary

| Sprint | Dates | Theme | Target Milestone |
|---|---|---|---|
| **S1** | May 3–16 | Foundation Setup | Repos, infra, auth skeleton — **Done** |
| **S2** | May 17–30 | Auth & App Shells | Login works end-to-end on all 3 apps — **In Progress** |
| S3 | May 31–Jun 13 | Events Core | Event CRUD end-to-end |
| S4 | Jun 14–27 | Registration MVP | First breakfast meeting beta |
| S5 | Jun 28–Jul 11 | Check-in + Razorpay | Paid flow + QR check-in |
| S6 | Jul 12–25 | MVP Hardening | MVP v1.0 in Production |
| S7–S10 | Jul–Sep | Phase 2 | Sessions, push, Remote Config, payments dashboard |
| S11–S13 | Sep–Oct | Phase 3 + GA | Refunds, audit, analytics, production hardening |



# SKarkala Progress Notes

## Firebase Project

| Item | Value |
|---|---|
| Project name | NITKSAA Alumni Database |
| Project ID |  |
| Project number |  |
| Web app | Alumni Portal Web |
| Environment | Unspecified |
| Plan | Blaze |

## Firebase Apps

| Platform | Firebase App Nickname | Package / Bundle ID |
|---|---|---|
| Admin Portal (React Web) | `NITKSAA Event Admin` | Web App |
| Event App Android | `NITKSAA Event Android` | `org.nitksaa.event` |
| Event App iOS | `NITKSAA Event iOS` | `org.nitksaa.event` |

## Product Configuration

| Item | Value |
|---|---|
| GitHub repo | `nitksaa-event` |
| Product name | `NITKSAA Event` |
| Firebase project | Existing shared project |
| Android package | `org.nitksaa.event` |
| iOS bundle ID | `org.nitksaa.event` |

## Firebase App IDs



## Flutter Run Command

```bash
flutter run
```

## NITKSAA Event Platform

### Sprint 1: Current Sprint

**Theme:** Foundation Setup

**Goal:** All apps running locally with stable architecture, Firebase integration, placeholder authentication flow, and a production-safe project structure.

### Included In Sprint 1

#### Event App

- [x] Flutter project setup
- [x] Firebase integration
- [x] Riverpod setup
- [x] GoRouter setup
- [x] Hive setup
- [x] Logger setup
- [x] Folder architecture
- [x] Theme foundation
- [x] Developer diagnostics
- [x] Splash screen
- [x] Auth wrapper
- [x] Login UI
- [x] Firebase Auth foundation
- [x] Email login
- [x] Google login
- [x] Logout flow
- [x] Placeholder home screen

#### Backend

- [x] Backend repository bootstrap
- [x] Firebase project setup
- [x] Initial infrastructure planning
- [x] Docker/FastAPI skeleton (basic)
- [x] Repo strategy
- [x] CI/CD planning

#### Admin Portal

- [x] React/Vite bootstrap
- [x] Tailwind setup
- [x] Basic folder structure
- [x] Login placeholder UI
- [x] Theme/design foundation

#### Documentation

- [x] Architecture documents
- [x] Sprint planning
- [x] Workflow/process setup
- [x] Git strategy
- [x] Production-safe engineering workflow

## Current Status

Sprint 1 is mainly focused on foundation, authentication, and architecture stabilization. It is not full feature development yet.

### In Progress

1. Splash screen
2. Auth state wrapper
3. Login screen UI only
4. Firebase Auth service
5. Email login
6. Google login
7. Logout

### Pending Items: Upcoming Phases

- [ ] Event management modules
- [ ] Event listing APIs
- [ ] Registration flow
- [ ] QR / badge functionality
- [ ] Push notifications
- [ ] Offline sync
- [ ] Admin Portal development
- [ ] Backend API services
- [ ] CI/CD automation
- [ ] Production deployment
- [ ] Analytics and monitoring
- [ ] Security hardening
- [ ] Role-based access
- [ ] Event check-in workflows
- [ ] Reports and dashboards

## Progress Update: May 12, 2026

- GitHub repository initialized
- Firebase project connected successfully
- Android Firebase app configured
- iOS Firebase app configured
- Firebase initialization verified in Flutter
- Foundational packages added
- Production-grade `.gitignore` created
- Initial scalable folder architecture created
- Architecture review process established
- Controlled AI-assisted development workflow established

## Engineering Rationale

This is the correct enterprise approach because architecture mistakes become expensive later. Authentication, navigation, and theme foundations affect all future screens, and stabilizing them now saves significant rework later.
