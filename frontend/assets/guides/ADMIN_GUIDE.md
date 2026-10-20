<!-- Public file: served by the events site and read by NITiKA to answer "how do I…" questions.
     Keep it to what users see on screen. No personal emails, people's names, commit ids or
     internal setup (the API and Ops guides never go here). -->

# NITKSAA Events — Admin guide

**For:** organisers and door volunteers. **App:** events.nitkalumni.in. **Updated:** 20 Oct 2026.
Words in **bold** are what you see on screen.

---

## 1. Getting to Admin

- Sign in at events.nitkalumni.in. If you have admin rights, a **shield icon** shows at the top right. Tap it to open Admin.
- A gold number on the shield = items that need attention (§7).
- No shield: you have no admin rights yet. Ask an overall admin to add you (§3). Opening `/admin` without rights shows **Not an admin**.

**Tabs:** Actions, Dashboard, Events, Registrations, Check-in, Payments, Audit, Roles.

| Who you are | Tabs you see |
|---|---|
| Overall admin | All eight |
| Admin of an event | All except Roles; only your own events |
| Can create events, admin of none yet | All except Payments and Roles |
| Finance only | Payments |

- **On a phone:** Actions, Events, Registrations and Check-in are in the row; the rest are under **More ▾**. In Events, **Create event** is the gold **+** next to the search box (**Import** is on computers only); the count of events is in the **All** button. The date buttons are one row: **Pick dates** opens the slider and From – To. The links at the bottom slide away while you scroll down a list (not on Check-in).
- **Where Admin opens:** **Actions**. On an event day (one of your events is on, or starts within 3 hours) it goes straight to **Check-in** for that event.

---

## 2. Set up an event

Two ways, never mixed:

- **Create event:** you type everything in the app. Best for simple events (breakfasts, meetups). Three steps: **create** the essentials, **edit** to add extras, **publish** (below).
- **Import:** everything comes from a Google Sheet: the event, speakers, agenda and sponsors. Best for big events, or if you prefer a sheet. See **Import from a Google Sheet** below.

Saving never publishes: nobody sees the event until you press Publish.

### Step 1: Create

Admin › **Events** › **Create event** (also on the public Events page).

1. **Event Title** (required).
2. **Description (optional)**. If empty, the event page hides "About the Event". New lines show as typed. You can also use `**bold**`, `## Heading`, `- list item` and `[link text](https://…)`; save the draft and open its page to see how it looks.
3. **When:** Start Date and Time, End Date and Time; or switch on **Full Day Event** for dates only. Moving the start moves the end. Times are India time; **Change** picks another timezone.
4. **Where:** type in **Search Location** and pick a suggestion (or **Use as location**). Online: switch on **Online event** and paste the **Meeting URL** (only organisers and registered people see it).
5. **Capacity:** the most people who can attend, **guests included**.
6. **Free Event** is on by default. For a paid event, switch it off and press **Add Fee**:
   - **Fee Name** (e.g. Registration), **Fee Type** (usually Participation), **Fee Amount (₹)**.
   - The ticket price is the **Total** of the rows. One price = one row.

Press **Save draft**. If something is missing, a message lists it and the form scrolls to the first problem.

### Step 2: Edit (add only what this event needs)

**⋯** on the event › **Edit**, or **Edit event** on its page. Right under the essentials, "Add more only if this event needs it:" shows a **+** button for each part the event doesn't have yet; the parts it has come below, each with **Remove**.

| Button | Sets | If you don't add it |
|---|---|---|
| + Images | Thumbnail URL (cards), Banner URL (event page, about 1600 × 400) | A plain card with the date |
| + Branding | Logo URL (for light backgrounds), Logo URL for dark backgrounds (e.g. a white logo) | No logo |
| + Registration dates | Registration Opens / Registration Closes | Opens when published, closes when the event starts |
| + Guests | Guests per registration: None, 1–4 | Nobody can bring guests |
| + Speakers | Name, title, organisation, photo link, and email and phone (organisers only, never on the event page). Enough on its own for an event with a guest speaker and no agenda | No speakers shown |
| + Agenda | Sessions: title, start, end and speakers (optional, one or more) | No agenda shown |
| + Sponsors & partners | Name, type, logo URL, website | No sponsors shown |

- Images must already be online somewhere; paste their links (no upload yet).
- **Sessions:** a session can have no speaker (e.g. lunch) or several. In a session, **Add speaker** lists the event's speakers; **New speaker…** adds someone new, who then also appears under Speakers. Sessions may overlap (parallel sessions). A new session starts at the event's start, or where the last one ends.
- **Branding:** with a logo set, the event card shows the logo (the white one in dark mode) instead of the banner, and the event page shows the banner whole, never cropped. Pages keep the site's colours. NITKonnect's own files: `/brand/nitkonnect/logo.png`, `/brand/nitkonnect/logo_white.png` and `/brand/nitkonnect/banner.png`.
- A part you add with **+** appears and scrolls into view.
- Long lists (more than 5 speakers, sessions or sponsors) show as one line, e.g. "83 speakers"; **Show** opens the list, **Hide** folds it again.
- **Remove** on a group asks first if it holds anything, and clears it when you **Save**.
- Closing with unsaved changes asks **Discard your changes?** — **Keep editing** goes back.

**The event's link.** Under the title, Edit shows the event's link, e.g. `events.nitkalumni.in/e/bangalore-breakfast-oct-2026`, with a copy button.
- It's made from the title when you first save. **Change** sets your own: letters, numbers and hyphens (spaces become hyphens as you type).
- **Set it before you publish.** Once the event has been published, the link can't change, so links already shared keep working.
- A link another event already uses is refused: "This link is already used by another event." For a repeat event, add the month (e.g. `…-oct-2026`).
- Give practice or demo events their own link (e.g. `demo-…`), so the real event gets the clean one.

### Step 3: Publish

**⋯** › **Publish**. If something is missing: "Can't publish yet. Please fill in: …". Fix it with Edit, then publish again.

### Import from a Google Sheet

Admin › **Events** (or the Events page) › **Import**, on a computer. The window shows three steps:

1. **Make a copy of a template:** **Blank**, **Breakfast example** or **NITKonnect example**. Each opens Google's "Make a copy". Fill in your copy, not the template.
2. **Share it with the app, as Viewer:** press **Copy** for the email shown, then in the sheet: **Share** › paste it › **Viewer** › untick "Notify people".
3. **Paste the sheet's link** and press **Read the sheet**.

The **Create event from a sheet** form opens, filled in from the sheet. Check it and press **Save draft**: the event is made with its speakers, agenda and sponsors, and stays linked to the sheet.

**The sheet's tabs** (keep their names and headers; hover over a header to see what goes in it):
- **Event** (required): title, date, times, venue, capacity, price, guests per registration. Under **More** (the **+** on the left): an end date for an event over several days, a map link, a meeting link (an online event leaves Venue blank), registration dates, description, image and logo links, and the gap between sessions.
- **Sessions:** start, end, title, speakers; more columns for big events (moderator, type, hall, pillar, subtitle, presented by) under the **+** above the columns. Leave **Date** blank for a one-day event. A blank **End** runs to the next session. Dates copied from a template move to the event's own date.
- **Speakers:** name, title, company, email; more under the **+** (role, phone, LinkedIn, photo link, batch, bio). For NITK alumni, the email fills in their batch, LinkedIn and phone where the sheet leaves them blank. Email and phone are for organisers only.
- **Sponsors:** name, tier (sponsors and partners in one list), logo link, website, label.

**An imported event is changed only in its sheet.** Its **Edit event** shows everything read-only, with a card at the top:
- **Open:** opens the sheet. **Refresh:** reads it again. If the sheet changes the event itself (title, dates, place, seats…), you see **Apply the changes from your sheet?** with each change; nothing is saved until **Apply**. Speakers, the agenda and sponsors just refresh.
- **The price doesn't change once the event is published**, even if the sheet says otherwise; Refresh says so. Capacity can't go below the people already registered.
- If the sheet has a mistake, Refresh lists it by tab and row (e.g. "Sessions, row 14: no start time") and changes nothing. Fix the sheet and press Refresh again.
- The event's link can still be set in Edit until you publish.
- **Unlink and edit here instead:** the event keeps everything it has and from then on is edited in the app. **This can't be undone:** it can't be linked to a sheet again. Use it, for example, for an urgent fix on the day when nobody can edit the sheet.

### Later: the ⋯ menu

| Item | What happens |
|---|---|
| Edit | Change anything. A new price applies to new payments only. For an imported event, shows it read-only with **Refresh** |
| Registrations | Opens this event's registrations |
| Close registration / Reopen registration | Stops or restarts new registrations; existing ones stay |
| Unpublish | Back to draft, hidden from Events; registrations kept |
| Admins | Who manages this event (§3) |
| Cancel event | Cancelled for everyone; can't be undone. **Refunds are not sent automatically** (§6) |
| Delete | Drafts with no registrations only; gone for good |

### Tips

- Allowing guests: **+ Guests** › **Guests per registration** (up to 4).
- Leave **Registration Closes** empty, so registration closes when the event starts. Never set it after the start.
- Capacity counts every person, guests included.
- **Sharing:** a published event's page has **Share** on phones (WhatsApp and others) and **Copy link** on computers. Drafts don't, because their link doesn't open for anyone else yet.
- **Big events:** when two or more sessions start at the same time, the event page groups the agenda by time (side by side on a computer, swipe on a phone) and shows each session's hall when one is set. A session with no speaker named Tea, Lunch, Break or Dinner shows as a band. When an event's sessions have them, a session also shows its type and pillar (with pillar buttons to filter the agenda) and "Presented by" a sponsor, and a sponsor can show a label such as "Co-presenter" instead of its tier. These come from an imported sheet; the form doesn't set them. Each session lists the speakers linked to it (first 3, then **+N more**; hidden speakers are left out); a session with no linked speakers shows its speaker line as before. More than 12 speakers get **Search speakers** and **Show all**; sponsors of more than one tier are grouped by tier. Small events look as before.

---

## 3. Event admins and door volunteers

An event admin can edit the event, see its registrations and payments, check people in, and add or remove other admins.

**Add someone:**
1. They **sign in once** at events.nitkalumni.in first (otherwise: "No one with that email has signed in to the events app yet.").
2. Event's **⋯** › **Admins** › type their sign-in email in **Add an admin by email** › **Add** › **Done**.
3. They now see the shield icon (a page refresh may be needed).

- Remove: the remove icon next to their name.
- Event admins are added **only** through Admins. The **Roles** tab (overall admins only) is for **Overall admin**, **Can create events** and **Finance**.

**Door volunteers:**
- Make each one an event admin of the event, a few days before.
- **The day before:** each signs in on the phone they'll use at the door, in **Chrome** (Android) or **Safari** (iPhone). On the morning, they open the site and check they're still signed in.
- **Email sign-in link on a phone:** open the link in Chrome or Safari (long-press › Open in Chrome, or ⋮ › Open in browser), **not** inside the email app. Otherwise you may be asked for your email again and land on Events.
- Gmail users: use **Continue with Google** instead.

---

## 4. Check-in at the door

Every person, guest included, has their own QR on their phone (no emails, so no printouts).

### Scan

1. Admin › **Check-in**. On an event day it opens on that event; otherwise tap the event card › **Change ▾** to pick it.
2. Tap **Scan**. Allow the camera when asked.
3. Point at each pass. Each valid pass checks in **at once**; no button to press.
4. **Done** goes back to the list.

| Colour | You see | Do |
|---|---|---|
| Green | **Checked in** | Let them in. **Undo** if it was a mistake |
| Yellow | **Already checked in** | Their pass was used before. Check the name; ask if someone else used it |
| Red | **Not registered** | Cancelled or never paid. Send to the help desk |
| Red | **Pass for another event** / **Not a pass for this event** | Wrong QR. Ask for the right pass, or find them in the list |
| Red | **Not an entry pass** | Not one of our QR codes |

- A guest shows as "Ravi Kumar, guest of Meera Nair".
- The same pass is ignored for 4 seconds, so it isn't read twice.

### No QR? Use the list

- Type in **Find a person: name, email, phone or number** › **Check in** on their row.
- Pills: **Not checked in** (default), **Checked in**, **All**. The count line shows "X of Y checked in".
- Mistake: **Undo** on their row.

### If the scanner won't start

- "Camera access is blocked…": allow the camera for this site in the browser settings, then tap Scan again.
- Otherwise: use the **phone's own camera** (or Google Lens) on the pass. It opens the person's check-in page with a big **Check in** button.
- Or use the list.

People who aren't admins of the event see "This is an entry pass" when they open a QR. That's expected.

---

## 5. Registrations

Admin › **Registrations**.

- Pick the event (or **All events**). Pills: **Registered**, **Cancelled**, **Check-ins**.
- Search by name, email, phone or registration number. Guests show in **Guest of**.
- The card on top shows **Capacity**, **Registered**, **Seats left**, **Cancelled**, **Checked in**.
- **Export CSV** downloads exactly the rows on screen (filters and search apply).

Nothing on a row can be changed here. To cancel someone's registration, see §8.

---

## 6. Payments and refunds

**How refunds work:** when someone **unregisters** (or cancels a guest) from a paid event, the app refunds them automatically through Razorpay. Attendees see the status in the app. Unregistering is possible until the event starts.

Admin › **Payments** (overall admins, Finance, and the event's admins):

| Pill | Shows |
|---|---|
| Orders | Every payment. **Paid** (green), **Pending**; **Pending · stuck** = pending over 30 min. Tap a row for details |
| Refunds | Every refund: **Pending**, **Processing**, **Delayed**, **Refunded**, **Needs attention** |
| Paid events | Each paid event's price and what the attendee pays |

- **Delayed:** Razorpay couldn't take it for now (often a low balance). It retries automatically, or press **Retry now**.
- **Needs attention:** the refund failed and the person hasn't been paid back. Press **Retry now**; if it fails again, tell the NITKSAA Digital Platform Team.

**Cancelling a paid event does not refund anyone.** Before you press **Cancel event** on a paid event, talk to the NITKSAA Digital Platform Team.

---

## 7. Actions, Dashboard, Audit and NITiKA

**Actions** — check it daily. "All clear" means nothing to do.

| Needs action | What to do |
|---|---|
| Drafts not published | Publish, fix the date, or delete |
| Payments stuck | Open it; usually confirms itself. Tell the NITKSAA Digital Platform Team if it stays |
| Refunds need attention | **Retry now** in Payments › Refunds (§6) |

For information: **Registration closing soon**, **Nearly full** (90%+ of seats), **Refunds delayed**.

**Dashboard:** registrations, cancellations and money collected (live payments only), per event or all.

**Audit:** who did what and when (event changes, registrations, payments, roles). Tap a row for details.

**NITiKA** (the chat icon at the top): ask in plain words, e.g. "How many people have registered for the Pune meet?" On Registrations and Check-in, "this event" means the event you've picked. Check important numbers against the Registrations tab.

---

## 8. When something goes wrong

| Problem | What to do |
|---|---|
| Someone can't find the Register button | Registration may be closed, full or not open yet; the event page says which. Check the event's dates and capacity |
| "Event is at full capacity" | Raise **Capacity** in Edit, if there's room |
| Someone paid but isn't registered | Their page shows "Payment received, confirming…"; it usually clears in a minute. If not, check Payments › Orders and tell the NITKSAA Digital Platform Team |
| Someone's payment failed or they closed the window | They tap **Complete payment** on the event page |
| Someone wants to cancel | They tap **Unregister** on the event's card (Events or My Events). Admins can't cancel for them |
| Someone wants to drop one guest | They tap the **✕** next to the guest on the event page |
| Someone wants to add a guest after registering | Not possible: they unregister and register again with the guest |
| Unregister after the start | Not possible, by design |
| A volunteer has no Check-in tab | They aren't an admin of this event yet (§3), or need to refresh the page |
| A volunteer is asked for their email again | They opened the sign-in link inside the email app. Open it in Chrome or Safari (§3) |
| "Can't publish yet…" | Edit and fill in the fields it lists |
| Anything else | Tell the NITKSAA Digital Platform Team. Attendees can use **Feedback** at the bottom of every page |
