# NITKSAA Event Platform — Alpha curl/Postman Test Guide

**Base URL:** `http://localhost:8000`  
**Dev Auth Headers:**
- Admin: `-H "X-Dev-User: admin"`
- Attendee: `-H "X-Dev-User: attendee"`

> All commands assume the server is running: `cd backend && uvicorn app.main:app --reload`
> Set `EVENT_ID` and `REG_ID` shell variables as you go for convenience.

---

## 1. Health Check

```bash
# Root health (no auth needed)
curl -s http://localhost:8000/healthz | jq .

# API health with DB connectivity check
curl -s http://localhost:8000/api/v1/health | jq .
```

Expected:
```json
{"status": "ok", "version": "0.1.0-alpha", "env": "development", "db": "ok"}
```

---

## 2. Create Event (Admin)

```bash
curl -s -X POST http://localhost:8000/api/v1/admin/events \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: admin" \
  -d '{
    "slug": "nitksaa-reunion-2026",
    "title": "NITKSAA Annual Reunion 2026",
    "description": "Annual alumni reunion at NIT Karnataka campus.",
    "event_type": "event",
    "venue_name": "NIT Karnataka",
    "venue_address": "Surathkal, Mangaluru",
    "city": "Mangaluru",
    "country": "India",
    "is_virtual": false,
    "starts_at": "2026-12-20T10:00:00+05:30",
    "ends_at": "2026-12-20T18:00:00+05:30",
    "timezone": "Asia/Kolkata",
    "capacity": 500
  }' | jq .

# Save event_id for subsequent steps
EVENT_ID=1
```

Expected: HTTP 201 with event object, `"status": "draft"`

---

## 3. Publish Event (Admin)

```bash
curl -s -X POST http://localhost:8000/api/v1/admin/events/${EVENT_ID}/publish \
  -H "X-Dev-User: admin" | jq .
```

Expected: HTTP 200, `"status": "published"`

---

## 4. List Public Events (No auth)

```bash
curl -s http://localhost:8000/api/v1/events | jq .
```

Expected: Array containing the published event.

---

## 5. Get Event Detail (No auth)

```bash
curl -s http://localhost:8000/api/v1/events/${EVENT_ID} | jq .
```

Expected: Full event object.

---

## 6. Add Session (Admin)

```bash
curl -s -X POST http://localhost:8000/api/v1/admin/events/${EVENT_ID}/sessions \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: admin" \
  -d '{
    "title": "Keynote: Alumni Impact",
    "speaker_name": "Prof. Ramesh Kumar",
    "location": "Main Auditorium",
    "starts_at": "2026-12-20T10:30:00+05:30",
    "ends_at": "2026-12-20T11:30:00+05:30",
    "sort_order": 1
  }' | jq .
```

---

## 7. Register Attendee 1 (Auth required — attendee context)

```bash
curl -s -X POST http://localhost:8000/api/v1/events/${EVENT_ID}/register \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: attendee" \
  -d '{
    "full_name": "Rajesh Nair",
    "email": "rajesh.nair@example.com",
    "ref_id": "NITK-ALU-2001-001",
    "phone": "+919876543210",
    "badge_name": "Rajesh"
  }' | jq .

# Save registration_id and qr_token
REG_ID=1
QR_TOKEN=$(curl -s http://localhost:8000/api/v1/admin/events/${EVENT_ID}/registrations \
  -H "X-Dev-User: admin" | jq -r '.[0].qr_token')
echo "QR Token: $QR_TOKEN"
```

Expected: HTTP 201 with `qr_token` field (format: `nitksaa_evt_...`)

---

## 8. Register Attendee 2 (Different user)

```bash
curl -s -X POST http://localhost:8000/api/v1/events/${EVENT_ID}/register \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: attendee" \
  -d '{
    "full_name": "Priya Sharma",
    "email": "priya.sharma@example.com",
    "ref_id": "NITK-ALU-2005-042"
  }' | jq .
```

Expected: HTTP 201 with a different `qr_token`

---

## 9. Attempt Duplicate Registration (Must fail)

```bash
curl -s -X POST http://localhost:8000/api/v1/events/${EVENT_ID}/register \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: attendee" \
  -d '{
    "full_name": "Rajesh Nair Again",
    "email": "rajesh.nair@example.com"
  }' | jq .
```

Expected: HTTP 409 `{"detail": "registration_duplicate"}`

---

## 10. Verify QR Token (Before check-in)

```bash
curl -s "http://localhost:8000/api/v1/admin/events/${EVENT_ID}/check-ins/verify?qr_token=${QR_TOKEN}" \
  -H "X-Dev-User: admin" | jq .
```

Expected: `"valid": true, "already_checked_in": false, "message": "ready_to_checkin"`

---

## 11. Check In Attendee

```bash
curl -s -X POST http://localhost:8000/api/v1/admin/events/${EVENT_ID}/check-ins \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: admin" \
  -d "{\"qr_token\": \"${QR_TOKEN}\"}" | jq .
```

Expected: HTTP 201 with check-in record.

---

## 12. Attempt Duplicate Check-In (Must fail)

```bash
curl -s -X POST http://localhost:8000/api/v1/admin/events/${EVENT_ID}/check-ins \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: admin" \
  -d "{\"qr_token\": \"${QR_TOKEN}\"}" | jq .
```

Expected: HTTP 409 `{"detail": "already_checked_in"}`

---

## 13. Attempt Invalid QR Token

```bash
curl -s -X POST http://localhost:8000/api/v1/admin/events/${EVENT_ID}/check-ins \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: admin" \
  -d '{"qr_token": "nitksaa_evt_INVALID_TOKEN_XYZ"}' | jq .
```

Expected: HTTP 404 `{"detail": "invalid_qr_token"}`

---

## 14. List Registrations (Admin)

```bash
curl -s http://localhost:8000/api/v1/admin/events/${EVENT_ID}/registrations \
  -H "X-Dev-User: admin" | jq .
```

---

## 15. List Attendees (Admin)

```bash
curl -s http://localhost:8000/api/v1/admin/events/${EVENT_ID}/attendees \
  -H "X-Dev-User: admin" | jq .
```

---

## 16. List Check-Ins (Admin)

```bash
curl -s http://localhost:8000/api/v1/admin/events/${EVENT_ID}/check-ins \
  -H "X-Dev-User: admin" | jq .
```

---

## 17. List Check-In Attempts (Admin — full audit log)

```bash
curl -s http://localhost:8000/api/v1/admin/events/${EVENT_ID}/check-in-attempts \
  -H "X-Dev-User: admin" | jq .
```

Expected: Array including success, duplicate, and invalid attempts logged from steps 11–13.

---

## 18. List All Events — Admin View

```bash
curl -s http://localhost:8000/api/v1/admin/events \
  -H "X-Dev-User: admin" | jq .
```

---

## 19. Close Event (Admin)

```bash
curl -s -X POST http://localhost:8000/api/v1/admin/events/${EVENT_ID}/close \
  -H "X-Dev-User: admin" | jq .
```

Expected: `"status": "closed"`

---

## 20. Try Register on Closed Event (Must fail)

```bash
curl -s -X POST http://localhost:8000/api/v1/events/${EVENT_ID}/register \
  -H "Content-Type: application/json" \
  -H "X-Dev-User: attendee" \
  -d '{
    "full_name": "Late Comer",
    "email": "latecomer@example.com"
  }' | jq .
```

Expected: HTTP 400 `{"detail": "event_not_published"}`

---

## Postman Collection Quick Setup

1. Create a collection: `NITKSAA Event Alpha`
2. Set collection variable: `base_url = http://localhost:8000`
3. Add header at collection level: `X-Dev-User = admin` (override per request for attendee flows)
4. Import requests above using `{{base_url}}` in place of `http://localhost:8000`
5. Chain requests: use "Tests" tab to save `pm.environment.set("event_id", pm.response.json().event_id)`

---

## Error Reference

| Code | detail | Meaning |
|------|--------|---------|
| 400 | `event_not_published` | Event not in published state |
| 400 | `registration_closed` | Registration deadline passed |
| 400 | `registration_not_open_yet` | Window not open |
| 401 | `missing_or_invalid_x_dev_user_header` | Missing dev auth |
| 403 | `admin_required` | Attendee tried admin endpoint |
| 404 | `event_not_found` | No such event |
| 404 | `registration_not_found` | No such registration |
| 404 | `invalid_qr_token` | QR token not in DB |
| 409 | `registration_duplicate` | Already registered |
| 409 | `already_checked_in` | Already scanned |
| 409 | `capacity_reached` | Event full |
| 409 | `slug_already_exists` | Slug taken |
