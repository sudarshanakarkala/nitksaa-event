# Week 3 — Flutter ListTile Assertion Fix Report

**Date:** 2026-06-18  
**Branch:** main  
**Status:** FIXED — flutter analyze PASS, flutter test 16/16 PASS

---

## Summary

A Flutter debug assertion warning was firing at runtime:

```
"ListTile background color or ink splashes may be invisible.
 The ListTile is wrapped in a DecoratedBox that has a background color."
```

Root cause: `_SpeakersCard` in `event_detail_screen.dart` placed a `ListTile` inside `AppCard`,
which uses `Container(decoration: BoxDecoration(color: ...))`. A `Container` with a
`decoration.color` is backed by a `DecoratedBox`, and Flutter's debug assertion fires whenever a
`ListTile` is a descendant because the ink splash layer renders below the `DecoratedBox` paint,
making it invisible.

Fix: replaced the non-interactive `ListTile` with an equivalent `Padding + Row + Column` layout
that produces the same visual output without `ListTile`'s ink layer expectation.

---

## Files Reviewed

| File | ListTile found? | Assertion source? |
|---|---|---|
| `apps/event_app/lib/features/events/presentation/event_detail_screen.dart` | Yes — `_SpeakersCard`, line 332 | **YES** |
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Yes — `_DiagRow`, line 4962 | No — inside Flutter built-in `Card` which uses `Material` |
| `apps/event_app/lib/features/events/presentation/event_list_screen.dart` | None | No |

---

## Root Cause

### The widget tree that triggered the assertion

```
AppCard                          ← uses Container(decoration: BoxDecoration(color: ...))
  └─ Container
       └─ DecoratedBox           ← Flutter internals: Container with decoration → DecoratedBox
            └─ Padding
                 └─ Column
                      └─ ListTile  ← ASSERTION: ink splashes rendered below DecoratedBox
```

### Why `_DiagRow` in the diagnostics screen does NOT assert

```
Card                             ← Flutter built-in Card
  └─ Material (type: card)      ← Material correctly handles ink layer ordering
       └─ Column
            └─ ListTile          ← Safe: Material manages ink above its own background
```

Flutter's `Card` widget is backed by `Material`, which handles ink rendering correctly.
Only `DecoratedBox` (and `Container` with a `decoration.color`) conflict with `ListTile`.

### Why `AppCard` triggers the assertion

`AppCard` is defined in `apps/event_app/lib/core/widgets/app_card.dart`:

```dart
return Container(
  decoration: BoxDecoration(
    color: colorScheme.surface,  // ← this color causes the assertion
    border: Border.all(color: colorScheme.outlineVariant),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Padding(padding: padding, child: child),
);
```

When `BoxDecoration` includes a `color`, Flutter renders it via `DecoratedBox`. Any `ListTile`
descendant then fires the assertion because its ink splash layer has no `Material` above the
`DecoratedBox` to composite against.

---

## Fix Applied

**File:** `apps/event_app/lib/features/events/presentation/event_detail_screen.dart`  
**Location:** `_SpeakersCard.build()`, line 331-337

The `ListTile` was not interactive (no `onTap`, no selection state) — it was used purely for
the two-column avatar + text layout. Replacing it with an equivalent `Padding + Row + Column`
eliminates the assertion without any visual regression.

### Before

```dart
for (final speaker in speakers)
  ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
    title: Text(speaker.name),
    subtitle: speaker.title == null ? null : Text(speaker.title!),
  ),
```

### After

```dart
for (final speaker in speakers)
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const CircleAvatar(child: Icon(Icons.person_outline)),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                speaker.name,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              if (speaker.title != null)
                Text(
                  speaker.title!,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ),
      ],
    ),
  ),
```

### Style equivalence

| `ListTile` slot | `ListTile` Material 3 default | Replacement |
|---|---|---|
| `leading` | `CircleAvatar` vertically centered | `CircleAvatar` in `Row` with `CrossAxisAlignment.center` |
| `title` | `bodyLarge` | `Text(..., style: textTheme.bodyLarge)` |
| `subtitle` | `bodyMedium` + `onSurfaceVariant` | `Text(..., style: bodyMedium.copyWith(color: onSurfaceVariant))` |
| `contentPadding: EdgeInsets.zero` | No horizontal insets | `Row` has no extra horizontal padding |
| Vertical spacing | 56dp min height (non-dense) | `Padding(vertical: 8)` + natural column height |

### Why this approach (Option 2) over the alternatives

| Option | Approach | Verdict |
|---|---|---|
| Option 1 | Wrap `ListTile` in `Material(color: surface)` | Adds an unnecessary `Material` layer for a non-interactive widget |
| Option 2 | Replace with `Row + Column` | Correct — no ink needed for static display; eliminates the issue at the source |
| Option 3 | Remove background color from `AppCard` | Breaks `AppCard` visually across all screens that depend on its `surface` background |

Option 2 is the cleanest: the speakers list has no interaction, so `ListTile`'s ink splash
infrastructure is not needed. A `Row + Column` is the appropriate widget for a static list entry.

---

## `AppCard` — Note on Future Use

`AppCard` uses `Container(decoration: BoxDecoration(color: ...))`. Any future feature that places
an interactive `ListTile` inside `AppCard` will re-trigger this assertion. The fix is to either:

- Use `Material(color: colorScheme.surface)` instead of `Container(decoration: ...)` in `AppCard`
  to make the entire card `Material`-backed (best long-term fix if interactive tiles are needed)
- Or replace interactive `ListTile` instances with `InkWell + Row` combinations

`AppCard` itself was **not changed** in this fix because no other interactive widgets are currently
placed inside it. This note is recorded to inform Week 4 development.

---

## Validation

| Gate | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze --no-fatal-infos` | **PASS — No issues found (1.7s)** |
| Unit + widget tests | `flutter test` | **PASS — 16/16 passed** |

---

## PASS / FAIL Status

| Check | Status |
|---|---|
| Assertion source identified | PASS |
| All three files reviewed | PASS |
| Fix scoped to UI only — no backend changes | PASS |
| No API contract changes | PASS |
| No production registration UI changes | PASS |
| `flutter analyze` | PASS |
| `flutter test` | PASS — 16/16 |

**Overall: FIXED AND VERIFIED**

---

## Remaining Open Issues (Unchanged from Readiness Review)

This fix resolved OI-5 from `week3_readiness_review.md`. All other open issues are unchanged.

| # | Issue | Status |
|---|---|---|
| OI-1 | `RegisterRequest` — no `confirm_profile` field | Open — Week 4 decision |
| OI-2 | Eligibility response missing `event` / `my_registration` sub-objects | Open — Week 4 decision |
| OI-3 | `eligibility_status` values vs. v1 contract | Resolved in consistency review |
| OI-4 | `GET /alumni/me` flat response | Open — no change needed |
| OI-5 | `ListTile` / `DecoratedBox` assertion | **RESOLVED — this fix** |
| OI-6 | `ALUMNI_DB_URL` local setup not documented | Open — documentation task |
