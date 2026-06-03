# Backend Auth API

This document covers the frontend-facing authentication and health endpoints used by the Flutter event app.

Base URL is environment-specific. For local Flutter development the app defaults to:

- Android emulator: `http://10.0.2.2:8000`
- Other local targets: `http://127.0.0.1:8000`

The Flutter app can override this with `BACKEND_BASE_URL` or `DEV_BACKEND_BASE_URL` at build time.

## Authorization

Authenticated requests use a backend-issued JWT in the HTTP `Authorization` header:

```http
Authorization: Bearer <backend_access_token>
```

The backend access token is returned by `POST /api/v1/auth/firebase` after a Firebase ID token is verified and exchanged.

## GET /api/v1/health

Checks API availability and database connectivity.

### Request

```http
GET /api/v1/health
```

No authentication is required.

### Response

```json
{
  "status": "ok",
  "version": "1.0.0",
  "env": "development",
  "db": "ok"
}
```

If the API process is healthy but database validation fails, `db` contains an error string:

```json
{
  "status": "ok",
  "version": "1.0.0",
  "env": "development",
  "db": "error: connection refused"
}
```

## POST /api/v1/auth/firebase

Exchanges a fresh Firebase ID token for a backend JWT session.

### Request

```http
POST /api/v1/auth/firebase
Content-Type: application/json
```

```json
{
  "token": "firebase_id_token"
}
```

### Success Response

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

For non-alumni Firebase users, `user_type` is `other`, and `ref_id` and `graduation_year` are `null`.

### Error Cases

- `400 firebase_uid_missing`: verified Firebase token did not include a UID.
- `400 email_missing`: verified Firebase token did not include an email address.
- `403 account_suspended`: matching event user exists but is suspended.
- `422 Unprocessable Entity`: request body is missing `token` or token is empty.
- `401` or `403`: Firebase token verification failed, depending on middleware failure mapping.
- `500`: unexpected server or database error.

## GET /api/v1/auth/me

Validates the backend JWT and returns the current backend user profile.

### Request

```http
GET /api/v1/auth/me
Authorization: Bearer <backend_access_token>
```

### Success Response

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

### Error Cases

- `401`: missing, malformed, expired, or invalid bearer token.
- `403`: authenticated user is not allowed to continue, if rejected by auth middleware.
- `500`: unexpected server or database error.

## Frontend Usage Notes

The Flutter auth flow is:

1. Sign in with Firebase using Google or email/password.
2. Request a fresh Firebase ID token.
3. Call `POST /api/v1/auth/firebase` with `{ "token": "<firebase_id_token>" }`.
4. Store the returned backend `access_token` as the app session token.
5. Immediately call `GET /api/v1/auth/me` with `Authorization: Bearer <access_token>` to validate the backend session.
6. On app startup, load the stored backend token and revalidate it with `/auth/me`.
7. On logout, clear the stored backend session and sign out from Firebase.

Frontend route guards should treat Firebase sign-in alone as insufficient. A user is authenticated only when the backend JWT exists and `/api/v1/auth/me` has validated it.
