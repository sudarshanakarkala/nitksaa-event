# Backend API Index

This index documents frontend-facing backend APIs for the NITKSAA event platform. Planned entries are listed for frontend diagnostics and UI planning only; this task does not implement new backend endpoints.

## Health/Foundation

### GET /api/v1/health
- Auth requirement: No
- Request body: None
- Response body:
```json
{
  "status": "ok",
  "version": "1.0.0",
  "env": "development",
  "db": "ok"
}
```
- Used by screen: Developer Diagnostics > General > Network Test / Foundation Status
- Current status: Implemented

## Authentication

### POST /api/v1/auth/firebase
- Auth requirement: Firebase ID token required
- Request body:
```json
{
  "token": "firebase_id_token"
}
```
- Response body:
```json
{
  "status": "ok",
  "access_token": "backend_jwt",
  "token_type": "bearer",
  "firebase_uid": "firebase-user-id",
  "user_type": "alumni",
  "fullname": "NITKSAA Member",
  "ref_id": "ALUMNI123",
  "graduation_year": 2010
}
```
- Used by screen: LoginScreen, Developer Diagnostics > Authentication > Backend Auth Test
- Current status: Implemented

### GET /api/v1/auth/me
- Auth requirement: Backend JWT required
- Request body: None
- Response body:
```json
{
  "firebase_uid": "firebase-user-id",
  "email": "member@example.com",
  "fullname": "NITKSAA Member",
  "user_type": "alumni",
  "ref_id": "ALUMNI123",
  "graduation_year": 2010
}
```
- Used by screen: Route/session validation, Developer Diagnostics > Authentication > /auth/me Test
- Current status: Implemented

## Developer Diagnostics

### GET /api/v1/dev/diagnostics/db/tables
- Auth requirement: Backend JWT required, debug/dev only
- Request body: None
- Response body:
```json
{
  "tables": [
    {
      "name": "event_users",
      "available": true,
      "row_count": 1
    }
  ]
}
```
- Used by screen: Developer Diagnostics > Database > Database Tables Test
- Current status: Implemented

### GET /api/v1/dev/diagnostics/db/event_users
- Auth requirement: Backend JWT required, debug/dev only
- Request body: None
- Response body:
```json
{
  "table": "event_users",
  "available": true,
  "row_count": 1,
  "rows": [
    {
      "email": "member@example.com",
      "fullname": "NITKSAA Member",
      "user_type": "alumni",
      "is_suspended": false
    }
  ]
}
```
- Used by screen: Developer Diagnostics > Database > Event Users Test
- Current status: Implemented

### GET /api/v1/dev/diagnostics/audit
- Auth requirement: Admin/dev required
- Request body: None
- Response body:
```json
{
  "entries": [
    {
      "action": "event.updated",
      "actor": "admin@example.com",
      "created_at": "2026-06-03T10:00:00Z"
    }
  ]
}
```
- Used by screen: Developer Diagnostics > Admin / Attendees > Audit Trail Test
- Current status: Planned / Placeholder

## Events

### GET /api/v1/events
- Auth requirement: No
- Request body: None
- Response body:
```json
{
  "events": [
    {
      "id": "event-id",
      "slug": "annual-meet",
      "title": "Annual Meet",
      "starts_at": "2026-06-30T10:00:00Z",
      "status": "published"
    }
  ]
}
```
- Used by screen: Future Event List screen, Developer Diagnostics > Event Management > Events API Test
- Current status: Planned / Placeholder

### GET /api/v1/events/{slug}
- Auth requirement: No
- Request body: None
- Response body:
```json
{
  "id": "event-id",
  "slug": "annual-meet",
  "title": "Annual Meet",
  "location": "NITK",
  "speakers": [],
  "capacity": 100,
  "registered_count": 40,
  "registration_open": true
}
```
- Used by screen: Future Event Detail screen, Capacity Guard Test
- Current status: Planned / Placeholder

### POST /api/v1/events
- Auth requirement: Admin/Coordinator required
- Request body:
```json
{
  "title": "Annual Meet",
  "slug": "annual-meet",
  "starts_at": "2026-06-30T10:00:00Z",
  "location": "NITK"
}
```
- Response body:
```json
{
  "id": "event-id",
  "status": "draft",
  "title": "Annual Meet"
}
```
- Used by screen: Future Admin Event Creation form
- Current status: Planned / Placeholder

### PATCH /api/v1/events/{id}/status
- Auth requirement: Admin/Coordinator required
- Request body:
```json
{
  "status": "published"
}
```
- Response body:
```json
{
  "id": "event-id",
  "status": "published"
}
```
- Used by screen: Future Admin publish/unpublish action
- Current status: Planned / Placeholder

## Registrations

### POST /api/v1/events/{id}/register
- Auth requirement: Backend JWT required
- Request body:
```json
{
  "attendee_note": "Optional note"
}
```
- Response body:
```json
{
  "registration_id": "registration-id",
  "status": "confirmed",
  "confirmation_email_sent": true
}
```
- Used by screen: Future Registration confirmation screen, Confirmation Email Test
- Current status: Planned / Placeholder

### GET /api/v1/events/{id}/my-registration
- Auth requirement: Backend JWT required
- Request body: None
- Response body:
```json
{
  "registered": true,
  "status": "confirmed",
  "join_url": "https://example.com/join"
}
```
- Used by screen: Future Event Detail registration state, My Registration Test, Join Link Visibility Test
- Current status: Planned / Placeholder

## Admin/Attendees

### GET /api/v1/events/{id}/attendees
- Auth requirement: Admin/Coordinator required
- Request body: None
- Response body:
```json
{
  "attendees": [
    {
      "name": "NITKSAA Member",
      "email": "member@example.com",
      "status": "confirmed"
    }
  ]
}
```
- Used by screen: Future Admin attendee table
- Current status: Planned / Placeholder

### GET /api/v1/events/{id}/attendees/export
- Auth requirement: Admin/Coordinator required
- Request body: None
- Response body: `text/csv` attendee export stream
- Used by screen: Future Admin attendee export action
- Current status: Planned / Placeholder

### Protected admin/event endpoints
- Method: Varies by endpoint
- Path: Protected admin/event endpoints
- Auth requirement: Admin/Coordinator required
- Request body: Varies by endpoint
- Response body:
```json
{
  "detail": "forbidden"
}
```
- Used by screen: Developer Diagnostics > Admin / Attendees > Admin Role Guard Test
- Current status: Planned / Placeholder

## Notifications/Audit

### Registration confirmation email
- Method: Triggered by POST
- Path: /api/v1/events/{id}/register
- Auth requirement: Backend JWT required
- Request body: Registration request body
- Response body:
```json
{
  "confirmation_email_sent": true
}
```
- Used by screen: Future Registration confirmation screen, Confirmation Email Test
- Current status: Planned / Placeholder

### GET /api/v1/dev/diagnostics/audit or future admin audit endpoint
- Auth requirement: Admin/dev required
- Request body: None
- Response body:
```json
{
  "entries": [
    {
      "action": "registration.created",
      "actor": "member@example.com",
      "created_at": "2026-06-03T10:00:00Z"
    }
  ]
}
```
- Used by screen: Developer Diagnostics > Admin / Attendees > Audit Trail Test
- Current status: Planned / Placeholder
