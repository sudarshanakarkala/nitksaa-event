# Week 4 — Developer Diagnostics UI Fix Report

Date: 2026-06-24

## Scope

This document covers two fixes applied after Phase 2 delivery:

1. Flutter Developer Diagnostics screen — removed duplicate navigation tiles
2. Flutter Events screen — added explicit timeout and improved error visibility

---

## Fix 1: Duplicate Navigation Tiles Removed

### Problem

`_QuickActionsCard` in `developer_diagnostics_screen.dart` had three navigation tiles in its Navigate section:

| Tile | Callback | Destination |
|---|---|---|
| Events | `_openEvents()` | `context.go(AppRoutes.events)` |
| Event List | `_openEventListingTest()` | `context.go(AppRoutes.events)` ← duplicate |
| Event Detail | `_openEventDetailTest()` | `context.go(AppRoutes.eventDetail(1))` |

"Events" and "Event List" navigated to the same route. "Event Detail" navigated to a hardcoded event ID (`DEV_TEST_EVENT_ID`, default 1) which is unreliable in reviewer environments where that event may not exist.

### Fix

- Removed `_openEventListingTest()` and `_openEventDetailTest()` methods from `_DeveloperDiagnosticsScreenState`
- Removed `onOpenEventListingTest` and `onOpenEventDetailTest` parameters from `_QuickActionsCard`
- Replaced the three-tile `Row` with a single full-width `_navTile` labelled **"Open Events"**

### Result

The Navigate section now has exactly one action. The Quick Actions card contains:

- **Navigate:** Open Events
- **Run:** Public Events API Test, Run All Diagnostics
- **Utilities:** Export Report, Clear Cache

---

## Fix 2: Events Screen Loading Timeout and Error Visibility

### Problem

The Events screen could appear stuck on "Loading events" if the backend was unreachable or responded slowly. The 15-second Dio `receiveTimeout` was the only backstop — no application-level timeout was set, so any partial or delayed connection could spin indefinitely. Parse errors were silently swallowed with no developer-visible output.

### Fix Applied

**File:** `apps/event_app/lib/features/events/presentation/event_list_screen.dart`

1. **Explicit 10-second timeout** — wrapped `_eventService.listEvents(period)` with `.timeout(const Duration(seconds: 10))`. This fires a `TimeoutException` after 10 seconds regardless of Dio's own socket-level timeout.

2. **`debugPrint` on every error** — the catch block now logs `[EventList] load error ($period): $error\n$stackTrace` to the developer console. Only visible in debug builds via `debugPrint` (no-op in release). Reviewers can observe raw errors in the Flutter DevTools or `flutter run` terminal output.

3. **`TimeoutException` mapped to user message** — `_errorMessage()` now handles `TimeoutException` (from `dart:async`) and Dio timeout types explicitly, returning `'Request timed out. Check your connection and retry.'` instead of the generic fallback.

### Error UI Already Present

`AppErrorView` with a **Retry** button was already rendered on error. The fix ensures the error state is actually reached (10s timeout fires) and the error message is informative rather than generic.

### Timeout Sequence

```
_load(period) called
  ↓
_eventService.listEvents(period).timeout(10s)
  ↓
  If backend responds within 10s → success
  If 10s elapses → TimeoutException thrown
    → debugPrint logs raw error + stack trace (debug builds only)
    → AppErrorView shown: "Request timed out. Check your connection and retry."
    → Retry button calls _load(period) again
```

---

## Files Changed

| File | Change |
|---|---|
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Removed `_openEventListingTest`, `_openEventDetailTest` methods; removed `onOpenEventListingTest`, `onOpenEventDetailTest` from `_QuickActionsCard`; simplified Navigate section to single tile |
| `apps/event_app/lib/features/events/presentation/event_list_screen.dart` | Added `dart:async`, `flutter/foundation.dart` imports; added `.timeout(10s)` wrapper; added `debugPrint` in catch; updated `_errorMessage()` for timeout types |

---

## Verification Checklist

| Check | Method | Expected |
|---|---|---|
| Dev diagnostics opens | Navigate to dev diagnostics screen | No crash, Quick Actions visible |
| Navigate section has one tile | Visual inspection | "Open Events" tile only |
| Open Events navigates correctly | Tap "Open Events" | Goes to `/events` route |
| Run All Diagnostics works | Tap button | Spinner, then results |
| Export Report works | Tap button | Share sheet / file written |
| Clear Cache works | Tap button | Confirmation snackbar |
| Events load normally | Open Events with backend running | List of events shown |
| Events timeout error | Open Events with backend unreachable | Error state after ~10s, Retry visible |
| Retry works | Tap Retry after error | Retries the load |
| Error logged to console | Trigger error in debug build | `[EventList] load error` printed |

---

## What Was NOT Changed

Per session instructions — no new features implemented:

- No speakers / sponsors / analytics
- No meeting OAuth
- No QR check-in / rewards
- No paid events
- No full-day migration
