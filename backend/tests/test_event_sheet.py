"""An event's Google Sheet (B7): reading the tabs, Refresh, the lock, unlink,
import preview and the alumni lookup.

Google is never called: `sheet_reader.read_tabs` is replaced with the tabs a
test hands it, in the API's UNFORMATTED_VALUE shape (text, or serial numbers
for real date and time cells).
"""
import asyncio

import httpx
import pytest

from app.services import alumni_directory, sheet_reader
from app.services.sheet_parser import parse_sheet
from tests.test_event_links import _draft, _publish
from tests.test_payment_refunds import (
    _FIXTURE_ADMIN,
    _TEST_ALUMNI,
    _bearer,
    _db,
    _seed,  # noqa: F401  (autouse fixture: the test users and admin)
)

LINK = "https://docs.google.com/spreadsheets/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd/edit#gid=0"

SESSIONS_H = ["Date", "Start *", "End", "Title *", "Speakers", "Moderator", "Type", "Hall", "Pillar", "Subtitle", "Presented by"]
SPEAKERS_H = ["Name *", "Title", "Company", "Email", "Role", "Phone", "LinkedIn", "Photo link", "Batch", "Bio"]
SPONSORS_H = ["Name *", "Tier *", "Logo link", "Website", "Label"]


def _admin():
    return _bearer(_FIXTURE_ADMIN)


def _tabs(sessions=(), speakers=(), sponsors=(), event=None):
    tabs = {
        "Sessions": [SESSIONS_H, *[list(r) for r in sessions]],
        "Speakers": [SPEAKERS_H, *[list(r) for r in speakers]],
        "Sponsors": [SPONSORS_H, *[list(r) for r in sponsors]],
    }
    if event is not None:
        tabs["Event"] = [["Field", "Value", ""], *[[k, v] for k, v in event.items()]]
    return tabs


def _sheet(monkeypatch, tabs):
    async def fake(sheet_id):
        assert sheet_id == "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd"
        return tabs
    monkeypatch.setattr(sheet_reader, "read_tabs", fake)


def _refresh(client, eid, url=LINK):
    return client.post(f"/api/v1/admin/events/{eid}/sheet/refresh", json={"url": url}, headers=_admin())


def _public(client, eid):
    r = client.get(f"/api/v1/events/{eid}", headers=_admin())
    assert r.status_code == 200, r.text
    return r.json()["event"]


# A small big-event sheet. The draft event is 1 Mar 2027, 08:00–10:00 IST.
SPEAKERS = [
    ["Asha Rao", "CTO", "Acme", "asha@example.com", "", "", "", "", "", "Builds things."],
    ["Vikram Shenoy", "Partner", "Fund", "", "Panelist", "+91 98450 00000", "linkedin.com/in/vikram", "", "Mech 1998", ""],
    ["Meera Nayak", "", "", "", "Moderator", "", "", "", "", ""],
]
SPONSORS = [
    ["Acme Corp", "Gold sponsor", "https://acme.example/logo.png", "https://acme.example", "Co-presenter"],
    ["Daily News", "Media partner", "", "", ""],
]
SESSIONS = [
    ["", "8:00 am", "", "Welcome", "Asha Rao", "", "Keynote", "", "Main Event", "", ""],
    ["", "8:30 am", "9:15 am", "Future of Work", "Asha Rao, vikram shenoy", "Meera Nayak", "Panel", "Hall A", "Career Konnect", "Hiring in 2027", "Acme Corp"],
    ["", "8:30 am", "9:15 am", "Workshop", "", "", "Workshop", "Hall B", "", "", ""],
    ["", "9:15 am", "", "Tea", "", "", "Break", "", "", "", ""],
]


# ── The parser ──────────────────────────────────────────────────────────────

def test_parse_times_dates_and_blank_ends():
    tabs = _tabs(
        sessions=[
            [46447.0, 0.3125, "", "Opening", "", "", "", "", "", "", ""],          # 1 Mar 2027, 7:30
            ["1 Mar 2027", "08:00", "", "Second", "", "", "", "", "", "", ""],
            ["", "8.40 am", "", "Last", "", "", "", "", "", "", ""],
        ],
        event={"Gap between sessions (minutes)": 5.0},
    )
    r = parse_sheet(tabs, event_start="2027-03-01 07:30", event_end="2027-03-01 10:00")
    assert r.errors == []
    assert [(s["start"], s["end"]) for s in r.sessions] == [
        ("2027-03-01 07:30", "2027-03-01 07:55"),  # to the next start, less the 5-minute gap
        ("2027-03-01 08:00", "2027-03-01 08:35"),
        ("2027-03-01 08:40", "2027-03-01 10:00"),  # the last runs to the event's end
    ]


def test_parse_reports_each_problem_with_tab_and_row():
    tabs = _tabs(
        speakers=[["Asha Rao"], ["asha  rao"], ["Bad Link", "", "", "", "", "", "http://x"]],
        sponsors=[["Acme", "Gold sponsor"], ["Daily News", "Media partner"], ["Who", "Platinum"]],
        sessions=[
            ["", "", "", "No start", "", "", "", "", "", "", ""],
            ["", "9:00", "", "Unknown speaker", "A. Nobody", "", "", "", "", "", ""],
            ["", "9:00", "", "Partner presents", "", "", "", "", "", "", "Daily News"],
            ["", "9:00", "", "Bad type", "", "", "Lecture", "", "", "", ""],
            ["", "25:00", "", "Bad time", "", "", "", "", "", "", ""],
            ["", "9:00", "8:00", "Ends early", "", "", "", "", "", "", ""],
        ],
    )
    r = parse_sheet(tabs, event_start="2027-03-01 08:00", event_end="2027-03-01 18:00")
    assert r.errors == [
        "Speakers, row 3: 'asha rao' is already on row 2. Each person once.",
        "Speakers, row 4: the LinkedIn link must start https://",
        "Sponsors, row 4: tier 'Platinum' isn't in the list (e.g. Gold sponsor, Media partner).",
        "Sessions, row 2: no start time.",
        "Sessions, row 3: speaker 'A. Nobody' isn't on the Speakers tab.",
        "Sessions, row 4: 'Daily News' is a partner; only sponsors can present a session.",
        "Sessions, row 5: type 'Lecture' isn't one of Keynote, Talk, Panel, Fireside, Workshop, Showcase, Networking, Awards, Break.",
        "Sessions, row 6: start '25:00' isn't a time (e.g. 9:30 or 2:15 pm).",
        "Sessions, row 7: it ends before it starts.",
    ]


def test_parse_missing_header_and_empty_tabs():
    r = parse_sheet({"Sessions": [["When", "What"], ["9:00", "Talk"]], "Speakers": [SPEAKERS_H]})
    assert r.errors == [
        "Sessions tab: no 'Start' column. Keep the header row as in the template.",
        "Sessions tab: no 'Title' column. Keep the header row as in the template.",
    ]
    r = parse_sheet({"Sessions": [SESSIONS_H], "Speakers": [], "Other": [["x"]]})
    assert (r.errors, r.sessions, r.speakers, r.sponsors) == ([], [], [], [])


def test_parse_event_tab_for_import():
    tabs = _tabs(event={
        "Title *": "Breakfast", "Date *": "15 Nov 2026", "Start time": "7:30 am", "End time": "9:30 am",
        "Venue": "BHIVE, Church Street", "Capacity *": 75.0, "Ticket price (₹)": "100", "Guests per registration": "2",
        "Registration closes": "14 Nov 2026 8:00 pm", "Gap between sessions (minutes)": "",
    })
    r = parse_sheet(tabs, need_event=True)
    assert r.errors == []
    assert r.event == {
        "title": "Breakfast", "timezone": "Asia/Kolkata", "is_full_day": False,
        "start": "2026-11-15 07:30", "end": "2026-11-15 09:30",
        "is_virtual": False, "location_text": "BHIVE, Church Street", "location_maps_url": None, "virtual_url": None,
        "capacity": 75, "is_free": False, "ticket_price": 100.0, "max_guests": 2,
        "registration_opens_at": None, "registration_closes_at": "2026-11-14 20:00",
        "description": None, "thumbnail_url": None, "banner_url": None,
        "brand_logo_url": None, "brand_logo_dark_url": None,
    }

    online = parse_sheet(_tabs(event={
        "Title": "Webinar", "Date": "1 Dec 2026", "Capacity": "500", "Meeting link": "https://meet.example/x",
    }), need_event=True)
    assert online.errors == []
    assert (online.event["is_virtual"], online.event["is_full_day"], online.event["start"], online.event["end"]) == (
        True, True, "2026-12-01 00:00", "2026-12-02 00:00",
    )

    bad = parse_sheet(_tabs(event={
        "Title": "X", "Date": "1 Dec 2026", "Start time": "10:00", "End time": "11:00", "Capacity": "0",
        "Registration closes": "1 Dec 2026 10:30 am",
    }), need_event=True)
    assert bad.event is None
    assert bad.errors == [
        "Event: give a Venue, or a Meeting link for an online event.",
        "Event, row 6: capacity must be a whole number above 0.",
        "Event, row 7: registration can't close after the event starts.",
    ]


# ── Refresh ─────────────────────────────────────────────────────────────────

def test_refresh_links_and_saves_everything(client, monkeypatch):
    eid = _draft(client)["event_id"]
    _sheet(monkeypatch, _tabs(SESSIONS, SPEAKERS, SPONSORS))
    r = _refresh(client, eid)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["summary"] == {"sessions": 4, "speakers": 3, "sponsors": 1, "partners": 1}
    assert body["url"] == "https://docs.google.com/spreadsheets/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd/edit"
    assert body["warnings"] == []

    event = _public(client, eid)
    people = {p["person_id"]: p for p in event["people"]}
    by_name = {p["fullname"]: p for p in event["people"]}
    assert by_name["Vikram Shenoy"]["role"] == "PANELIST"
    assert by_name["Vikram Shenoy"]["linkedin_url"] == "https://linkedin.com/in/vikram"
    assert by_name["Vikram Shenoy"]["batch"] == "Mech 1998"
    assert all("email" not in p and "phone" not in p for p in event["people"])

    sessions = {s["title"]: s for s in event["sessions"]}
    panel = sessions["Future of Work"]
    assert (panel["session_type"], panel["pillar"], panel["track"], panel["description"]) == (
        "PANEL", "Career Konnect", "Hall A", "Hiring in 2027",
    )
    assert [(people[p["person_id"]]["fullname"], p["role"]) for p in panel["people"]] == [
        ("Asha Rao", "SPEAKER"), ("Vikram Shenoy", "PANELIST"), ("Meera Nayak", "MODERATOR"),
    ]
    acme = next(s for s in event["sponsors"] if s["name"] == "Acme Corp")
    assert (acme["sponsor_type"], acme["label"]) == ("GOLD_SPONSOR", "Co-presenter")
    assert panel["presented_by"] == [acme["sponsor_id"]]
    assert [p["name"] for p in event["partners"]] == ["Daily News"]
    # Blank ends: Welcome runs to the next start, Tea to the event's end.
    assert sessions["Welcome"]["end_datetime"].startswith("2027-03-01T03:00:00")  # 08:30 IST
    assert sessions["Tea"]["end_datetime"].startswith("2027-03-01T04:30:00")      # 10:00 IST

    details = client.get(f"/api/v1/admin/events/{eid}/details", headers=_admin()).json()
    asha = next(s for s in details["speakers"] if s["fullname"] == "Asha Rao")
    assert (asha["email"], asha["bio"]) == ("asha@example.com", "Builds things.")
    admin_event = client.get("/api/v1/admin/events", headers=_admin()).json()
    mine = next(e for e in admin_event if e["event_id"] == eid)
    assert mine["agenda_sheet_url"].endswith("/edit") and mine["agenda_sheet_read_at"]


def test_refresh_again_updates_in_place_and_keeps_checked_in_sessions(client, monkeypatch):
    eid = _draft(client)["event_id"]
    _publish(client, eid)
    _sheet(monkeypatch, _tabs(SESSIONS, SPEAKERS, SPONSORS))
    assert _refresh(client, eid).status_code == 200
    before = client.get(f"/api/v1/admin/events/{eid}/details", headers=_admin()).json()
    ids = {s["title"]: s["session_id"] for s in before["sessions"]}
    person = {s["fullname"]: s["person_id"] for s in before["speakers"]}

    # Someone checks in to "Workshop".
    reg = client.post(f"/api/v1/events/{eid}/register", json={"phone": "+919000000001"}, headers=_bearer(_TEST_ALUMNI))
    assert reg.status_code in (200, 201), reg.text
    _db(
        "INSERT INTO check_ins (registration_id, event_id, scanned_by, session_id, result)"
        " VALUES ($1, $2, $3, $4, 'success')",
        reg.json()["registration_id"], eid, _FIXTURE_ADMIN["firebase_uid"], ids["Workshop"],
    )

    # The sheet changes: a title edited (same start), Workshop and Meera gone.
    sessions = [list(r) for r in SESSIONS if r[3] != "Workshop"]
    sessions[1][3] = "The Future of Work"
    sessions[1][5] = ""
    speakers = [r for r in SPEAKERS if r[0] != "Meera Nayak"]
    _sheet(monkeypatch, _tabs(sessions, speakers, SPONSORS))
    r = _refresh(client, eid)
    assert r.status_code == 200, r.text
    assert r.json()["warnings"] == ["'Workshop' isn't in the sheet any more but people checked in to it, so it was kept."]

    after = client.get(f"/api/v1/admin/events/{eid}/details", headers=_admin()).json()
    new_ids = {s["title"]: s["session_id"] for s in after["sessions"]}
    assert new_ids["Welcome"] == ids["Welcome"] and new_ids["Tea"] == ids["Tea"]
    assert new_ids["Workshop"] == ids["Workshop"]
    assert "Future of Work" not in new_ids  # renamed: matched by title elsewhere or recreated
    assert {s["fullname"]: s["person_id"] for s in after["speakers"]} == {
        "Asha Rao": person["Asha Rao"], "Vikram Shenoy": person["Vikram Shenoy"],
    }


def test_a_bad_sheet_changes_nothing(client, monkeypatch):
    eid = _draft(client)["event_id"]
    _sheet(monkeypatch, _tabs(SESSIONS, SPEAKERS, SPONSORS))
    assert _refresh(client, eid).status_code == 200
    broken = [list(r) for r in SESSIONS]
    broken[0][4] = "Nobody Here"
    _sheet(monkeypatch, _tabs(broken, SPEAKERS, SPONSORS))
    r = _refresh(client, eid)
    assert r.status_code == 422
    assert r.json()["detail"]["errors"] == ["Sessions, row 2: speaker 'Nobody Here' isn't on the Speakers tab."]
    assert len(_public(client, eid)["sessions"]) == 4


@pytest.mark.parametrize("code", ["sheet_not_shared", "sheet_not_found", "sheets_unavailable"])
def test_unreachable_sheet_is_explained(client, monkeypatch, code):
    eid = _draft(client)["event_id"]

    async def fail(sheet_id):
        raise sheet_reader.SheetAccessError(code, "The app can't open this sheet.")
    monkeypatch.setattr(sheet_reader, "read_tabs", fail)
    r = _refresh(client, eid)
    assert r.status_code == 422
    assert r.json()["detail"] == {"code": code, "message": "The app can't open this sheet."}
    r = _refresh(client, eid, url="not a link")
    assert r.json()["detail"]["code"] == "sheet_link_invalid"


# ── The lock ────────────────────────────────────────────────────────────────

def test_linked_sheet_locks_the_lists_until_unlinked(client, monkeypatch):
    eid = _draft(client)["event_id"]
    _sheet(monkeypatch, _tabs(SESSIONS, SPEAKERS, SPONSORS))
    assert _refresh(client, eid).status_code == 200
    sponsor_id = next(s["sponsor_id"] for s in _public(client, eid)["sponsors"])

    sponsor = {"sponsor_type": "GOLD_SPONSOR", "name": "Sneaky"}
    assert client.post(f"/api/v1/events/{eid}/sponsors", json=sponsor, headers=_admin()).status_code == 409
    assert client.delete(f"/api/v1/events/{eid}/sponsors/{sponsor_id}", headers=_admin()).status_code == 409
    person = {"role": "SPEAKER", "fullname": "Sneaky"}
    assert client.post(f"/api/v1/events/{eid}/people", json=person, headers=_admin()).status_code == 409

    # The form's save still saves the fees, and leaves speakers and sessions as the sheet set them.
    r = client.put(f"/api/v1/admin/events/{eid}/details", json={
        "speakers": [{"fullname": "Someone Else"}], "sessions": [],
        "fees": [{"name": "Entry", "fee_type": "participation", "amount": 100}],
    }, headers=_admin())
    assert r.status_code == 200, r.text
    assert len(r.json()["sessions"]) == 4 and len(r.json()["speakers"]) == 3
    assert r.json()["fees"][0]["name"] == "Entry"

    r = client.delete(f"/api/v1/admin/events/{eid}/sheet", headers=_admin())
    assert r.status_code == 200, r.text
    assert client.post(f"/api/v1/events/{eid}/sponsors", json=sponsor, headers=_admin()).status_code == 201
    assert len(_public(client, eid)["sessions"]) == 4  # unlinking keeps what's there


def test_details_save_keeps_speaker_extras_when_left_out(client):
    eid = _draft(client)["event_id"]
    url = f"/api/v1/admin/events/{eid}/details"
    r = client.put(url, json={"speakers": [{"fullname": "Asha Rao", "email": "ASHA@Example.com",
                                            "photo_url": "https://x/p.jpg", "batch": "CS 2001"}]}, headers=_admin())
    assert r.status_code == 200, r.text
    sp = r.json()["speakers"][0]
    assert (sp["email"], sp["photo_url"], sp["batch"]) == ("asha@example.com", "https://x/p.jpg", "CS 2001")
    r = client.put(url, json={"speakers": [{"person_id": sp["person_id"], "fullname": "Asha Rao", "title": "CTO"}]},
                   headers=_admin())
    sp = r.json()["speakers"][0]
    assert (sp["title"], sp["email"], sp["photo_url"]) == ("CTO", "asha@example.com", "https://x/p.jpg")


# ── Import and info ─────────────────────────────────────────────────────────

def test_preview_for_import(client, monkeypatch):
    _sheet(monkeypatch, _tabs(SESSIONS, SPEAKERS, SPONSORS, event={
        "Title": "Imported", "Date": "1 Mar 2027", "Start time": "8:00", "End time": "10:00",
        "Venue": "Hall", "Capacity": "50",
    }))
    r = client.post("/api/v1/admin/sheets/preview", json={"url": LINK}, headers=_admin())
    assert r.status_code == 200, r.text
    assert r.json()["event"]["title"] == "Imported"
    assert r.json()["summary"] == {"sessions": 4, "speakers": 3, "sponsors": 1, "partners": 1}

    info = client.get("/api/v1/admin/sheets/info", headers=_admin()).json()
    assert info["share_with"].endswith(".iam.gserviceaccount.com")
    assert [t["name"] for t in info["templates"]] == ["Blank", "Breakfast example", "NITKonnect example"]
    assert client.get("/api/v1/admin/sheets/info", headers=_bearer(_TEST_ALUMNI)).status_code == 403


def test_spreadsheet_id_from_links():
    assert sheet_reader.spreadsheet_id(LINK) == "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd"
    assert sheet_reader.spreadsheet_id("https://docs.google.com/spreadsheets/d/1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd/copy") \
        == "1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd"
    assert sheet_reader.spreadsheet_id("https://example.com/sheet") is None


# ── Alumni directory ────────────────────────────────────────────────────────

def _directory(monkeypatch, handler):
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "nitksaa_partner_api_key", "nitk_test_key")
    real = httpx.AsyncClient
    monkeypatch.setattr(alumni_directory.httpx, "AsyncClient",
                        lambda **kw: real(transport=httpx.MockTransport(handler), **kw))


def _speakers():
    return parse_sheet(_tabs(speakers=[
        ["Padmanand", "", "", "padmanand@outlook.com", "", "", "", "", "", ""],
        ["Typed Batch", "", "", "typed@example.com", "", "+91 1", "", "", "Mine", ""],
        ["Twice", "", "", "twice@example.com", "", "", "", "", "", ""],
        ["Nobody", "", "", "nobody@example.com", "", "", "", "", "", ""],
    ])).speakers


def test_alumni_lookup_fills_only_blanks(monkeypatch):
    record = {"alumni_id": "ALUMNI-002923", "graduationyear": 1981, "branch": "Electrical & Electronics",
              "phone": "", "secondaryphone": "+1-425; +91-1", "linkedin": "https://www.linkedin.com/in/pw"}

    def handler(request):
        assert request.headers["X-API-Key"] == "nitk_test_key"
        assert request.url.path.endswith("/alumni/profile/lookup")
        return httpx.Response(200, json={"results": [
            {"query": "nobody@example.com", "matches": []},
            {"query": "padmanand@outlook.com", "matches": [record]},
            {"query": "twice@example.com", "matches": [record, record]},
            {"query": "typed@example.com", "matches": [{**record, "alumni_id": "A2", "phone": "+91 2"}]},
        ]})
    _directory(monkeypatch, handler)
    speakers = _speakers()
    warnings = asyncio.run(alumni_directory.fill_speakers(speakers))
    by = {s["fullname"]: s for s in speakers}
    assert (by["Padmanand"]["batch"], by["Padmanand"]["linkedin_url"], by["Padmanand"]["phone"], by["Padmanand"]["alumni_id"]) == (
        "Electrical & Electronics, 1981", "https://www.linkedin.com/in/pw", "+1-425", "ALUMNI-002923",
    )
    assert (by["Typed Batch"]["batch"], by["Typed Batch"]["phone"]) == ("Mine", "+91 1")  # the sheet wins
    assert by["Twice"]["alumni_id"] is None and by["Nobody"]["alumni_id"] is None
    assert warnings == ["Speakers, row 4: twice@example.com is on 2 alumni records, so none was used."]


def test_alumni_lookup_problems_are_warnings(monkeypatch):
    _directory(monkeypatch, lambda request: httpx.Response(429, json={"detail": "rate limited"}))
    speakers = _speakers()
    assert asyncio.run(alumni_directory.fill_speakers(speakers)) == [
        "The alumni directory didn't answer (error 429); batch and LinkedIn weren't filled in."
    ]
    assert all(s["alumni_id"] is None for s in speakers)
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "nitksaa_partner_api_key", "")
    assert asyncio.run(alumni_directory.fill_speakers(_speakers())) == []


def _day(date_, start="9:00", end="", title=None):
    return [date_, start, end, title or f"{date_} {start}", "", "", "", "", "", "", ""]


def test_parse_moves_a_templates_dates_onto_the_event():
    # One-day event on 1 Mar 2027; the copied template says 21 Feb 2026.
    r = parse_sheet(_tabs(sessions=[_day("21 Feb 2026", "9:00"), _day("21 Feb 2026", "10:00")]),
                    event_start="2027-03-01 08:00", event_end="2027-03-01 18:00")
    assert r.errors == []
    assert [s["start"] for s in r.sessions] == ["2027-03-01 09:00", "2027-03-01 10:00"]
    assert r.warnings == ["Sessions on 21 Feb 2026 are shown on 1 Mar 2027, the event's date."]

    # Two days onto a two-day event, in order.
    r = parse_sheet(_tabs(sessions=[_day("21 Feb 2026"), _day("22 Feb 2026")]),
                    event_start="2027-03-01 08:00", event_end="2027-03-02 18:00")
    assert [(s["start"], s["end"]) for s in r.sessions] == [
        ("2027-03-01 09:00", "2027-03-01 18:00"),  # each day's last session runs to the event's end time
        ("2027-03-02 09:00", "2027-03-02 18:00"),
    ]
    assert r.warnings == [
        "Sessions on 21 Feb 2026 are shown on 1 Mar 2027, the event's day 1.",
        "Sessions on 22 Feb 2026 are shown on 2 Mar 2027, the event's day 2.",
    ]


def test_parse_more_days_than_the_event_still_warns():
    rows = [_day("21 Feb 2026", f"{h}:00", f"{h}:45") for h in (9, 10, 11)] + [_day("22 Feb 2026")]
    r = parse_sheet(_tabs(sessions=rows), event_start="2027-03-01 08:00", event_end="2027-03-01 18:00")
    assert r.errors == []
    assert r.warnings == [
        "Sessions on 21 Feb 2026 are shown on 1 Mar 2027, the event's date.",
        "Sessions on 22 Feb 2026 are shown on 2 Mar 2027, the event's date.",
        "Sessions, row 5: 2 Mar 2027 is outside the event's dates.",
    ]


def test_parse_dates_inside_the_event_stay():
    r = parse_sheet(_tabs(sessions=[_day("1 Mar 2027"), _day("", "10:00")]),
                    event_start="2027-03-01 08:00", event_end="2027-03-01 18:00")
    assert (r.errors, r.warnings) == ([], [])
    # A full-day event ends at midnight after its last day: sessions on that day stay.
    r = parse_sheet(_tabs(sessions=[_day("1 Mar 2027")]), event_start="2027-03-01 00:00", event_end="2027-03-02 00:00")
    assert (r.warnings, r.sessions[0]["start"]) == ([], "2027-03-01 09:00")
