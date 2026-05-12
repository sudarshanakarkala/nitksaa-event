# NITKSAA Event Platform — Customer Architecture Flow

**Version:** 0.1  
**Status:** Draft for Customer Review  
**Project:** NITKSAA Event Platform  
**Repo:** `nitksaa-event`  
**Current Phase:** Sprint 1 — Foundation Setup

---

## 1. Executive Summary

NITKSAA Event Platform is a modern event management system for alumni, community, professional, and institutional events.

The platform will support:

- Event discovery
- Attendee registration
- QR badge generation
- QR-based check-in
- Event announcements
- Notifications
- Admin operations
- Payments in future phases
- Reporting and analytics in future phases

The system is designed to be secure, scalable, maintainable, and configuration-driven.

---

## 2. High-Level Platform Architecture

```text
┌────────────────────────────────────────────────────────────┐
│                    NITKSAA EVENT PLATFORM                  │
└────────────────────────────────────────────────────────────┘

              ┌──────────────────────────────┐
              │      Event App - Flutter      │
              │      iOS + Android            │
              └───────────────┬──────────────┘
                              │
                              │ Firebase Auth Token
                              │ REST API Calls
                              ▼
              ┌──────────────────────────────┐
              │        Backend API            │
              │        FastAPI / Cloud Run    │
              └───────────────┬──────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Firebase Auth   │  │ PostgreSQL       │  │ Firebase / GCP   │
│ Login Identity  │  │ Business Data    │  │ Realtime + Push  │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

---

## 3. Applications in the Platform

### 3.1 Event App — Flutter

The Event App is the attendee-facing and volunteer-facing mobile application.

Supported platforms:

- Android
- iOS

Primary users:

- Alumni attendees
- Event participants
- Volunteers
- Organizers with mobile access

Main features:

- Login / signup
- Event list
- Event details
- Registration
- QR badge
- Check-in scanner for volunteers
- My registrations
- Profile and settings
- Notifications
- Light/dark theme support

---

### 3.2 Admin Portal — Web

The Admin Portal will be used by event organizers and administrators.

Recommended technology:

- React
- TypeScript
- Tailwind CSS
- Firebase Auth
- REST API integration

Primary users:

- Admin
- Event manager
- Finance admin
- Volunteer coordinator

Main features:

- Event creation
- Event publishing
- Registration management
- Attendee search
- Payment monitoring
- Check-in dashboard
- Reports
- Configuration management

---

### 3.3 Backend API

The Backend API will act as the secure business layer.

Recommended technology:

- FastAPI
- Python
- Cloud Run
- PostgreSQL
- Firebase Admin SDK

Responsibilities:

- Verify Firebase Auth tokens
- Enforce role-based access
- Manage event data
- Manage registrations
- Generate QR tokens
- Validate QR check-ins
- Handle payments
- Store audit logs
- Provide REST APIs to all clients

---

## 4. Data Flow Overview

```text
User opens app
   ↓
Firebase Authentication
   ↓
User receives Firebase ID token
   ↓
App calls Backend API with token
   ↓
Backend verifies token using Firebase Admin SDK
   ↓
Backend checks user role and access
   ↓
Backend reads/writes business data in PostgreSQL
   ↓
Backend returns response to app
```

---

## 5. Authentication Flow

```text
┌─────────────┐
│ User opens  │
│ Event App   │
└──────┬──────┘
       │
       ▼
┌────────────────────────┐
│ Login with Email/Google │
└──────┬─────────────────┘
       │
       ▼
┌────────────────────────┐
│ Firebase Authentication │
└──────┬─────────────────┘
       │
       ▼
┌────────────────────────┐
│ Firebase ID Token       │
└──────┬─────────────────┘
       │
       ▼
┌────────────────────────┐
│ Backend verifies token  │
└──────┬─────────────────┘
       │
       ▼
┌────────────────────────┐
│ User allowed into app   │
└────────────────────────┘
```

---

## 6. Event Discovery Flow

```text
Attendee opens Event App
   ↓
App requests event list from Backend API
   ↓
Backend fetches published events from PostgreSQL
   ↓
App displays upcoming and past events
   ↓
Attendee opens event detail
   ↓
App shows date, venue, agenda, description, and registration CTA
```

---

## 7. Registration Flow

### 7.1 Free Event Registration

```text
Attendee selects event
   ↓
Clicks Register
   ↓
Fills registration form
   ↓
App submits registration to Backend API
   ↓
Backend validates form and user
   ↓
Backend creates registration record
   ↓
Backend generates signed QR badge token
   ↓
App displays confirmation and QR badge
```

---

### 7.2 Paid Event Registration — Future Phase

```text
Attendee selects paid event
   ↓
Fills registration form
   ↓
Backend creates pending registration
   ↓
Backend creates payment order
   ↓
App opens payment gateway checkout
   ↓
Payment success/failure returned
   ↓
Backend verifies payment
   ↓
Registration confirmed
   ↓
QR badge generated
```

---

## 8. QR Check-in Flow

```text
Volunteer logs in
   ↓
Volunteer opens Check-in Mode
   ↓
App opens QR scanner
   ↓
QR badge is scanned
   ↓
App sends QR token to Backend API
   ↓
Backend validates:
   - Event ID
   - Registration ID
   - QR signature
   - Duplicate check-in
   ↓
Backend records check-in
   ↓
App shows result:
   - Success
   - Duplicate
   - Invalid
   - Wrong event
```

---

## 9. Notification and Announcement Flow

```text
Admin creates announcement
   ↓
Backend stores announcement
   ↓
Backend sends push notification using Firebase Cloud Messaging
   ↓
Attendee receives notification
   ↓
App displays announcement
```

---

## 10. Data Storage Strategy

### 10.1 PostgreSQL — System of Record

PostgreSQL will store core business data:

- Users
- Events
- Registrations
- Payments
- QR badges
- Check-ins
- Roles
- Audit logs

### 10.2 Firebase

Firebase will be used for:

- Authentication
- Push notifications
- Remote configuration
- Crash reporting
- Analytics
- Limited real-time features

### 10.3 Important Architecture Rule

The mobile app should not directly access business data collections.

Recommended pattern:

```text
Flutter App → Backend REST API → PostgreSQL
```

Firebase should support authentication, push notifications, analytics, crash reporting, and selected real-time use cases.

---

## 11. Security Architecture

```text
┌──────────────────────┐
│ Firebase Auth         │
│ User Identity         │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Backend Auth Layer    │
│ Token Verification    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ RBAC Layer            │
│ Role + Scope Check    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Business Services     │
│ Events / Registration │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ PostgreSQL            │
│ Secure Data Storage   │
└──────────────────────┘
```

Security principles:

- Firebase Auth for identity
- Backend authorization for business access
- HTTPS only
- No secrets in mobile app code
- No direct database access from client
- Role-based access control
- Audit logging for sensitive actions
- No PII in logs
- Payment data handled only by payment gateway

---

## 12. Role-Based Access Model

| Role | Access |
|---|---|
| Super Admin | Full platform control |
| Event Manager | Create and manage assigned events |
| Finance Admin | Payments, refunds, financial reports |
| Volunteer | QR check-in for assigned events |
| Attendee | Register and attend events |

---

## 13. Theme and User Experience Direction

The app will use a clean, modern, professional design suitable for alumni and community events.

Recommended design language:

```text
Premium Professional Modern
```

Inspired by:

- Apple
- Linear
- Stripe

### Default Theme

```text
Light mode
```

Reason:

- Better readability
- Better outdoor usability
- Suitable for event check-in environments
- Friendly for alumni and general attendees

### Optional Theme

```text
Dark mode
```

Users can switch between:

- System default
- Light
- Dark

### Suggested Colors

Light theme:

```text
Background: #F7F8FA
Surface:    #FFFFFF
Primary:    #2563EB
Text:       #0E1117
Secondary:  #4A5260
Border:     #E5E8EC
```

Dark theme:

```text
Background: #0B0D10
Surface:    #14171C
Primary:    #5B8DEF
Text:       #F5F7FA
Secondary:  #9AA3B2
Border:     #252A33
```

---

## 14. Sprint 1 Foundation Flow

Current Sprint 1 focus:

```text
Firebase setup
   ↓
Flutter app bootstrap
   ↓
Firebase Core initialization
   ↓
Folder architecture
   ↓
State management setup
   ↓
Routing setup
   ↓
Theme setup
   ↓
Logger setup
   ↓
Placeholder login screen
   ↓
Clean build and commit
```

Completed so far:

- GitHub repository created
- Firebase project selected
- Android Firebase app created
- iOS Firebase app created
- Flutter app created
- Firebase Core added
- FlutterFire configured
- Firebase initialization verified
- Base app opens successfully

---

## 15. Recommended Future Architecture Evolution

### Phase 1 — Foundation and MVP

- Auth
- Event listing
- Event detail
- Free registration
- QR badge
- QR check-in
- Basic admin operations

### Phase 2 — Operational Platform

- Paid events
- Razorpay
- Sessions
- Speakers
- Resources
- Announcements
- Push notifications
- Dashboard

### Phase 3 — Production Hardening

- Audit viewer
- Advanced roles
- Refunds
- Analytics
- Security hardening
- Performance optimization

### Phase 4 — Post-October Enhancements

- Offline QR scanning
- Visual event builder
- Advanced reports
- Multi-brand configuration
- Calendar integration
- Certificate generation
- AI-assisted event operations

---

## 16. Customer-Friendly Summary

The proposed architecture separates the platform into clean layers:

```text
Mobile App
   ↓
Secure API Layer
   ↓
Business Logic
   ↓
Database and Firebase Services
```

This approach gives the customer:

- Better security
- Easier maintenance
- Faster future enhancements
- Scalable event operations
- Clean mobile experience
- Strong foundation for payments and reporting
- Ability to support multiple event formats in the future

---

## 17. Immediate Next Steps

1. Finalize Flutter folder architecture.
2. Add Riverpod, GoRouter, Dio, Hive, and Logger.
3. Create design tokens and theme system.
4. Create splash and placeholder login screens.
5. Add Firebase Auth wrapper.
6. Commit Sprint 1 foundation changes.
7. Continue with authentication implementation in Sprint 2.

---

## 18. Architecture Decision

For the NITKSAA Event Platform, the recommended decision is:

```text
Use Firebase for identity, notifications, analytics, and configuration.
Use Backend REST APIs for all business operations.
Use PostgreSQL as the primary system of record.
Use Flutter for the Event App.
Use React for the Admin Portal.
```

This balances speed, security, maintainability, and long-term scalability.
