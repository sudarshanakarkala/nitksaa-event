# UI patterns (events app)

**Owner:** Padmanand. Kept in the repo from 24 Oct 2026, so a PR that changes a pattern updates this guide in the same PR. **History:** started 13 Oct 2026. Forms were added 14 Oct (#37). Shared pieces, tables and filters were updated 14 Oct, main @ `a55da6c` (#44–#48). The admin tab frame and the date slider were added 14 Oct (#49); the look-back date line on #50; the Events page on the same controls on 15 Oct (#52).

This is the app's UI pattern guide: the patterns agreed so far, where the shared code lives, and the known gaps. It grows as new patterns are agreed. Anything new on screen should follow it, or update it first. The admin tab layout was designed separately (the admin layout design, built in #49; in the team's private docs).

**Behind the code in places:** the Filters rail (#103–#105) and a few later patterns aren't written up here yet; see Known gaps. Where this guide and the code disagree, the code wins until the guide is updated.

**Why:** on 13 Oct, testing turned up the same kinds of problem on several screens:
- notices that were easy to miss and all looked alike;
- tables that sorted differently;
- columns cut off.

Each was fixed by making **one shared piece** that every screen uses. This doc records those pieces so they stay consistent.

---

## Principles

1. **One shared component per pattern.** Screens use it; they don't build their own. A change to the pattern happens in one place.
2. **The website is the style reference** (`pwarrier108/nitksaa-website`): margins, containers, colours, toggles. Content lines up with the NITKSAA logo, and cards never shift when panels open.
3. **Web first.** The app is web-only: the iPhone, Android and desktop code was removed in #44. Layouts must work on a laptop, a tablet and a phone width.
4. **Say where people stand, where they'll look.** After an action, take people to the page that shows its result. For example, after a payment (successful, failed or cancelled), go back to the event page.
5. **Don't over-build.** Accept a small imperfection in a corner case rather than add server calls or complexity.

---

## Shared pieces: use these, don't build your own

| Need | Use | File |
|---|---|---|
| A pop-up message | `showNotice(context, message, kind:)` | `shared/widgets/notice.dart` |
| A coloured status pill | `StatusBadge(label, tone)`, `StatusBadge.event(…)`, `StatusBadge.paymentMode(…)` | `shared/widgets/status_badge.dart` |
| Empty, no matches, couldn't load, not allowed | `StateMessage(icon, title, body, action)` | `shared/widgets/state_message.dart` |
| Dates, times, money | `formatDate`, `formatShortDate`, `formatTime`, `formatTimeRange`, `formatDateTime`, `formatShortDateTime`, `formatMoney`, `monthNames` | `shared/format.dart` |
| A list page frame | `ListPage` (title, search, toggle, Filters, picker, pills, count, actions) | `shared/widgets/list_page.dart` |
| An admin tab | `AdminTabFrame` (search, toggle, picker, pills, count, one action, loading line), on `ListPage` | `features/admin/presentation/admin_tab_frame.dart` |
| The search box on a list page | `ListSearchField(controller, hint)` | `shared/widgets/list_search_field.dart` |
| The count line ("**24** events") | `ResultCount(count, one, many, extra:)` | `shared/widgets/filter_controls.dart` |
| Filters rail controls | `FilterLabel`, `FilterChipToggle`, `FilterChipSection`, `FilterSearchSelect`, `FilterYearRange`, `showFilterSheet` | `shared/widgets/filter_controls.dart` |
| A date range filter | `FilterDateRange` (presets, two-handle slider, From – To you can type; `inline: true` on the page, `leading:` for a control before it) and `parseFilterDate` | `shared/widgets/filter_controls.dart` |
| Quick-filter pills | `QuickFilterPill(label, active, onTap, count:)` | `shared/widgets/quick_filter_pill.dart` |
| Cards / Table switch | `SegmentToggle` (two-way: clicking the lit side flips it) | `shared/widgets/segment_toggle.dart` |
| A table of records | `AdminGridTable` with `GridColumn`s | `features/admin/presentation/grid_table.dart` (exported by `admin_widgets.dart`); columns in `features/admin/domain/registration_filters.dart` |
| Label → value rows in a details window | `AdminDetailRows` | `features/admin/presentation/admin_widgets.dart` |
| Event picker | `AdminEventPicker` (`width: AdminTabFrame.pickerWidth(context)` in an admin tab) | `features/admin/presentation/admin_widgets.dart` |
| Event cards | `EventCard`, `EventCardGrid` | `features/events/presentation/widgets/event_card.dart` |
| Unregister from a card | `confirmAndUnregister(context, ref, registration:, eventTitle:)` | `features/events/presentation/widgets/unregister_flow.dart` |
| Form fields | `LabeledField`, `FormFieldLabel`, `ReadOnlyValue`, `FormSectionLabel` | `shared/widgets/form_fields.dart` |
| Colours | `context.palette` | `theme/app_palette.dart` |
| Toggles | `SiteToggle` | `shared/widgets/site_toggle.dart` |

---

## Colours mean the same thing everywhere

| Colour | Meaning | Examples |
|---|---|---|
| **Green** (`palette.success`) | Done, all good | Saved, copied, payment successful, Refunded |
| **Yellow** (`palette.warning`) | Needs attention soon, not an error | Please fill in…, payment cancelled, payment not finished, Delayed |
| **Red** (`palette.error`) | Failed, someone must act | Payment could not be completed, Needs attention, couldn't save |
| **Blue** (`palette.info`) | Information | "Publishing…", coming soon |

The same state gets the same colour on every screen: in notices, status badges and banners. For example, a failed payment is red in the notice and in the event page message; an unfinished one is yellow in both.

---

## Notices (pop-up messages)

**Use `showNotice(context, message, kind: NoticeKind.…)`.** Never build a `SnackBar` directly.

- **Kinds:** `success`, `warning`, `error`, `info`. Each has its colour (above) and an icon.
- **How long it stays:**
  - **Errors stay until closed**, because they're the ones people must not miss.
  - Warnings stay 8 seconds; success and info stay 4.
  - Every notice has a × to close it. `persist:` overrides how long it stays.
- **Placement:** at the bottom. On wide screens it's a centred card (560px), not a strip across the page.
- **A new notice replaces the one showing.**
- `action:` adds a button, such as "View refund".
  - Pass the **page's** context, not a card's. A card can disappear after the action (for example with a filter on), and the button then has nothing to open from (#47).
- **Wording:** plain words, saying what happened and what to do. No technical codes. Server errors go through `apiErrorMessage(error, action: '…')`.

---

## Empty and error states

**Use `StateMessage`** for any page or panel with nothing to show.
- **Couldn't load:** `Icons.error_outline`, "Couldn't load …", the error in words, and a **Try again** button.
- **No matches:** `Icons.search_off`, "No … match", "Try another search or filter.", and **Clear filters** where it helps.
- **Nothing yet:** an icon for the thing, "No … yet", and the next step if there is one (e.g. **Browse events**).
- **Not allowed:** `Icons.lock_outline`, "Not available", and why.

Sentence case ("No events found", not "No Events Found").

---

## Forms

**Use the shared pieces in `lib/shared/widgets/form_fields.dart`**, which follow the website's `.field` look:

| Piece | What it is |
|---|---|
| `LabeledField(label:, child:, helper:, optional:)` | Label above any control; optional muted helper line below; `optional: true` adds "(optional)" |
| `FormFieldLabel(text)` | The small uppercase muted label on its own |
| `ReadOnlyValue(text)` | A value the person sees but can't change (subtle surface, border), e.g. the sign-in email |
| `FormSectionLabel(text)` | Eyebrow-style section heading inside a form ("YOUR DETAILS", later "GUESTS") |

- **Labels above fields**, never floating labels. Controls are plain `TextFormField`s in a `Form`, styled by the theme (`inputDecorationTheme`); no per-field colours.
- **Validation inline**, under the field, checked when the person presses the main button. Plain words: "Please enter your name.", "Please enter a phone number we can reach you on."
- **Server errors** go through `showNotice(…, kind: NoticeKind.error)` with `apiErrorMessage` (known codes have their own wording there).
- **Buttons:** Cancel (outlined) and the main action, right-aligned on wide screens; stacked full width on a phone, main action on top.
- **Personal details never go in the page address.** Pass them inside the app (e.g. the registration draft in the event's provider).
- **Used by:** the registration form (event page, `_RegistrationFormDialog`) and the Feedback page.

---

## List pages (the Events page, My Events, admin tabs)

All list pages use **`ListPage`**, in this order:
1. **Search** (`ListSearchField`).
2. **Cards/Table** switch, if the page has both.
3. The **Filters** icon, which opens the **filters rail on the left** (a bottom sheet on phones).
4. **Quick-filter pills**, after a dropdown such as the event picker (`picker:`).
5. The **count line** (`ResultCount`).
6. The page's **action button**.

Rules:
- The rail always has every filter; quick filters are shortcuts to filters that are also in the rail.
- With no search box or toggle, the Filters icon goes at the end of the pills row, never alone on a row.
- On phones, the picker gets its own full-width line above the pills.
- A page may add one full-width line under the pills (`belowPills:`), for a filter people use all the time. Admin → Events uses it for the date line.
- There are no refresh buttons.
- Content lines up with the logo. On the Events and My Events pages on desktop, the rail's strip on the left is kept free, so opening it covers nothing. On admin tabs the rail slides over the page instead (`reserveRail: false`), so every tab lines up with the "Admin" title.

**Admin tabs use `AdminTabFrame`** (the shared admin version of this frame: one main action, a loading line under the toolbar), with deliberate differences per tab (the admin layout design, #49).

### Dates in filters

**Use `FilterDateRange`**, never a calendar pop-up, for "between these dates":
- Presets first (e.g. Next 30 days), for the common windows in one tap.
- A slider with two handles over the dates that occur: it snaps to days on a laptop and to weeks on a phone; each handle shows its date while dragged.
- **From – To** boxes take typed dates, day first ("15 Nov", "15/11", "15 Nov 2026"); no year = the next one coming. They follow the slider; blank = no limit; × clears; a date it can't read turns the box red.
- **Looking forward** (the Events page and Admin → Events, `EventDateLine` in `features/events/presentation/widgets/event_list_controls.dart`): Date ↑/↓, then presets This week · This month · Next 90 days; a date without a year is the next one coming.
- **Looking back** (`lookBack: true`: Admin → Registrations, Payments, Audit): presets `FilterDateRange.lookBackPresets` (Today · Last 7 days · Last 30 days); a date without a year is the latest one; `FilterDateRange.contains(range, at)` tests a record.
- On the page (`inline: true`, the `belowPills:` line), not in the rail, and not counted on the Filters badge.
- Setting an event's own start and end keeps the existing date and time fields (event form).

### Filter chips

Chips light up for **what they show**:
- **Nothing lit = everything shown** (the default).
- **Click a chip: only that kind is shown**, and the chip lights up.
- Click a lit chip to take it off. When the last one goes off, everything shows again.

The Events page's Event Mode, Registration Status and Price chips were the other way round until #47 (clicking Physical showed virtual events). If a filter is stored as "included" flags, map them as the Events page does (`_includeChips`).

---

## Tables

**Use `AdminGridTable`** with `GridColumn`s, for every table of records. Since #48 it is the only table in the app: Registrations and check-ins, Payments (orders, refunds), Audit, Admin → Events, and the Events page Table view.

### What it does
- **Wide screens (600px and up):**
  - The table fills the page below the toolbar.
  - **The headings stay at the top** while the rows scroll.
  - **The first column (who / what) stays on the left** while the others scroll sideways (`frozenColumns`, default 1).
  - **Only the rows on screen are drawn**, so long lists are quick. It's built on `TableView` from the Flutter team's `two_dimensional_scrollables` package.
  - Visible scrollbars both ways, and the table can be dragged with the mouse.
  - **A fade on the right edge** while columns are hidden there, and a shadow beside the frozen column once you've scrolled sideways.
- **Phones:** the rows become **cards** with a **Sort by** menu. A tab can pass its own card (`card:`), as Registrations does; otherwise a card lists the columns.
- **`above:`** holds a summary or notes. They're fixed above the table on wide screens and scroll with the cards on phones. **`below:`** holds paging (Audit). **`empty:`** is shown instead when there are no rows (use `StateMessage`).

### Rules
- **Every column heading sorts.** Click to sort, click again to reverse. An **arrow shows the sorted column and direction**.
- **The table always starts sorted by a visible column**, so the arrow shows from the start. Usually it's the newest date first: Orders → Started, Refunds → Requested, Registrations → Registered, Admin → Events → Starts.
- **Column order:** who → what → how much → status → why → when → **ID last** → **actions in the last column**. For example:
  - **Registrations:** Name, Event, Batch, Branch, Email, Phone, Confirmation, Registered, No.
  - **Orders:** Name, Event, Amount, Status, Mode, Started, Paid, Order #.
  - **Refunds:** Name, Event, Amount, Status, Reason, Tries, Requested, Refund ID, Retry now.
- **Column widths:**
  - Columns size to their text, **measured over every row**, so sorting never resizes them. Long text is capped (about 240px, two lines).
  - Columns whose cells aren't plain text (badges, buttons, bars) set a width (`GridColumn(width:)`).
  - Keep headings short ("Confirmation", not "Confirmation email"): the heading sets the minimum width.
- **Fit a laptop screen.** Keep only what's needed to scan and act. Dates in tables are short ("13 Oct, 10:29 AM").
- **Everything else goes in a details window** (below), opened by **tapping the row** (`onRowTap`).
- **Status** is shown as a `StatusBadge`, using the colours above.

---

## Details window

For one record with more fields than a table row can show. Built today for refunds and orders (Payments) and audit entries, with the shared `AdminDetailRows`. It should become one shared `DetailsDialog` when the next screen needs one (see Known gaps).

- A list of label → value rows; empty values are left out.
- **References and IDs** (order #, refund ID, payment, gateway and bank references, email) each have a **copy button**, which shows a green "… copied" notice.
- **Full dates**, with the year.
- **Actions at the bottom**, such as Retry now, only when the person may use them, plus Close.

---

## References and IDs

- They have copy buttons wherever they're shown to someone who may need to quote them: attendees in the refund dialog, admins in details windows.
- In tables they come last, never first.

---

## Dates and money

All through **`shared/format.dart`**. Don't write a date or money format by hand, and don't type out month names.

| What | Format | Function |
|---|---|---|
| Full date and time | 13 Oct 2026, 10:29 AM | `formatDateTime` |
| Short, in tables | 13 Oct, 10:29 AM | `formatShortDateTime` |
| Date | 13 Oct 2026 | `formatDate` |
| Short date | 13 Oct | `formatShortDate` |
| Time / range | 10:29 AM / 10:29 AM – 12:00 PM | `formatTime`, `formatTimeRange` |
| Money | ₹1,800 · ₹1,23,456 · ₹123.45 (Indian grouping, paise only when there are any) | `formatMoney` (`wholeRupees: true` for Dashboard tiles) |

---

## Known gaps (to tidy when those screens are next touched)

- **Details windows** are built separately (refund, order, audit entry). Make one shared `DetailsDialog`; guests will need one for a party.
- **The sign-in screen** still uses the old widget set (`lib/widgets/material/`, with its own SnackBar). Move it to the shared pieces, then delete that folder.
- **The event page** has about 8 hand-built bordered boxes. A shared `SectionCard` can come with the guests work, which reworks that page.
- **The event form** (`manage_events_screen.dart`) was reorganised in #69–#88 but still has some of its own formats and dialogs. Bring it onto the shared pieces when it's next touched.
- **The developer diagnostics screen** (debug builds only) is left as it is until Sudarshana says whether it's still needed. It also keeps the `google_sign_in` package (and Google's sign-in script) in the app.
- **~35 `flutter analyze` infos** in older code (style only).
- **Not written up here yet** (added since 15 Oct): the Filters rail (`ListPage.filtersInRail`, `keepRailStrip`, `header` / `AdminHeaderScope`; every filter in the rail, closed on load, the strip kept free from 900px; #103–#105), the phone footer that folds while scrolling, `ListIconAction`, folded long lists, the big-event agenda, and the imported event's read-only view. Check the **List pages** section against #103–#105 before relying on it.

Done on 14 Oct and removed from this list:
- the Admin → Events table moved onto `AdminGridTable`;
- money and date formatting is one shared formatter;
- status badges are one shared badge;
- the fixed table header;
- the splash label is one constant;
- the admin tabs are on one layout, `AdminTabFrame` (#49).

---

## Checklist for a new screen or change

- [ ] Uses the shared pieces (table above), with nothing hand-built that already exists there.
- [ ] Messages go through `showNotice`, with the right kind and the page's context.
- [ ] Colours follow the meaning table.
- [ ] Empty and error states use `StateMessage`.
- [ ] Dates and money use `shared/format.dart`.
- [ ] Forms use `form_fields.dart`: labels above, inline validation, no personal details in the address.
- [ ] A list page uses `ListPage` in the order above. An admin tab uses `AdminTabFrame`.
- [ ] Filter chips light up for what they show (none lit = all).
- [ ] A table uses `AdminGridTable`:
  - every heading sorts, and it starts sorted on a visible column;
  - IDs come last, and actions are in the last column;
  - badge and button columns set a width;
  - it fits a laptop, with the rest in a details window.
- [ ] References have copy buttons.
- [ ] After an action, the person lands where they can see the result.
- [ ] Checked at phone width.
