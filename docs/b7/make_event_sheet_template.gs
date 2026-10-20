/**
 * NITKSAA event sheet template (B7).
 *
 * Builds the template that organisers copy (File → Make a copy), fill in and
 * share as Viewer with the events app. The events app reads the tabs by name
 * and the columns by their header, so keep the tab names and header words as
 * they are; the order of columns and extra columns don't matter.
 *
 * How to run (once, as nitksaa.infra@gmail.com):
 *   1. Open a blank Google Sheet (sheets.new).
 *   2. Extensions → Apps Script; replace the code with this file; Save.
 *   3. Choose makeTemplate in the toolbar and press Run; allow access
 *      (Google warns it's unverified: Advanced → Go to … (unsafe); it's your
 *      own script and only touches this sheet).
 *   4. Share → General access → Anyone with the link → Viewer, so organisers
 *      can make a copy. Send the link to Claude for the form.
 * Running it again rebuilds the tabs (anything typed in them is lost).
 */

const SERVICE_ACCOUNT = 'nitksaa-events-api@project-d22bed42-f302-4e23-8dc.iam.gserviceaccount.com';
const TEMPLATE_VERSION = '1';
const ROWS = 500; // rows prepared on each list tab (more can be added)

const COLOURS = {
  header: '#1f3b73',
  headerText: '#ffffff',
  required: '#fff4d6',
  help: '#5f6368',
  missing: '#f8d7da',
};

const SESSION_TYPES = ['Keynote', 'Talk', 'Panel', 'Fireside', 'Workshop', 'Showcase', 'Networking', 'Awards', 'Break'];
const ROLES = ['Speaker', 'Panelist', 'Moderator', 'Chief guest', 'Guest of honour', 'Host'];
const TIERS = [
  'Title sponsor', 'Gold sponsor', 'Silver sponsor', 'Bronze sponsor', 'Associate sponsor',
  'Community partner', 'Knowledge partner', 'Media partner', 'Venue partner',
  'Technology partner', 'Ecosystem partner', 'Hiring partner',
];

// Column kinds: text, date, time, link, email, list (with `values`), long (wrapped text).
const SESSIONS = [
  { name: 'Date', kind: 'date', width: 110, note: 'The day of the session, e.g. 15 Nov 2026. Leave blank for a one-day event (the event\'s date is used).' },
  { name: 'Start', kind: 'time', width: 90, required: true, note: 'Required. A time like 9:30 or 2:15 pm, in the event\'s timezone.' },
  { name: 'End', kind: 'time', width: 90, note: 'Optional. Blank: the session ends when the next one that day starts (less the gap on the Event tab); the last one ends with the event.' },
  { name: 'Title', kind: 'long', width: 260, required: true, note: 'Required. The session\'s name.' },
  { name: 'Speakers', kind: 'long', width: 220, note: 'Names, separated by commas, exactly as on the Speakers tab. Leave blank for a break or a session without speakers.' },
  { name: 'Moderator', kind: 'text', width: 160, note: 'Optional. The moderator\'s name (or names, separated by commas), as on the Speakers tab.' },
  { name: 'Type', kind: 'list', values: SESSION_TYPES, width: 110, note: 'Optional. Break shows as a band across the agenda.' },
  { name: 'Hall', kind: 'text', width: 120, note: 'Optional. For parallel sessions, e.g. Hall A.' },
  { name: 'Pillar', kind: 'text', width: 140, note: 'Optional. A theme, e.g. Career Konnect. With two or more, attendees can filter the agenda by pillar.' },
  { name: 'Subtitle', kind: 'long', width: 220, note: 'Optional. A second line under the title.' },
  { name: 'Presented by', kind: 'text', width: 180, note: 'Optional. Sponsor names, separated by commas, exactly as on the Sponsors tab.' },
];

const SPEAKERS = [
  { name: 'Name', kind: 'text', width: 180, required: true, note: 'Required. Each name once; the Sessions tab refers to people by this name.' },
  { name: 'Role', kind: 'list', values: ROLES, width: 130, note: 'Optional. Blank means Speaker.' },
  { name: 'Title', kind: 'text', width: 180, note: 'Optional. Job title, e.g. CTO.' },
  { name: 'Company', kind: 'text', width: 160, note: 'Optional.' },
  { name: 'Email', kind: 'email', width: 200, note: 'Optional, for organisers only (never shown on the event page). For NITK alumni, the app looks up their batch, branch and contact details from the alumni directory and fills what is blank here.' },
  { name: 'Phone', kind: 'text', width: 130, note: 'Optional, for organisers only (never shown on the event page). Overrides the alumni directory\'s number.' },
  { name: 'LinkedIn', kind: 'link', width: 220, note: 'Optional. A full link starting https://' },
  { name: 'Photo link', kind: 'link', width: 220, note: 'Optional. A full link to a square photo, starting https://' },
  { name: 'Batch', kind: 'text', width: 130, note: 'Optional, e.g. Mech 1998. Blank: filled from the alumni directory when the email matches.' },
  { name: 'Bio', kind: 'long', width: 300, note: 'Optional. A few lines about the person.' },
];

const SPONSORS = [
  { name: 'Name', kind: 'text', width: 200, required: true, note: 'Required. Each name once; the Sessions tab\'s "Presented by" refers to it.' },
  { name: 'Tier', kind: 'list', values: TIERS, width: 160, required: true, note: 'Required. Sponsors are grouped by tier on the event page; partners are listed with the partners.' },
  { name: 'Label', kind: 'text', width: 160, note: 'Optional. Shown instead of the tier, e.g. Co-presenter.' },
  { name: 'Logo link', kind: 'link', width: 240, note: 'Optional. A full link to the logo, starting https://' },
  { name: 'Website', kind: 'link', width: 220, note: 'Optional. Starting https://' },
];

// Event tab: one field per row. Read when an event is imported from the sheet
// (Events → Import); after that these are changed in the app, except the gap.
const EVENT_FIELDS = [
  { name: 'Title', kind: 'text', required: true, help: 'Required. The event\'s name; its link is made from it.' },
  { name: 'Start date', kind: 'date', required: true, help: 'Required. e.g. 15 Nov 2026.' },
  { name: 'Start time', kind: 'time', help: 'e.g. 8:00 am. Leave both times blank for a full-day event.' },
  { name: 'End date', kind: 'date', help: 'Blank: the same day as the start.' },
  { name: 'End time', kind: 'time', help: 'e.g. 9:30 pm.' },
  { name: 'Timezone', kind: 'text', help: 'Blank: Asia/Kolkata (India).' },
  { name: 'Where', kind: 'list', values: ['In person', 'Online'], required: true, help: 'Required.' },
  { name: 'Venue', kind: 'long', help: 'In person: the venue\'s name and address.' },
  { name: 'Map link', kind: 'link', help: 'In person, optional: a Google Maps link to the venue.' },
  { name: 'Meeting link', kind: 'link', help: 'Online: the meeting link (shown only to registered attendees).' },
  { name: 'Capacity', kind: 'whole', required: true, help: 'Required. The most people who can come, guests included.' },
  { name: 'Ticket price (₹)', kind: 'number', help: 'Blank or 0: a free event. Otherwise the price per person.' },
  { name: 'Guests per registration', kind: 'list', values: ['0', '1', '2', '3', '4'], help: 'Blank: 0 (no guests).' },
  { name: 'Registration opens', kind: 'datetime', help: 'Blank: when the event is published.' },
  { name: 'Registration closes', kind: 'datetime', help: 'Blank: when the event starts. Never after the start.' },
  { name: 'Description', kind: 'long', help: 'Optional. Simple formatting works: **bold**, ## headings, - lists, [links](https://…).' },
  { name: 'Thumbnail link', kind: 'link', help: 'Optional. The small image on the event card.' },
  { name: 'Banner link', kind: 'link', help: 'Optional. The wide image on the event page (about 1600×400).' },
  { name: 'Logo link', kind: 'link', help: 'Optional. The event\'s logo, for light backgrounds.' },
  { name: 'Logo link (dark backgrounds)', kind: 'link', help: 'Optional. A white version of the logo.' },
  { name: 'Gap between sessions (minutes)', kind: 'gap', help: 'Blank: 0. Used for sessions with no End time: they end this many minutes before the next one starts. Read on every Refresh.' },
];

function makeTemplate() {
  // Run from a sheet (Extensions → Apps Script): builds in that sheet.
  // Run from script.google.com: makes a new sheet and logs its link.
  const ss = SpreadsheetApp.getActiveSpreadsheet() || SpreadsheetApp.create('NITKSAA event sheet (template)');
  ss.setSpreadsheetTimeZone('Asia/Kolkata');
  ss.setSpreadsheetLocale('en_IN');
  ss.rename('NITKSAA event sheet (template)');

  // Start clean: a scratch tab, so every other tab can be removed.
  const old = ss.getSheetByName('_building');
  if (old) ss.deleteSheet(old);
  const scratch = ss.insertSheet('_building');
  ss.getSheets().forEach(function (sh) { if (sh.getName() !== '_building') ss.deleteSheet(sh); });

  buildHowTo(ss.insertSheet('How to fill', 0));
  buildEvent(ss.insertSheet('Event', 1));
  buildList(ss.insertSheet('Sessions', 2), SESSIONS, ['Start', 'Title']);
  buildList(ss.insertSheet('Speakers', 3), SPEAKERS, ['Name']);
  buildList(ss.insertSheet('Sponsors', 4), SPONSORS, ['Name', 'Tier']);

  ss.deleteSheet(scratch);
  ss.setActiveSheet(ss.getSheetByName('How to fill'));
  SpreadsheetApp.flush();
  Logger.log('Template ready: ' + ss.getUrl());
}

function buildList(sh, columns, requiredCols) {
  sh.clear();
  const width = columns.length;
  if (sh.getMaxColumns() > width) sh.deleteColumns(width + 1, sh.getMaxColumns() - width);
  if (sh.getMaxRows() < ROWS) sh.insertRowsAfter(sh.getMaxRows(), ROWS - sh.getMaxRows());
  if (sh.getMaxRows() > ROWS) sh.deleteRows(ROWS + 1, sh.getMaxRows() - ROWS);

  const header = sh.getRange(1, 1, 1, width);
  header.setValues([columns.map(function (c) { return c.name; })])
    .setFontWeight('bold').setFontColor(COLOURS.headerText).setBackground(COLOURS.header)
    .setVerticalAlignment('middle').setWrap(true);
  sh.setRowHeight(1, 34);
  sh.setFrozenRows(1);
  header.protect().setDescription('Header row: the app reads these names').setWarningOnly(true);

  const data = sh.getRange(2, 1, ROWS - 1, width);
  data.setVerticalAlignment('top');
  data.applyRowBanding(SpreadsheetApp.BandingTheme.LIGHT_GREY, false, false);

  columns.forEach(function (c, i) {
    const col = i + 1;
    const cell = sh.getRange(1, col);
    cell.setNote(c.note);
    if (c.required) cell.setValue(c.name + ' *');
    sh.setColumnWidth(col, c.width || 140);
    applyKind(sh.getRange(2, col, ROWS - 1, 1), c, colLetter(col) + '2');
  });

  // A required cell left empty on a row that has something else in it turns red.
  requiredCols.forEach(function (name) {
    const col = columns.findIndex(function (c) { return c.name === name; }) + 1;
    const letter = colLetter(col);
    const last = colLetter(width);
    const rule = SpreadsheetApp.newConditionalFormatRule()
      .whenFormulaSatisfied('=AND(' + letter + '2="",COUNTA($A2:$' + last + '2)>0)')
      .setBackground(COLOURS.missing)
      .setRanges([sh.getRange(2, col, ROWS - 1, 1)])
      .build();
    sh.setConditionalFormatRules(sh.getConditionalFormatRules().concat([rule]));
  });
}

function buildEvent(sh) {
  sh.clear();
  if (sh.getMaxColumns() > 3) sh.deleteColumns(4, sh.getMaxColumns() - 3);
  const n = EVENT_FIELDS.length;
  if (sh.getMaxRows() > n + 1) sh.deleteRows(n + 2, sh.getMaxRows() - (n + 1));

  sh.getRange(1, 1, 1, 3).setValues([['Field', 'Value', 'Help']])
    .setFontWeight('bold').setFontColor(COLOURS.headerText).setBackground(COLOURS.header);
  sh.setFrozenRows(1);
  sh.setColumnWidth(1, 240);
  sh.setColumnWidth(2, 280);
  sh.setColumnWidth(3, 460);

  EVENT_FIELDS.forEach(function (f, i) {
    const row = i + 2;
    sh.getRange(row, 1).setValue(f.required ? f.name + ' *' : f.name).setFontWeight('bold');
    sh.getRange(row, 3).setValue(f.help).setFontColor(COLOURS.help).setWrap(true);
    const value = sh.getRange(row, 2);
    if (f.required) value.setBackground(COLOURS.required);
    applyKind(value, f, 'B' + row);
  });
  sh.getRange(2, 1, n, 3).setVerticalAlignment('top');

  sh.getRange(1, 1, n + 1, 1).protect().setDescription('Field names: the app reads these').setWarningOnly(true);
  sh.getRange(1, 3, n + 1, 1).protect().setDescription('Help text').setWarningOnly(true);
  sh.getRange(1, 2).protect().setWarningOnly(true);
}

/** Format and validation for one column (or one Event value cell); `first` is its top-left cell, e.g. "B2". */
function applyKind(range, c, first) {
  let rule = null;
  switch (c.kind) {
    case 'date':
      range.setNumberFormat('d mmm yyyy');
      rule = SpreadsheetApp.newDataValidation().requireDate()
        .setHelpText('A date, e.g. 15 Nov 2026').setAllowInvalid(false).build();
      break;
    case 'time':
      range.setNumberFormat('h:mm am/pm');
      rule = SpreadsheetApp.newDataValidation()
        .requireFormulaSatisfied('=AND(ISNUMBER(' + first + '),' + first + '>=0,' + first + '<1)')
        .setHelpText('A time, e.g. 9:30 or 2:15 pm').setAllowInvalid(false).build();
      break;
    case 'datetime':
      range.setNumberFormat('d mmm yyyy h:mm am/pm');
      rule = SpreadsheetApp.newDataValidation().requireDate()
        .setHelpText('A date and time, e.g. 1 Nov 2026 10:00 am').setAllowInvalid(false).build();
      break;
    case 'link':
      range.setNumberFormat('@');
      rule = SpreadsheetApp.newDataValidation()
        .requireFormulaSatisfied('=REGEXMATCH(' + first + ',"^https://")')
        .setHelpText('A full link starting https://').setAllowInvalid(false).build();
      break;
    case 'email':
      range.setNumberFormat('@');
      rule = SpreadsheetApp.newDataValidation().requireTextIsEmail()
        .setHelpText('An email address').setAllowInvalid(false).build();
      break;
    case 'list':
      range.setNumberFormat('@');
      rule = SpreadsheetApp.newDataValidation().requireValueInList(c.values, true)
        .setHelpText('Choose from the list').setAllowInvalid(false).build();
      break;
    case 'whole':
      range.setNumberFormat('0');
      rule = SpreadsheetApp.newDataValidation()
        .requireFormulaSatisfied('=AND(ISNUMBER(' + first + '),' + first + '>0,INT(' + first + ')=' + first + ')')
        .setHelpText('A whole number above 0').setAllowInvalid(false).build();
      break;
    case 'number':
      range.setNumberFormat('0.##');
      rule = SpreadsheetApp.newDataValidation().requireNumberGreaterThanOrEqualTo(0)
        .setHelpText('A number, 0 or more').setAllowInvalid(false).build();
      break;
    case 'gap':
      range.setNumberFormat('0');
      rule = SpreadsheetApp.newDataValidation().requireNumberBetween(0, 60)
        .setHelpText('Minutes, 0 to 60').setAllowInvalid(false).build();
      break;
    case 'long':
      range.setNumberFormat('@').setWrap(true);
      break;
    default: // text
      range.setNumberFormat('@');
  }
  if (rule) range.setDataValidation(rule);
}

function buildHowTo(sh) {
  sh.clear();
  if (sh.getMaxColumns() > 4) sh.deleteColumns(5, sh.getMaxColumns() - 4);
  sh.setColumnWidth(1, 30);
  sh.setColumnWidth(2, 150);
  sh.setColumnWidth(3, 420);
  sh.setColumnWidth(4, 300);
  sh.setHiddenGridlines(true);

  const lines = [
    ['', 'NITKSAA event sheet', '', ''],
    ['', 'One sheet for an event\'s agenda, speakers and sponsors. The events app reads it; edit here, then press Refresh in the app.', '', ''],
    ['', '', '', ''],
    ['', 'Steps', '', ''],
    ['1', 'Copy', 'File → Make a copy. Name it after your event. Fill in your copy, not this template.', ''],
    ['2', 'Fill in', 'Event: the basics (used when the event is imported). Sessions, Speakers, Sponsors: one row each. Use only the tabs you need; an empty tab means none.', ''],
    ['3', 'Share', 'Share → add ' + SERVICE_ACCOUNT + ' as Viewer. Untick "Notify people" (it has no inbox).', ''],
    ['4', 'Link', 'In the events app: Events → Import (a new event), or Edit event → Link a Google Sheet (an existing event). Paste this sheet\'s link.', ''],
    ['5', 'Refresh', 'Whenever you change the sheet, press Refresh in Edit event. The event page changes only then. While linked, speakers, sessions and sponsors are changed here, not in the app.', ''],
    ['', '', '', ''],
    ['', 'Rules', '', ''],
    ['•', 'Headers', 'Keep the tab names and the header words as they are (they are locked, with a warning). Columns marked * are required.', ''],
    ['•', 'Names', 'Each speaker and sponsor once. On the Sessions tab, write names exactly as on the Speakers and Sponsors tabs; a name the app can\'t find stops the Refresh and says which row.', ''],
    ['•', 'Times', 'In the event\'s timezone (India, unless the Event tab says otherwise). A blank End runs to the next session\'s start that day.', ''],
    ['•', 'Several days', 'Put the date on each session. A blank date means the event\'s first day.', ''],
    ['•', 'Links', 'Photos, logos and websites as full links starting https://', ''],
    ['•', 'Private', 'Speakers\' email and phone are for organisers only; they never appear on the event page.', ''],
    ['•', 'Errors', 'If something is wrong, the app lists the tab and row (e.g. "Sessions, row 14: no start time") and changes nothing.', ''],
    ['', '', '', ''],
    ['', 'Example (Sessions tab)', '', ''],
    ['', 'Date · Start · End', 'Title', 'Speakers / Type'],
    ['', '15 Nov 2026 · 8:00 am · 8:30 am', 'Breakfast and networking', 'Type: Networking'],
    ['', '15 Nov 2026 · 8:30 am · (blank)', 'Keynote: Building in India', 'A. Rao · Type: Keynote'],
    ['', '15 Nov 2026 · 9:15 am · 10:00 am', 'Panel: Careers after 40', 'Priya Nair, K. Shetty · Moderator: S. Bhat'],
    ['', '', '', ''],
    ['', 'Template version ' + TEMPLATE_VERSION, '', ''],
  ];
  sh.getRange(1, 1, lines.length, 4).setValues(lines).setVerticalAlignment('top').setWrap(true);
  sh.getRange('B1').setFontSize(16).setFontWeight('bold');
  sh.getRange('B2:D2').merge().setFontColor(COLOURS.help);
  ['B4', 'B11', 'B20'].forEach(function (a) { sh.getRange(a).setFontWeight('bold').setFontSize(12); });
  sh.getRange('B5:B18').setFontWeight('bold');
  sh.getRange('B21:D21').setFontWeight('bold').setBackground('#eeeeee');
  for (let r = 5; r <= 18; r++) sh.getRange(r, 3, 1, 2).merge();
  sh.getRange('B26').setFontColor(COLOURS.help).setFontSize(9);
  sh.getRange(1, 1, lines.length, 4).protect().setDescription('Instructions').setWarningOnly(true);
}

function colLetter(n) {
  let s = '';
  while (n > 0) { const m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); }
  return s;
}
