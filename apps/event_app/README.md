# event_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Local developer diagnostics

Developer Diagnostics is a debug-only route and is hidden from the public login
screen. To enable access for the local test account, run the app with
dart-defines:

```bash
flutter run \
  --dart-define=DEV_DIAGNOSTICS_EMAIL=UUsername2026@gmail.com \
  --dart-define=DEV_DIAGNOSTICS_PASSWORD=Password2026
```

The password define documents the local test credential used for Firebase
sign-in. The app gates diagnostics visibility by the authenticated backend
session email and does not expose diagnostics in release mode.

Optional:

```bash
flutter run --dart-define=DEV_TEST_EVENT_ID=1
```

`DEV_TEST_EVENT_ID` controls which event opens from the Developer Diagnostics
"Open Event Detail Test" action.
