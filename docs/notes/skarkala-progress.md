# SKarkala Progress Notes

## Firebase Project

| Item | Value |
|---|---|
| Project name | NITKSAA Alumni Database |
| Project ID | `project-d22bed42-f302-4e23-8dc` |
| Project number | `246773894709` |
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

| Platform | Firebase App ID |
|---|---|
| Web | `1:246773894709:web:c4d4d005ec66432a33ab7c` |
| Android | `1:246773894709:android:45059af885cd128b33ab7c` |
| iOS | `1:246773894709:ios:f4ac285fc1d20c3f33ab7c` |
| macOS | `1:246773894709:ios:f4ac285fc1d20c3f33ab7c` |
| Windows | `1:246773894709:web:346987865cd7f33933ab7c` |

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
