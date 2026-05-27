# Current Project Status Review

Review date: 2026-05-27  
Repository root: `nitksaa-event`  
Primary app reviewed: `apps/event_app`

This report reviews the current repository state before backend vertical slice implementation begins. It is based on static inspection plus `flutter analyze` and `flutter test`. No code changes, package installs, refactors, backend work, or auth implementation were performed.

## 1. Repository Overview

The repository is currently a Flutter-first project with architecture and planning documentation. The implemented runtime code lives under `apps/event_app`; there is no implemented backend service in this repository at the time of review.

Root structure summary:

```text
.
├── README.md
├── TOBE READ/
├── apps/
│   └── event_app/
│       ├── android/
│       ├── ios/
│       ├── lib/
│       ├── linux/
│       ├── macos/
│       ├── test/
│       ├── web/
│       ├── windows/
│       ├── firebase.json
│       ├── pubspec.yaml
│       └── pubspec.lock
├── docs/
│   ├── guidelines/
│   ├── notes/
│   ├── event_management_requirement_and_design.md
│   ├── improvement_roadmap.md
│   ├── nitksaa_event_architecture_flow.md
│   ├── pre_kickoff_readiness.md
│   └── sprint_release_plan.md
└── firebase/
    ├── android/google-services.json
    └── ios/GoogleService-Info.plist
```

Important modules:

| Area | Current state |
|---|---|
| Flutter app | Present at `apps/event_app` |
| Backend | Not present |
| Database/migrations | Not present |
| Firebase config | Present for Flutter and platform files |
| Docs | Strong planning/reference docs already present |
| Tests | One Flutter widget test |
| CI/CD | No workflow or pipeline config found |

Architecture style:

- The app is organized around a feature-first Flutter layout with `core`, `features`, `routes`, and `theme`.
- Many intended architecture folders exist as placeholders through `.gitkeep`.
- The current implementation is a foundation scaffold rather than a complete feature app.
- Frontend/backend separation is clear by absence: Flutter exists, backend has not been created yet.

## 2. Flutter Application Review

Current `lib` structure:

```text
apps/event_app/lib
├── app/
├── config/
├── core/
│   ├── app_state.dart
│   ├── constants/
│   ├── errors/
│   ├── extensions/
│   ├── logger/app_logger.dart
│   ├── network/
│   ├── storage/
│   ├── utils/
│   └── widgets/
├── features/
│   ├── auth/
│   ├── developer/
│   ├── foundation/
│   └── home/
├── firebase_options.dart
├── main.dart
├── routes/
├── services/
├── shared/
├── theme/
└── widgets/
```

App structure:

- `main.dart` initializes Flutter bindings, Firebase, Hive, logging, and wraps the app in `ProviderScope`.
- `MaterialApp.router` is used with light/dark theme support and `GoRouter`.
- There are 18 Dart source files in `apps/event_app/lib`.
- Implemented screens are foundation, splash, login, home placeholder, auth wrapper, and developer diagnostics.

Routing architecture:

- `AppRoutes` centralizes route constants.
- `AppRouter` defines routes for `/`, `/splash`, `/login`, `/home`, and `/developer`.
- Initial route is `/splash`.
- `route_guards.dart` is a placeholder only.
- `AuthWrapperScreen` exists but is not currently wired into `GoRouter`.
- There is no `GoRouter.redirect` protection for authenticated routes yet.

Riverpod usage:

- `ProviderScope` is configured at the root.
- Riverpod is currently used for theme state through `NotifierProvider<ThemeNotifier, ThemeMode>`.
- There are no auth, API, repository, cache, or feature state providers yet.

GoRouter usage:

- Basic route table is clean and centralized.
- No shell routes, nested routes, route refresh listenables, auth redirects, or typed route model exist yet.
- Debug route diagnostics are disabled.

Theme architecture:

- `AppTheme.light` and `AppTheme.dark` are implemented.
- `AppColors` and `AppTextStyles` centralize color and typography tokens.
- `themeProvider` allows changing `ThemeMode`.
- Theme is functional, but design tokens are still minimal.
- `AppTextStyles` uses negative letter spacing in headline styles, which is not an analyzer issue but should be reviewed against the platform design guidance before heavy UI expansion.

Reusable widgets:

- No reusable production widgets are implemented yet under `core/widgets`, `shared`, or `widgets`.
- Existing private helper widgets are local to screens, for example `_StatusRow`, `_SectionLabel`, and `_DiagRow`.
- Current UI uses raw Material widgets directly: `TextField`, `FilledButton`, `OutlinedButton`, `Card`, `ListTile`, and `SegmentedButton`.

Diagnostics/dev tooling:

- `DeveloperDiagnosticsScreen` is useful and already checks Firebase initialization, Hive, platform, router, logger, theme, and auth status.
- Logger test buttons exist for debug/info/warning/error.
- Diagnostic screen is reachable from login in debug mode and from foundation/home fallback routes.

Strengths:

- Clean foundation with FlutterFire, Riverpod, GoRouter, Hive, theme, and logger already integrated.
- Good early separation of routes, theme, core, and feature folders.
- Developer diagnostics provide fast feedback while foundation work continues.
- Analyzer is clean.

Inconsistencies and gaps:

- Auth service is static and not Riverpod-injected; future testability and mocking will suffer unless this is adjusted.
- Login screen handlers do not call the service yet.
- Home screen signs out directly through `FirebaseAuth.instance`, while `FirebaseAuthService.signOut` also exists.
- `AuthWrapperScreen` and `route_guards.dart` imply route protection, but routing does not use them.
- Folder placeholders suggest planned layering, but `auth/services` currently sits beside empty `data` and `domain` layers.
- No app-level network client despite `dio` dependency.
- No shared components yet, so feature expansion may duplicate UI patterns if not addressed before screens multiply.

## 3. Firebase Review

Firebase apps/platforms configured:

| Platform | Current status |
|---|---|
| Web | Configured in `lib/firebase_options.dart` |
| Android | Configured in `lib/firebase_options.dart` and `android/app/google-services.json` |
| iOS | Configured in `lib/firebase_options.dart` and `ios/Runner/GoogleService-Info.plist` |
| macOS | Configured in `lib/firebase_options.dart` and `macos/Runner/GoogleService-Info.plist` |
| Windows | Configured in `lib/firebase_options.dart` |
| Linux | Explicitly unsupported in `DefaultFirebaseOptions.currentPlatform` |

Firebase initialization flow:

- `main.dart` calls `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.
- On success, `AppState.firebaseInitialized = true`.
- Success and failure are logged through `AppLogger`.
- The app continues after Firebase initialization failure because the exception is caught.

Configuration observations:

- `apps/event_app/firebase.json` exists and points platform outputs to the app platform folders.
- Generated `firebase_options.dart` is present.
- Platform config files exist inside the app and also under root `firebase/`.
- The root `firebase/android/google-services.json` differs from `apps/event_app/android/app/google-services.json`.
- The root `firebase/ios/GoogleService-Info.plist` differs from both `apps/event_app/ios/Runner/GoogleService-Info.plist` and `apps/event_app/macos/Runner/GoogleService-Info.plist`.
- `firebase.json` contains an Android Dart configuration app id that differs from the Android platform default app id in the same file. This should be reconciled before production release.

Current auth integration status:

- `firebase_auth` is installed and imported in splash, auth wrapper, home, diagnostics, and auth service.
- Splash checks `FirebaseAuth.instance.currentUser`.
- Logout works by calling `FirebaseAuth.instance.signOut()`.
- Email/password sign-in and Google sign-in are placeholders.

Missing production Firebase/auth pieces:

- No implemented Firebase email/password login.
- No Google Sign-In package or OAuth flow integration.
- No Firebase ID token exchange with a backend.
- No auth state provider or stream-driven auth lifecycle.
- No route-level auth guard.
- No token refresh, API auth header injection, or backend session contract.
- No Firebase emulator or environment switching setup.
- No production signing config for Android release.

## 4. Authentication Status

Splash flow:

- Functional for checking current local Firebase user state.
- Uses a fixed 2-second delay, then routes to `/home` if a Firebase user exists or `/login` otherwise.
- It is not stream-based and does not wait for backend profile/session resolution.

Login screen:

- UI exists for email/password and Google sign-in.
- Email and password controllers are present.
- Password visibility toggle works.
- Handlers only log TODO actions; no sign-in occurs.
- Developer Diagnostics link appears in debug mode.

Auth wrapper:

- `AuthWrapperScreen` exists and redirects based on `FirebaseAuth.instance.currentUser`.
- It is not currently included in the router table.
- It should be considered deferred.

Logout:

- Functional in `HomePlaceholderScreen` via `FirebaseAuth.instance.signOut()`.
- `FirebaseAuthService.signOut()` is also functional but not used by `HomePlaceholderScreen`.

Route protection:

- Not implemented.
- `/home` can be reached directly if the route is entered.
- `route_guards.dart` is a comment-only placeholder.

Auth services:

- `FirebaseAuthService.signInWithEmail` is UI-only/deferred and returns `null`.
- `FirebaseAuthService.signOut` is functional.
- No Google sign-in service exists.
- No backend auth service, token exchange, JWT storage, or user profile service exists.

Summary:

| Auth item | Status | Notes |
|---|---|---|
| Splash user check | Partial | Uses `currentUser`; no backend session |
| Login UI | Present | UI only |
| Email/password login | Deferred | TODO only |
| Google login | Deferred | TODO only; no package integration |
| Logout | Functional | Direct Firebase sign-out works |
| Auth wrapper | Present but unused | Not wired into router |
| Route protection | Missing | No `GoRouter.redirect` or guards |
| Backend session | Missing | No API/backend yet |

## 5. Backend Readiness Review

No backend implementation exists in this repository.

Inspection found no active:

- `backend/`
- `server/`
- `api/`
- FastAPI app
- Python dependency file
- Dockerfile
- backend tests
- backend service/repository/database layer

Relevant backend architecture exists in documentation only. The docs reference a future FastAPI backend, `/api/v1` route conventions, event database boundaries, auth token exchange, and deployment patterns. This is good planning material, but there is no executable backend slice yet.

## 6. Database Readiness Review

No implemented database layer exists in this repository.

Inspection found no active:

- `database/`
- `db/`
- `migrations/`
- `.sql` migration files
- ORM models
- database utilities
- migration tooling

Database readiness is currently documentation-only. Existing docs discuss `events_db`, `registrations`, `check_ins`, `sessions`, `firebase_uid`, `ref_id`, and avoiding cross-database foreign keys, but no schema has been created.

## 7. Shared Component Readiness

Reusable UI components currently available:

| Component | Exists? | Notes |
|---|---|---|
| AppButton | No | Raw `FilledButton` / `OutlinedButton` used directly |
| AppTextField | No | Raw `TextField` used in login |
| AppCard | No | Raw `Card` used in diagnostics |
| LoadingView | No | Inline `CircularProgressIndicator` used |
| ErrorView | No | No common error surface |
| EmptyStateView | No | No reusable empty state |
| AppScaffold/AppShell | No | Screens use direct `Scaffold` |
| AppSnackbar/Toast | No | No feedback utility |
| AppDialog/Modal | No | Not implemented |
| Theme toggle | Partial | Implemented inside diagnostics only |
| Status row | Partial | Private `_StatusRow` and `_DiagRow` only |
| Developer diagnostics | Yes | Implemented screen-level diagnostics |

Readiness assessment:

- Shared component layer is not ready for feature-scale implementation.
- Before adding event list/detail/registration/check-in screens, define a small shared UI kit to avoid repeated raw Material patterns.
- Components should remain minimal and app-specific rather than over-abstracted.

## 8. Dependency Review

Important installed packages from `pubspec.lock`:

| Package | Version | Purpose | Concerns |
|---|---:|---|---|
| `firebase_core` | 4.8.0 | Firebase initialization | Config consistency should be verified |
| `firebase_auth` | 6.5.0 | Firebase user auth | Sign-in flows not implemented |
| `flutter_riverpod` | 3.3.1 | State management | Only theme provider uses it so far |
| `go_router` | 17.2.3 | Routing | No guards/redirects yet |
| `dio` | 5.9.2 | Future API client | Installed but unused |
| `hive` | 2.2.3 | Local storage | Initialized but no boxes/models yet |
| `hive_flutter` | 1.1.0 | Flutter Hive integration | Initialized only |
| `logger` | 2.7.0 | Structured logging | Uses colored/emojified pretty logs; review production behavior |
| `build_runner` | 2.4.13 | Code generation | Present for future generated code |
| `hive_generator` | 2.0.1 | Hive adapters | Present but no Hive models yet |
| `flutter_lints` | 6.0.0 | Static linting | Analyzer currently clean |

`flutter pub get` previously reported newer package versions are available but incompatible with current constraints. No package upgrade was performed as part of this review.

## 9. Current Technical Debt

Identified debt and risks:

- Auth flow is incomplete: login UI exists but sign-in does not work.
- Route protection is incomplete: guards are placeholders and `/home` is directly reachable.
- Auth responsibility is duplicated between direct `FirebaseAuth.instance` calls and `FirebaseAuthService`.
- `FirebaseAuthService` is static, making dependency injection and tests harder.
- `AppState.firebaseInitialized` is global mutable state, not reactive and not Riverpod-managed.
- `Dio` is installed but no API client, interceptors, error model, or auth token handling exists.
- Hive is initialized but no storage abstraction or boxes exist.
- Feature folders contain many placeholders, but real layering conventions have not been proven.
- No shared UI components exist; UI duplication will grow quickly if vertical slice screens start immediately.
- No backend, database, migrations, or API contracts are implemented.
- No CI/CD configuration exists.
- No environment/config strategy exists beyond generated Firebase options.
- Firebase config copies differ between root `firebase/` and app platform folders; ownership/source of truth should be clarified.
- Android release build still uses debug signing config.
- Default Flutter README content remains in `apps/event_app/README.md`.
- `.DS_Store` files and untracked `TOBE READ/` content are present in the working tree.

## 10. Production Readiness Status

| Area | Status |
|---|---|
| Flutter Foundation | Partial / Good foundation |
| Firebase Setup | Partial / Runs locally, needs config reconciliation |
| Shared UI | Not ready |
| Auth | UI/Scaffold only, not production-ready |
| Backend | Not started |
| Database | Not started |
| Documentation | Strong planning docs, weak app README |
| Testing | Minimal |
| CI/CD | Missing |
| API Integration | Not started |
| Local Storage | Initialized only |
| Logging | Basic available |

## 11. Backend Vertical Slice Readiness

Is the project ready to begin `events_db` schema?

- Yes, from a planning standpoint.
- No executable database/migration structure exists yet.
- Recommended first step is to establish migration location and naming before writing tables.

Is the project ready to begin FastAPI backend?

- Yes, as a greenfield addition.
- There are no current backend constraints in code.
- Existing docs provide useful conventions for `/api/v1`, auth, `events_db`, and deployment.

Is the project ready to begin event CRUD?

- Backend can begin, but Flutter is not yet ready to consume it cleanly.
- Add API client, response/error models, environment config, and event models before wiring UI.

Is the project ready to begin registration flow?

- Conceptually yes, but implementation needs backend auth/session design first.
- Registration should not begin before deciding Firebase ID token versus internal JWT exchange.
- `ref_id` / alumni identity contract must be finalized before schema and API implementation.

Is the project ready to begin QR check-in APIs?

- Not as the first slice.
- QR check-in depends on event schema, registration identity, check-in token strategy, operator permissions, and audit rules.
- It should follow after event CRUD and registration are stable.

Blockers before a clean vertical slice:

- No backend folder or dependency strategy.
- No migration convention.
- No auth contract between Flutter, Firebase, and backend.
- No Flutter API client/config layer.
- No shared error handling.
- No route protection.

Recommended vertical slice order:

1. Define backend/migration structure.
2. Create `events_db` initial schema.
3. Implement FastAPI health and event read endpoints.
4. Add Flutter API client/environment config.
5. Add event list/detail UI.
6. Implement authenticated registration.
7. Add admin/event CRUD.
8. Add QR check-in APIs and operator flow.

## 12. Recommended Immediate Next Steps

Today's action items:

- Decide and document backend folder location, for example `backend/`.
- Decide migration location, for example `database/migrations/events_db/`.
- Decide auth contract: Firebase ID token directly to backend or Firebase token exchanged for internal JWT.
- Reconcile Firebase config source of truth between root `firebase/` and `apps/event_app` platform files.
- Define minimal Flutter API client shape using existing `dio`.
- Define minimal shared components needed for the first event list/detail slice.

This week's action items:

- Scaffold FastAPI backend with health endpoint and `/api/v1` prefix.
- Add `events_db` initial migration with `events`, `sessions`, `registrations`, and `check_ins` only if the data contract is approved.
- Add backend settings/config pattern and local `.env` example policy without committing secrets.
- Implement backend Firebase token verification or internal JWT validation.
- Implement Flutter API base URL/environment config.
- Implement route protection and an auth state provider.
- Add CI for `flutter analyze` and `flutter test`.
- Expand tests around routing, auth decisions, and API client error parsing.

Safe tasks:

- Documentation updates.
- Backend skeleton with health route.
- Migration convention decision.
- Shared Flutter UI primitives.
- Flutter API client abstraction without screen coupling.
- Analyzer/test CI setup.

Risky tasks to avoid right now:

- Building QR check-in before registration and identity contracts are stable.
- Creating event tables before confirming `ref_id`, `firebase_uid`, and alumni lookup rules.
- Duplicating alumni profile data into event tables as source of truth.
- Adding direct `Dio` calls inside screens.
- Expanding screens with raw Material widgets before shared primitives exist.
- Adding another auth abstraction without deciding backend session ownership.

## 13. Validation Commands

Commands were run from `apps/event_app`.

### `flutter analyze`

Output:

```text
Analyzing event_app...
No issues found! (ran in 1.6s)
```

Status: Passed.

Warnings:

- No analyzer warnings.
- No deprecated API warnings reported by analyzer.

### `flutter test`

Output:

```text
00:00 +0: loading /Users/ananth/iTelematics/NITK_Project/NITK_Alumni/nitksaa-event/apps/event_app/test/widget_test.dart
00:01 +0: Foundation screen renders correctly
00:01 +1: Foundation screen renders correctly
00:01 +1: All tests passed!
```

Status: Passed.

Test coverage notes:

- Only one widget test exists.
- It verifies the foundation screen title renders.
- There are no auth tests, router tests, service tests, API tests, model tests, or integration tests.

## 14. Final Engineering Assessment

Scores:

| Dimension | Score |
|---|---:|
| Overall project health | 5.5 / 10 |
| Architecture quality | 6.0 / 10 |
| Maintainability | 5.5 / 10 |
| Scalability | 4.5 / 10 |

Biggest strengths:

- Clean Flutter foundation with Firebase, Riverpod, GoRouter, Hive, theming, and logging already wired.
- Analyzer and current tests pass.
- Documentation is unusually strong for product direction, architecture goals, release planning, and backend conventions.
- Folder structure anticipates scalable layering.
- Developer diagnostics are a good early operational habit.

Biggest risks:

- Backend and database are not started, so the vertical slice has no executable server foundation yet.
- Auth is currently mostly UI/state-check scaffolding, not a production-ready flow.
- Route protection is absent.
- API client and environment config are absent despite `dio` being installed.
- Shared UI is absent, increasing duplication risk once feature screens begin.
- Firebase config source-of-truth and app id consistency should be reviewed before production work accelerates.

Recommended focus:

The project is ready to begin backend vertical slice foundation work, but not yet ready for deep event feature UI implementation. Start with backend structure, migration convention, auth contract, and Flutter API/client groundwork. Then implement event read/list CRUD before registration and QR check-in.

## Final Output Checklist

### 1. Files Reviewed

Key files and areas reviewed:

- `README.md`
- `apps/event_app/README.md`
- `apps/event_app/pubspec.yaml`
- `apps/event_app/pubspec.lock`
- `apps/event_app/analysis_options.yaml`
- `apps/event_app/firebase.json`
- `apps/event_app/lib/main.dart`
- `apps/event_app/lib/firebase_options.dart`
- `apps/event_app/lib/core/app_state.dart`
- `apps/event_app/lib/core/logger/app_logger.dart`
- `apps/event_app/lib/routes/app_router.dart`
- `apps/event_app/lib/routes/app_routes.dart`
- `apps/event_app/lib/routes/route_guards.dart`
- `apps/event_app/lib/theme/app_colors.dart`
- `apps/event_app/lib/theme/app_text_styles.dart`
- `apps/event_app/lib/theme/app_theme.dart`
- `apps/event_app/lib/theme/theme_provider.dart`
- `apps/event_app/lib/features/auth/presentation/screens/splash_screen.dart`
- `apps/event_app/lib/features/auth/presentation/screens/login_screen.dart`
- `apps/event_app/lib/features/auth/presentation/screens/auth_wrapper_screen.dart`
- `apps/event_app/lib/features/auth/services/firebase_auth_service.dart`
- `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart`
- `apps/event_app/lib/features/foundation/presentation/foundation_ready_screen.dart`
- `apps/event_app/lib/features/home/presentation/home_placeholder_screen.dart`
- `apps/event_app/test/widget_test.dart`
- `apps/event_app/android/app/build.gradle.kts`
- `apps/event_app/android/app/google-services.json`
- `apps/event_app/ios/Runner/GoogleService-Info.plist`
- `apps/event_app/macos/Runner/GoogleService-Info.plist`
- `firebase/android/google-services.json`
- `firebase/ios/GoogleService-Info.plist`
- `docs/` planning and notes documents by filename/headings

### 2. Commands Executed

Commands executed:

- `git status --short`
- `rg --files`
- `find . -maxdepth 3 -type d | sort`
- `find . -maxdepth 4 ...` for config/script/backend/database discovery
- `find apps/event_app/lib -maxdepth 5 -type f | sort`
- `find firebase -maxdepth 4 -type f | sort`
- `sed -n ...` on key Flutter, Firebase, routing, theme, auth, test, and docs files
- `diff -q` between root Firebase files and app platform Firebase files
- `rg -n ...` for TODO/auth/API/config references
- `grep` / `awk` for dependency versions and doc headings
- `tree -a -L 3 -I '.git|.dart_tool|build|.idea|Pods|Flutter'`
- `tree -a apps/event_app/lib -I '.DS_Store'`
- `flutter analyze`
- `flutter test`

### 3. Summary

The Flutter foundation is healthy and passes validation, but the project is still at scaffold stage. Firebase initializes, Hive initializes, routing works at a basic level, diagnostics exist, and theme state is managed with Riverpod. Auth UI exists, but sign-in is not functional. Backend, database, migrations, CI/CD, shared UI, API client, and production auth/session pieces are not yet implemented.

### 4. Blockers

- Backend structure is absent.
- Database migration structure is absent.
- Auth contract with backend is undecided/unimplemented.
- Route protection is absent.
- API client/environment config is absent.
- Shared UI component layer is absent.
- Firebase config ownership and app id consistency need review.

### 5. Readiness Recommendation

Proceed with backend vertical slice foundation, not full product feature buildout. The safest next move is to establish backend skeleton, database migration convention, auth/session contract, and Flutter API infrastructure. Event CRUD can follow immediately after that. Registration should follow event CRUD and identity resolution. QR check-in should wait until registration, permissions, and audit behavior are stable.
