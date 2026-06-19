# Developer Diagnostics JSON I/O Review

**Version:** 1.0  
**Date:** 2026-06-19  
**Status:** Review Complete — no implementation in this phase  
**Recommendation:** See §Gaps Found and §Priority

---

## Summary

Reviewed all Developer Diagnostics screens for JSON input/output visibility.
Source file:
`apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart`

**Finding:** Response JSON is shown for most live API sections via a collapsible
`_jsonBlock()` widget. Request payload is never shown. There is no copy button for
JSON blocks. HTTP status codes are not displayed. Token masking is partial
(Firebase token has a preview; backend JWT is not shown).

---

## Files Reviewed

| File | Purpose |
|---|---|
| `apps/event_app/lib/features/developer/presentation/developer_diagnostics_screen.dart` | Full diagnostics screen — primary source |
| `docs/reviews/week3_ux_showcase_verification_report.md` | Section inventory and state variables |
| `docs/api/swagger_testing_guide.md` | API path and auth reference |
| `docs/validation/backend_week3_manual_verification_guide_v2.md` | Expected request/response shapes |

---

## Current JSON Visibility Status

### `_jsonBlock()` Widget — How Response JSON Is Currently Shown

```dart
Widget _jsonBlock(BuildContext context, String title, Object? value) {
  if (value == null) return const SizedBox.shrink();
  return ExpansionTile(
    title: Text(title),
    subtitle: const Text('Show Raw Response'),
    children: [
      SelectableText(const JsonEncoder.withIndent('  ').convert(value), ...)
    ],
  );
}
```

**Behaviour:**
- Collapsible `ExpansionTile` — hidden by default, expands on tap
- Title shows the API label (e.g., "GET /api/v1/alumni/me response")
- Subtitle always reads "Show Raw Response"
- Content is pretty-printed JSON via `JsonEncoder.withIndent('  ')`
- Text is `SelectableText` — user can select/copy manually, no copy button
- Only rendered when `value != null` (hidden until a fetch completes)
- Shows response JSON only — no request payload visible

### `BackendApiDetailsCard` Widget — Static API Metadata

Shown at the top of every diagnostic detail screen:

| Field | Shown | Type |
|---|---|---|
| Feature name | Yes | Static string |
| API path | Yes | `method PATH` format |
| HTTP Method | Yes | Static string |
| Auth Required | Yes | Static string description |
| Purpose | Yes | Static string |
| Implementation status | Yes | Static string |
| Sample Response | Yes (if set) | Static string (not live) |
| UI Guidance | Yes (if set) | Static string |

This card provides method/path/auth context but the sample response is a static string,
not the live response from the last run.

---

## Diagnostic Flow Matrix

| Diagnostic Flow | Screen | API Path Shown | Method Shown | Request Payload | Response JSON | HTTP Status Code | Copy Button | Error JSON |
|---|---|---|---|---|---|---|---|---|
| Network Test / Health Check | `_NetworkDetail` | In button label | In button label | No | Yes (`_jsonBlock`) | No | No | Snackbar only |
| Firebase Token Test | `_AuthDiagnosticDetail` | In `BackendApiDetailsCard` | In `BackendApiDetailsCard` | No | No (token preview only) | No | Yes (token copy) | Snackbar only |
| Backend Auth Test | `_AuthDiagnosticDetail` | In `BackendApiDetailsCard` | In `BackendApiDetailsCard` | No | Yes (`_jsonBlock` — "Backend login response") | No | No | Snackbar only |
| /auth/me Test | `_AuthDiagnosticDetail` | In `BackendApiDetailsCard` | In `BackendApiDetailsCard` | No | Yes (`_jsonBlock` — "/auth/me response") | No | No | Snackbar only |
| Database Tables / Event Users | `_AuthDiagnosticDetail` | In `BackendApiDetailsCard` | In `BackendApiDetailsCard` | No | Shown as formatted table rows (not raw JSON) | No | No | Snackbar only |
| §0 Run All Diagnostics | `_RegistrationDiagnosticDetail` | In `BackendApiDetailsCard` | In `BackendApiDetailsCard` | No | Yes (`_jsonBlock` — "Raw diagnostic response") | No | No | Per-check error text |
| §1 Alumni Autofill | `_RegistrationDiagnosticDetail` | In button label | In button label | No | Yes (`_jsonBlock` — "GET /alumni/me response") | No | No | `_errorChip` |
| §2 Eligibility | `_RegistrationDiagnosticDetail` | In button label | In button label | No | Yes (`_jsonBlock` — "GET /registration-eligibility response") | No | No | `_errorChip` |
| §3 Registration Action | `_RegistrationDiagnosticDetail` | In button label | In button label | No | Yes (`_jsonBlock` — "POST /register response") | No | No | `_errorChip` |
| §4 Confirmation Preview | `_RegistrationDiagnosticDetail` | None | None | No | No (uses §3 result, no separate block) | No | No | None |
| §5 My Registration | `_RegistrationDiagnosticDetail` | In button label | In button label | No | Yes (`_jsonBlock` — "GET /my-registration response") | No | No | `_errorChip` |
| §6 My Registrations List | `_RegistrationDiagnosticDetail` | In button label | In button label | No | Yes (`_jsonBlock` — "GET /my/registrations response") | No | No | `_errorChip` |
| §7 Negative State Gallery | `_RegistrationDiagnosticDetail` | None | None | No | No (static cards only) | No | No | None |
| §8a Join Link Matrix | `_RegistrationDiagnosticDetail` | None | None | No | No (static table only) | No | No | None |
| §8b Public API Leak Validation | `_RegistrationDiagnosticDetail` | In button label | In button label | No | Yes (`_jsonBlock` — "Public event payload") | No | No | `_errorChip` |
| §9 Audit Trail | `_RegistrationDiagnosticDetail` | In button label | In button label | No | No (formatted row cards, no `_jsonBlock`) | No | No | `_errorChip` |
| §10 Email Demo | `_RegistrationDiagnosticDetail` | None | None | No | No (formatted status card, no `_jsonBlock`) | No | No | None |
| §11 Snapshot Demo | `_RegistrationDiagnosticDetail` | None | None | No | No (side-by-side comparison, no `_jsonBlock`) | No | No | None |
| §12 Database Rules | `_RegistrationDiagnosticDetail` | None | None | No | No (static cards only) | No | No | None |

---

## Gaps Found

### Gap 1 — Request payload not shown anywhere

**Affected sections:** All sections that make POST requests (§3 Registration Action) and GET requests with significant query parameters.

**Current state:** The button label shows the HTTP method and endpoint path (e.g., "Register (Dev) → POST /events/{id}/register") but the outgoing request body (`{"attendee_note": "..."}`) is never displayed.

**Impact:** When a test fails, the tester cannot see what was sent to the backend. Debugging requires adding debug logs or checking the backend request log.

---

### Gap 2 — No copy button on `_jsonBlock` response JSON

**Affected sections:** §0–§3, §5–§6, §8b, Network Test, Backend Auth, /auth/me.

**Current state:** `_jsonBlock` uses `SelectableText` — the user can manually select and copy text, but there is no one-tap copy button.

**Impact:** Copying a full response JSON for use in bug reports or Swagger testing requires manually selecting all the text, which is cumbersome on mobile or in a small window.

---

### Gap 3 — HTTP status code not displayed

**Affected sections:** All sections.

**Current state:** When a Dio error occurs, `error.response?.statusCode` is extracted but only surfaced via snackbar message or `_errorChip` text (e.g., "Error: 409: already_registered"). The successful HTTP status code (200, 201) is never shown.

**Impact:** Testers cannot confirm they got 201 (not 200) for POST /register without looking at the backend log.

---

### Gap 4 — §9 Audit Trail has no raw JSON block

**Affected section:** §9.

**Current state:** The audit trail shows formatted row cards (up to 8 rows) displaying `event_type`, `entity_type`, `entity_id`, `created_at`. There is no `_jsonBlock` showing the full raw API response.

**Impact:** Tester cannot see the full JSON response from `GET /dev/diagnostics/db/event_audit_log` — field names, count, and structure are hidden behind the formatted card UI.

**Contrast:** §8b Public Leak Validation does show the full `_jsonBlock` alongside its formatted PASS/FAIL card. §9 should do the same.

---

### Gap 5 — Firebase token masking inconsistency

**Current state:** In Firebase Token Test, a `_tokenPreview` shows a truncated version of the Firebase `idToken`. The backend `access_token` is stored in state (`_backendAccessToken`) but is never displayed in the UI — it can only be copied from the report export.

**Impact:** Testers using Option A (Flutter → Swagger) cannot easily copy the backend JWT from the screen.

---

### Gap 6 — §4, §10, §11 derive data but do not show the source JSON

**Affected sections:** §4 Confirmation Preview, §10 Email Demo, §11 Snapshot Demo.

**Current state:** These sections display formatted cards derived from §3's `_registerResult` and §1's `_autofillResult`. The underlying source JSON is not shown in these sections — it's only visible by scrolling up to §3 and §1.

**Impact:** A tester looking only at §10 Email Demo cannot see that `confirmation_email_status: "sent"` came from the POST /register response without scrolling to §3.

---

## Recommended UI Changes

Listed in priority order (highest first):

| Priority | Change | Section | Effort |
|---|---|---|---|
| P1 | Add `_jsonBlock` for raw response to §9 Audit Trail | §9 | Low — add `_jsonBlock(context, 'Raw audit log response', _auditLogResult)` after the row cards |
| P1 | Add copy button to `_jsonBlock` | All `_jsonBlock` usages | Medium — replace `SelectableText` with a Row containing text + `IconButton(Icons.copy)` + `Clipboard.setData` |
| P2 | Show HTTP status code in `_jsonBlock` title or subtitle | All live sections | Low — extract and store `statusCode` from Dio response, pass to `_jsonBlock` title |
| P2 | Show request payload in a separate `_requestBlock` before the response block | §3, §8b | Medium — add a non-collapsible card above `_jsonBlock` showing outgoing JSON |
| P3 | Display backend `access_token` preview (masked) in Backend Auth Test | Auth detail | Low — show first 20 chars + "..." similar to `_tokenPreview` for Firebase token |
| P3 | Add source JSON note to §4, §10, §11 | §4, §10, §11 | Low — add a chip/note "Source: §3 POST /register response" with a tap-to-scroll anchor |

---

## Priority

| Priority | Changes | Justification |
|---|---|---|
| P1 (high) | §9 raw JSON block + copy button | §9 missing JSON is a functional gap; copy button is the most common tester request |
| P2 (medium) | HTTP status code + request payload | Improves debugging significantly at low cost |
| P3 (low) | Backend JWT preview + §4/§10/§11 source notes | Nice-to-have for developer clarity |

---

## Implementation Risk

| Change | Risk | Notes |
|---|---|---|
| §9 `_jsonBlock` | Very low | One-line addition: `_jsonBlock(context, 'Raw audit log response', _auditLogResult)` after the row cards |
| Copy button on `_jsonBlock` | Low | `_jsonBlock` is a top-level function — one change propagates to all usages |
| HTTP status code in `_jsonBlock` | Low | Requires changing `_jsonBlock` signature to accept optional `statusCode` param |
| Request payload block | Medium | Requires storing outgoing payloads in state variables before each fetch |
| Backend JWT preview | Very low | Already in state as `_backendAccessToken` — just display it masked |
| §4/§10/§11 source notes | Very low | Static text addition |

---

## Suggested Phase 2B Prompt

When ready to implement Phase 2B, use the following scope:

**Priority 1 changes only (P1):**

1. Add `_jsonBlock(context, 'Raw audit log response', _auditLogResult)` at the bottom of `_auditTrailCard()` in `_RegistrationDiagnosticDetailState`, after the info banner (line ~2265).

2. Add a copy button to `_jsonBlock()`:
   - Change signature to `Widget _jsonBlock(BuildContext context, String title, Object? value)`
   - Add an `IconButton(icon: Icon(Icons.copy_outlined), onPressed: () => Clipboard.setData(ClipboardData(text: jsonEncode(value))))` as a trailing action in the `ExpansionTile`
   - Show a brief confirmation via `ScaffoldMessenger.of(context).showSnackBar`

**Constraints:**
- No new state variables needed for P1
- No changes to API calls or fetch methods
- No changes to backend, Flutter production screens, or React Admin
- All changes inside `kDebugMode`-gated Developer Diagnostics

---

## PASS / FAIL Recommendation

**Current state: PARTIAL PASS**

The Developer Diagnostics screen provides good response JSON visibility for the main
API flows (§0–§3, §5–§6, §8b, Auth, Network). The main gaps are:

- §9 Audit Trail is missing a raw JSON block (the only live-data section without one)
- No copy button (ergonomics issue, not a correctness issue)
- No request payload display (debugging gap)
- HTTP status codes not visible (minor gap)

These are ergonomics improvements, not functional regressions. The screen is usable
for development and demo purposes in its current state.

**Recommendation:** Implement Phase 2B P1 changes (§9 JSON block + copy button) in the
next available development slot. P2 and P3 can be batched with other Week 4 improvements.
