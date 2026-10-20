# Event sheets

Scripts for the Google Sheets that events are imported from (Events → **Import**). How importing works is in the Admin guide (`frontend/assets/guides/ADMIN_GUIDE.md`, "Import from a Google Sheet"); the server side is `backend/app/api/admin_event_sheet.py` and `backend/app/services/sheet_parser.py`.

| File | What it does |
|---|---|
| `make_event_sheet_templates.gs` | Builds the three template sheets (**Blank**, **Breakfast example**, **NITKonnect example**) in one run. Run it in Apps Script as the account that owns the templates (script.google.com → New project → paste → Run `makeTemplates`). The log lists each sheet's link and its "copy" link; share each as "Anyone with the link: Viewer". Running it again makes three new sheets, so the links in the app's settings (`SHEET_TEMPLATE_*_URL`) must then be updated. |
| `export_event_to_sheet.sql` | Read-only queries that export an event from the database in the template's columns (Event, Sessions, Speakers, Sponsors), for filling an example sheet. Run in Cloud SQL Studio; put the events' links (slugs) in each query. |

**Keep the tab names and header words** in the templates as they are: the server finds tabs by name and columns by their header words. The column order, extra columns and blank rows don't matter.
