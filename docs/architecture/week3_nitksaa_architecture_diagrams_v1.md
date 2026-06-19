# NITKSAA Event Platform — Architecture Diagrams v1

**Version:** 1.0  
**Date:** 2026-06-19  
**Scope:** Week 1 → Week 3  
**Syntax:** Mermaid (render at mermaid.live or in any Mermaid-compatible viewer)  
**Source document:** `docs/architecture/nitksaa_complete_architecture_v1.md`

---

## Diagram Index

| ID | Title | Section |
|---|---|---|
| D1 | System Overview | A |
| D2 | Authentication Flow — Full Sequence | B |
| D3 | Authentication — Identity Relationships | B |
| D4 | Events DB — Entity Relationship | C |
| D5 | Alumni DB — Usage Diagram | D |
| D6 | Registration Flow — Sequence Diagram | E |
| D7 | Registration Flow — State Machine | E |
| D8 | Join Link Security Rules | F |
| D9 | Email Flow — Sequence Diagram | G |
| D10 | Audit Log — Event Flow | H |
| D11 | Developer Diagnostics — Hierarchy | I |
| D12 | Flutter App — Layer Architecture | J |
| D13 | Admin Portal — Layer Architecture | K |
| D14 | API Request Flow — End-to-End | L |
| D15 | Migration Timeline | M |
| D16 | Week 4 Dependency Graph | P |

---

## D1 — System Overview

```mermaid
graph TB
    subgraph Clients["Client Layer"]
        Flutter["Flutter App\napps/event_app/\n(Mobile / Web)"]
        Admin["React Admin Portal\nadmin/event_admin/\n(Web)"]
    end

    subgraph Auth["External Auth"]
        Firebase["Firebase Authentication\n(Google / Email+Password)"]
    end

    subgraph Backend["FastAPI Backend\nbackend/app/ (uvicorn :8000)"]
        direction TB
        Routers["Routers\nauth · events · admin_events\nregistrations · alumni\ndev_diagnostics · health"]
        Services["Services\nregistration · alumni · email\naudit · events · slug"]
        Repos["Repositories\nregistration · event · checkin"]
    end

    subgraph Databases["Database Layer (PostgreSQL)"]
        EventsDB[("events_db\n──────────\nevents\nsessions\nregistrations\ncheck_ins\nevent_users\nevent_members\nevent_content\nevent_audit_log\nnotifications")]
        AlumniDB[("alumni_db\n──────────\nalumni\n(read-only)")]
    end

    Flutter -->|"Firebase SDK\nGoogle / Email"| Firebase
    Admin -->|"Firebase SDK\nEmail"| Firebase
    Firebase -->|"idToken"| Flutter
    Firebase -->|"idToken"| Admin
    Flutter -->|"REST / JWT\nlocalhost:8000"| Backend
    Admin -->|"REST / JWT\nlocalhost:8000"| Backend
    Backend -->|"asyncpg"| EventsDB
    Backend -->|"asyncpg (read-only)"| AlumniDB
```

---

## D2 — Authentication Flow (Full Sequence)

```mermaid
sequenceDiagram
    participant U as User
    participant C as Client (Flutter/Admin)
    participant FB as Firebase Auth
    participant BE as FastAPI Backend
    participant EDB as events_db
    participant ADB as alumni_db

    U->>C: Enter email + password (or tap Google)
    C->>FB: Firebase signInWithEmailAndPassword()
    FB-->>C: idToken (Firebase JWT, ~1 hour)

    C->>BE: POST /api/v1/auth/firebase\n{"token": "<idToken>"}
    BE->>FB: verify_firebase_token(idToken)
    FB-->>BE: verified claims {firebase_uid, email, name}

    BE->>ADB: SELECT * FROM alumni WHERE email = $1
    ADB-->>BE: alumni row (or null)

    alt Alumni found
        BE->>BE: user_type = "alumni"\nref_id = alumni.alumni_id\ngraduation_year = alumni.graduationyear
    else Not found
        BE->>BE: user_type = "other"\nref_id = null
    end

    BE->>EDB: INSERT INTO event_users ... ON CONFLICT DO UPDATE last_login
    EDB-->>BE: event_users row {is_suspended}

    alt is_suspended = true
        BE-->>C: 403 account_suspended
    else Not suspended
        BE->>BE: make_access_token({firebase_uid, email, user_type, ref_id, ...})
        BE-->>C: 200 {access_token, user_type, ref_id, graduation_year, ...}
    end

    C->>C: Store access_token in localStorage / SecureStorage
    C->>BE: GET /api/v1/auth/me\nAuthorization: Bearer <access_token>
    BE-->>C: 200 {firebase_uid, email, user_type, ref_id, ...}
```

---

## D3 — Authentication — Identity Relationships

```mermaid
erDiagram
    FIREBASE_AUTH {
        string firebase_uid PK
        string email
        string idToken "short-lived, ~1hr"
    }

    EVENT_USERS {
        string firebase_uid PK
        string email
        string user_type "alumni | other"
        string ref_id "= alumni.alumni_id (nullable)"
        int graduation_year
        boolean is_suspended
        timestamp last_login
    }

    ALUMNI_DB_ALUMNI {
        string alumni_id PK "= event_users.ref_id"
        string email
        string fullname
        string registrationstatus "Active | Self-Verified | ..."
    }

    BACKEND_JWT {
        string firebase_uid
        string user_type
        string ref_id
        int graduation_year
        int exp "now + 480 min"
    }

    FIREBASE_AUTH ||--o| EVENT_USERS : "upsert on login (firebase_uid)"
    FIREBASE_AUTH ||--o| ALUMNI_DB_ALUMNI : "lookup by email"
    ALUMNI_DB_ALUMNI ||--o| EVENT_USERS : "alumni_id → ref_id"
    EVENT_USERS ||--|| BACKEND_JWT : "claims copied to JWT payload"
```

---

## D4 — Events DB Entity Relationship Diagram

```mermaid
erDiagram
    EVENTS {
        int event_id PK
        text slug UK
        text title
        varchar status "draft|published|cancelled|completed"
        boolean is_virtual
        text virtual_url "NEVER in public API"
        int capacity "NULL = unlimited"
        timestamptz registration_opens_at
        timestamptz registration_closes_at
        boolean show_attendee_list
        varchar created_by_firebase_uid FK
    }

    SESSIONS {
        int session_id PK
        int event_id FK
        text title
        text speaker_name
        int sort_order
    }

    EVENT_USERS {
        varchar firebase_uid PK
        text email
        varchar user_type "alumni|other"
        text ref_id "alumni_id"
        boolean is_suspended
    }

    EVENT_MEMBERS {
        int event_id PK-FK
        varchar firebase_uid PK-FK
        varchar role
        varchar status "active"
    }

    REGISTRATIONS {
        int registration_id PK
        int event_id FK
        varchar firebase_uid FK
        text ref_id "alumni_id"
        varchar status "registered|cancelled"
        text registration_number "NITKSAA-YYYY-NNNNNN"
        text fullname_snapshot
        text email "email_snapshot"
        text phone "phone_snapshot"
        int batch_year_snapshot
        text branch_snapshot
        varchar confirmation_email_status "pending|sent|failed|skipped"
        text notes "= attendee_note in API"
    }

    CHECK_INS {
        int checkin_id PK
        int registration_id FK
        int event_id FK
        varchar scanned_by FK
        varchar result "success|duplicate|invalid"
    }

    EVENT_CONTENT {
        int content_id PK
        int event_id FK
        varchar content_type "recording|gallery"
        text url
    }

    EVENT_AUDIT_LOG {
        bigint log_id PK
        varchar actor_uid
        text event_type
        text entity_type
        int entity_id
        jsonb context "NO PII in context"
    }

    NOTIFICATIONS {
        bigint notification_id PK
        varchar firebase_uid
        text event_type
        boolean is_read
    }

    EVENTS ||--o{ SESSIONS : "has sessions"
    EVENTS ||--o{ EVENT_MEMBERS : "has members"
    EVENTS ||--o{ REGISTRATIONS : "has registrations"
    EVENTS ||--o{ CHECK_INS : "has check-ins"
    EVENTS ||--o{ EVENT_CONTENT : "has content"
    EVENTS }o--|| EVENT_USERS : "created_by"
    EVENT_USERS ||--o{ EVENT_MEMBERS : "is member of"
    EVENT_USERS ||--o{ REGISTRATIONS : "registers"
    EVENT_USERS ||--o{ CHECK_INS : "scans"
    REGISTRATIONS ||--o{ CHECK_INS : "generates"
```

---

## D5 — Alumni DB Usage

```mermaid
graph LR
    subgraph EventsPlatform["Events Platform"]
        AuthService["auth.py\nfind_alumni_by_email(email)"]
        AlumniService["alumni_service.py\nget_alumni_profile_by_ref_id(ref_id)"]
        RegService["registration_service.py\n(snapshot capture)"]
    end

    subgraph AlumniDB["alumni_db.alumni (read-only)"]
        AlumniTable["alumni\n──────────────\nalumni_id  ← ref_id\nfullname\nemail\nphone\ngraduationyear ← batch_year\nbranch\nregistrationstatus ← is_active\nfirebase_uid"]
    end

    subgraph SnapshotFields["Snapshot Fields (copied at registration)"]
        SS["fullname_snapshot\nbatch_year_snapshot\nbranch_snapshot\nemail (email_snapshot)\nphone (phone_snapshot)"]
    end

    AuthService -->|"WHERE email = $1"| AlumniTable
    AlumniTable -->|"alumni_id → event_users.ref_id"| AuthService
    AlumniService -->|"WHERE alumni_id = ref_id"| AlumniTable
    AlumniTable -->|"AlumniProfileResponse"| AlumniService
    RegService -->|"via AlumniService"| AlumniTable
    AlumniTable -->|"immutable snapshot at INSERT"| SnapshotFields
```

---

## D6 — Registration Flow — Full Sequence

```mermaid
sequenceDiagram
    participant A as Alumni (Flutter)
    participant BE as FastAPI Backend
    participant EDB as events_db
    participant ADB as alumni_db
    participant EMAIL as Email Service
    participant AUDIT as Audit Log

    A->>BE: GET /api/v1/alumni/me\nAuthorization: Bearer <jwt>
    BE->>ADB: SELECT * FROM alumni WHERE alumni_id = ref_id
    ADB-->>BE: alumni profile
    BE-->>A: {ref_id, fullname, email, batch_year, branch, is_active}

    A->>BE: GET /api/v1/events/{id}/registration-eligibility
    BE->>EDB: SELECT event, COUNT(registered) WHERE event_id=$1
    EDB-->>BE: event row + registered_count
    BE-->>A: {eligibility_status: "eligible", registered_count, capacity}

    A->>BE: POST /api/v1/events/{id}/register\n{"attendee_note": "..."}
    BE->>BE: Validate user_type=alumni, ref_id exists
    BE->>ADB: SELECT registrationstatus WHERE alumni_id = ref_id
    ADB-->>BE: registrationstatus = "Active"

    BE->>EDB: BEGIN TRANSACTION
    BE->>EDB: SELECT events WHERE event_id=$1 FOR UPDATE
    EDB-->>BE: event row (locked)
    BE->>BE: Check: published? dates? capacity?
    BE->>EDB: SELECT registrations WHERE event_id=$1 AND firebase_uid=$2 AND status='registered'
    EDB-->>BE: no active registration

    BE->>EDB: INSERT INTO registrations (...)
    EDB-->>BE: registration_id = 5
    BE->>EDB: UPDATE registrations SET registration_number='NITKSAA-2026-000005'
    BE->>EDB: COMMIT

    Note over BE,EDB: Registration is durable here

    BE->>EMAIL: send_confirmation_email(email, fullname, event_title, join_url)
    EMAIL-->>BE: EmailResult(status="sent", sent_at=...)
    BE->>EDB: UPDATE registrations SET confirmation_email_status='sent'

    BE->>AUDIT: emit('registration_created', 'registration', registration_id)
    AUDIT-->>BE: (fire and forget)

    BE-->>A: 201 RegistrationResponse\n{registration_number, status: "registered", join_url, event: {...}}
```

---

## D7 — Registration State Machine

```mermaid
stateDiagram-v2
    [*] --> EligibilityCheck : User opens event

    EligibilityCheck --> Eligible : eligibility_status = "eligible"
    EligibilityCheck --> AlreadyRegistered : eligibility_status = "already_registered"
    EligibilityCheck --> EventFull : eligibility_status = "full"
    EligibilityCheck --> RegistrationClosed : eligibility_status = "closed"
    EligibilityCheck --> NotOpenYet : eligibility_status = "not_open_yet"
    EligibilityCheck --> Ineligible : eligibility_status = "ineligible"

    Eligible --> RegisterRequest : POST /register

    RegisterRequest --> Registered : HTTP 201\nstatus = "registered"
    RegisterRequest --> Error403 : alumni_only / alumni_not_active
    RegisterRequest --> Error404 : event_not_found
    RegisterRequest --> Error409 : already_registered / event_full\nregistration_closed / not_open_yet

    Registered --> JoinUrlVisible : is_virtual=true AND published
    Registered --> JoinUrlNull : is_virtual=false OR not published
    Registered --> Cancelled : PATCH .../status (future)

    Cancelled --> Eligible : Re-registration allowed\n(partial unique index allows it)

    state "Blocked Paths" as Blocked {
        AlreadyRegistered
        EventFull
        RegistrationClosed
        NotOpenYet
        Ineligible
    }
```

---

## D8 — Join Link Security Rules

```mermaid
flowchart TD
    Req["Request for join_url"]

    Req --> Q1{"Is this a\npublic API?"}
    Q1 -->|Yes| FAIL1["null\nPublic APIs never return join_url\nSchema projection at Pydantic level"]
    Q1 -->|No| Q2{"User is\nauthenticated\n(valid JWT)?"}
    Q2 -->|No| FAIL2["null\n401 Unauthorized"]
    Q2 -->|Yes| Q3{"registration.status\n= 'registered'?"}
    Q3 -->|No| FAIL3["null\nCancelled or no registration"]
    Q3 -->|Yes| Q4{"event.is_virtual\n= true?"}
    Q4 -->|No| FAIL4["null\nPhysical event\n(no join link)"]
    Q4 -->|Yes| Q5{"event.status\n= 'published'?"}
    Q5 -->|No| FAIL5["null\nDraft or cancelled event"]
    Q5 -->|Yes| OK["return event.virtual_url\n✓ Join link visible"]

    style OK fill:#22c55e,color:#fff
    style FAIL1 fill:#ef4444,color:#fff
    style FAIL2 fill:#ef4444,color:#fff
    style FAIL3 fill:#ef4444,color:#fff
    style FAIL4 fill:#ef4444,color:#fff
    style FAIL5 fill:#ef4444,color:#fff
```

---

## D9 — Email Flow — Sequence Diagram

```mermaid
sequenceDiagram
    participant RS as registration_service
    participant DB as events_db (registrations)
    participant ES as email_service
    participant SMTP as SMTP / Logger

    RS->>DB: INSERT registration
    DB-->>RS: registration_id = N
    RS->>DB: UPDATE registration_number = 'NITKSAA-YYYY-NNNNNN'
    RS->>DB: COMMIT TRANSACTION

    Note over RS,DB: Registration is durable — never rolls back

    RS->>ES: send_confirmation_email(email, fullname, event_title, join_url)

    alt EMAIL_MODE = "log"
        ES->>SMTP: logger.info("[email/log] confirmation to=...")
        SMTP-->>ES: OK
        ES-->>RS: EmailResult(status="sent", sent_at=now)
    else EMAIL_MODE = "send"
        ES->>SMTP: smtplib.SMTP(host, port)\nstarttls → login → sendmail
        alt SMTP success
            SMTP-->>ES: OK
            ES-->>RS: EmailResult(status="sent", sent_at=now)
        else SMTP failure
            SMTP-->>ES: Exception
            ES-->>RS: EmailResult(status="failed", error=str(exc))
        end
    else Unknown mode
        ES-->>RS: EmailResult(status="skipped")
    end

    RS->>DB: UPDATE registrations SET\n  confirmation_email_status = result.status\n  confirmation_email_sent_at = result.sent_at\n  updated_at = now()

    Note over RS: Email failure NEVER raises\nNEVER rolls back registration
```

---

## D10 — Audit Log — Event Flow

```mermaid
sequenceDiagram
    participant RS as registration_service
    participant AS as audit_service.emit()
    participant DB as event_audit_log

    RS->>RS: COMMIT registration transaction

    RS->>AS: emit(actor_uid, "registration_created",\n"registration", registration_id,\ncontext={registration_number, event_id})
    AS->>DB: INSERT INTO event_audit_log\n(actor_uid, event_type, entity_type, entity_id, context)
    DB-->>AS: OK

    RS->>RS: send_confirmation_email(...)
    RS->>AS: emit(actor_uid, "confirmation_email_sent",\n"registration", registration_id,\ncontext={email_status: "sent"})
    AS->>DB: INSERT INTO event_audit_log (...)
    DB-->>AS: OK

    Note over AS: emit() NEVER raises\nErrors swallowed with [audit] log prefix
    Note over DB: context JSONB — NO firebase_uid,\nNO email, NO phone, NO join_url
```

---

## D11 — Developer Diagnostics — Hierarchy

```mermaid
graph TD
    DD["Developer Diagnostics Screen\n(kDebugMode only)"]

    DD --> GEN["General"]
    DD --> AUTH["Authentication"]
    DD --> DBCat["Database"]
    DD --> EVENTS["Event Management"]
    DD --> REG["Registration"]
    DD --> ADMIN["Admin / Attendees"]
    DD --> ALUMNICAT["Alumni Database"]

    GEN --> G1["Foundation Status\nFirebase, Hive, Router"]
    GEN --> G2["Logger Test\nEmit test logs"]
    GEN --> G3["Theme Control\nLight / Dark / System"]
    GEN --> G4["Network Test\nGET /health"]
    GEN --> G5["App Performance\nNotes"]
    GEN --> G6["Debug Tools\nExport report, Clear cache"]

    AUTH --> A1["Firebase Token Test\nCapture idToken preview"]
    AUTH --> A2["Backend Auth Test\nPOST /auth/firebase"]
    AUTH --> A3["/auth/me Test\nGET /auth/me"]

    DBCat --> D1["Event Users Test\nInspect event_users table"]
    DBCat --> D2["Database Tables Test\nList tables + row counts"]

    EVENTS --> E1["Events API Test ⏳"]
    EVENTS --> E2["Event Detail API Test ⏳"]
    EVENTS --> E3["Event Creation API Test ⏳"]
    EVENTS --> E4["Event Publish Test ⏳"]

    REG --> W3["Week 3 UX Showcase\n16 sections (§0–§12)"]
    REG --> R1["Registration Flow Test\n13-check backend suite"]
    REG --> R2["My Registration Test"]
    REG --> R3["Capacity Guard Test"]
    REG --> R4["Confirmation Email Status"]
    REG --> R5["Join Link Visibility Test"]

    ADMIN --> ADM1["Attendee List API Test ⏳"]
    ADMIN --> ADM2["Attendee Export Test ⏳"]
    ADMIN --> ADM3["Admin Role Guard Test ⏳"]
    ADMIN --> ADM4["Audit Trail Test ⏳"]

    ALUMNICAT --> AL1["Search by Email\nGET /alumni/search?email="]
    ALUMNICAT --> AL2["Search by Prefix\nGET /alumni/search-prefix?prefix="]
    ALUMNICAT --> AL3["Lookup by Alumni ID\nGET /alumni/{alumni_id}"]
    ALUMNICAT --> AL4["Login Mapping Trace\nGET /alumni/login-trace?email="]

    AL4 --> DIAG1["alumni_db lookup"]
    AL4 --> DIAG2["event_users lookup"]
    AL4 --> DIAG3["PASS / FAIL diagnosis"]

    W3 --> S0["§0 Run All (13 checks)"]
    W3 --> S1["§1 Alumni Autofill"]
    W3 --> S2["§2 Eligibility"]
    W3 --> S3["§3 Registration Action"]
    W3 --> S4["§4 Confirmation Preview"]
    W3 --> S5["§5 My Registration"]
    W3 --> S6["§6 My Registrations List"]
    W3 --> S7["§7 Negative Gallery"]
    W3 --> S8a["§8a Join Link Matrix"]
    W3 --> S8b["§8b Public Leak Check"]
    W3 --> S9["§9 Audit Trail"]
    W3 --> S10["§10 Email Demo"]
    W3 --> S11["§11 Snapshot Demo"]
    W3 --> S12["§12 DB Rules"]
```

---

## D12 — Flutter App — Layer Architecture

```mermaid
graph TB
    subgraph Flutter["Flutter App — apps/event_app/"]
        direction TB

        subgraph Config["Config / Environment"]
            ENV["dart-define constants\nDEV_DIAGNOSTICS_EMAIL\nDEV_DIAGNOSTICS_PASSWORD\nBACKEND_BASE_URL\nDEV_TEST_EVENT_ID"]
        end

        subgraph Core["Core Layer"]
            Routes["go_router\napp_router.dart\napp_routes.dart\nroute_guards.dart"]
            State["Riverpod Providers\napp_state.dart"]
            Logger["AppLogger\nlogging service"]
        end

        subgraph AuthFeature["Auth Feature\n(features/auth/)"]
            LoginScreen["LoginScreen\n/login"]
            AuthSession["AuthSessionStore\n(SecureStorage / Hive)"]
            GoogleInit["GoogleSignInInitializer"]
        end

        subgraph EventsFeature["Events Feature\n(features/events/)"]
            EventList["EventListScreen\n/events\n(Upcoming/Past tabs)"]
            EventDetail["EventDetailScreen\n/events/{id}\n(Public — no auth required)"]
        end

        subgraph DevFeature["Developer Diagnostics\n(features/developer/)\nkDebugMode only"]
            DiagScreen["DeveloperDiagnosticsScreen\n/developer"]
        end

        subgraph HomeFeature["Home Feature\n(features/home/)"]
            HomeScreen["HomeScreen\n/home"]
        end

        subgraph Shared["Shared Layer"]
            Widgets["Shared Widgets\nDiagnosticStatusBadge\nBackendApiDetailsCard\n_jsonBlock"]
            DevDio["devDio\n(Dio instance for dev use)"]
        end

        ENV --> Core
        Core --> AuthFeature
        Core --> EventsFeature
        Core --> DevFeature
        Core --> HomeFeature
        AuthFeature --> Shared
        EventsFeature --> Shared
        DevFeature --> Shared
    end

    subgraph External["External"]
        FirebaseSDK["Firebase SDK\n(Auth)"]
        BackendAPI["FastAPI Backend\nlocalhost:8000"]
    end

    AuthFeature -->|"signIn / Google"| FirebaseSDK
    AuthFeature -->|"POST /auth/firebase\nGET /auth/me"| BackendAPI
    EventsFeature -->|"GET /events/public\nGET /events/public/{id}"| BackendAPI
    DevFeature -->|"All endpoints\n+ /dev/diagnostics/*"| BackendAPI
```

---

## D13 — Admin Portal — Layer Architecture

```mermaid
graph TB
    subgraph AdminPortal["React Admin Portal — admin/event_admin/"]
        direction TB

        subgraph AuthLayer["Auth Layer"]
            AuthProvider["AuthProvider.jsx\nFirebase session + backend JWT"]
            RequireAuth["RequireAuth.jsx\nRoute guard"]
            SessionStorage["sessionStorage.js\nlocalStorage keys"]
        end

        subgraph APILayer["API Layer"]
            APIClient["apiClient.js\nFetch wrapper\nAuto-attaches Bearer JWT\n401/403 → redirect /login"]
            AuthAPI["authApi.js\nexchangeFirebaseToken()\ngetCurrentUser()"]
            EventsAPI["eventsApi.js\nlistEvents(), createEvent()\nupdateEvent(), updateStatus()"]
        end

        subgraph PagesLayer["Pages"]
            LoginPage["LoginPage\nFirebase sign-in form"]
            Dashboard["DashboardPage\nHealth card"]
            EventsPage["EventsPage\nEvent table + actions\n(publish/cancel buttons)"]
            EventForm["EventFormPage\nCreate + Edit form"]
            Attendees["AttendeesPage\nWeek 4 pending"]
            Registrations["RegistrationsPage\nWeek 4 pending"]
            Settings["SettingsPage\nFirebase config display"]
        end

        subgraph Layout["Layout"]
            Shell["Shell Layout\nSidebar + Header"]
        end

        AuthProvider --> SessionStorage
        RequireAuth --> AuthProvider
        AuthAPI --> APIClient
        EventsAPI --> APIClient
        PagesLayer --> APILayer
        PagesLayer --> AuthLayer
        Shell --> PagesLayer
    end

    subgraph Ext["External"]
        FirebaseSDK2["Firebase SDK\n(Auth)"]
        BE2["FastAPI Backend\nlocalhost:8000"]
    end

    AuthProvider -->|"signInWithEmailAndPassword"| FirebaseSDK2
    APIClient -->|"REST calls"| BE2
```

---

## D14 — API Request Flow — End-to-End

```mermaid
sequenceDiagram
    participant C as Client (Flutter / Admin)
    participant MW as FastAPI Middleware\n(auth.py get_current_user)
    participant R as Router Handler
    participant S as Service Layer
    participant Repo as Repository
    participant DB as events_db

    C->>MW: HTTP Request\nAuthorization: Bearer <jwt>
    MW->>MW: Decode JWT (HS256, SECRET_KEY)
    MW->>MW: Validate expiry, extract claims

    alt Token invalid
        MW-->>C: 401 Unauthorized
    else Token valid
        MW->>R: Inject user dict {firebase_uid, user_type, ref_id, ...}
        R->>S: Call service function(event_id, user, body)
        S->>S: Validate business rules\n(alumni check, event state, etc.)

        alt Validation fails
            S-->>R: raise HTTPException(4xx, detail="...")
            R-->>C: 4xx Error Response
        else Validation passes
            S->>Repo: CRUD operation
            Repo->>DB: SQL query (asyncpg)
            DB-->>Repo: Result rows
            Repo-->>S: Python dict / list
            S-->>R: Pydantic schema object
            R-->>C: 2xx JSON Response
        end
    end
```

---

## D15 — Migration Timeline

```mermaid
gantt
    title events_db Migration History
    dateFormat  YYYY-MM-DD
    axisFormat  %b %Y

    section Week 1 / Foundation
    001 Create events table          :done, m001, 2026-05-01, 1d
    002 Create sessions table        :done, m002, after m001, 1d
    003 event_users + event_members  :done, m003, after m002, 1d
    004 registrations + check_ins    :done, m004, after m003, 1d

    section Week 2
    005 event_content                :done, m005, 2026-05-15, 1d
    006 audit_log + notifications    :done, m006, after m005, 1d
    007 add show_attendee_list       :done, m007, after m006, 1d

    section Week 3
    008 Week 3 registration align    :done, m008, 2026-06-10, 1d
    009 audit_log context JSONB      :done, m009, after m008, 1d
```

---

## D16 — Week 4 Dependency Graph

```mermaid
graph TD
    W3["Week 3 Complete\nBackend + Diagnostics"]

    W3 --> A1["Phase 1: Admin Backend\nGET /events/id/attendees\nGET /events/id/attendees/export"]
    W3 --> F1["Phase 3: Flutter Registration UI\n(Can start in parallel with Phase 1)"]

    A1 --> A2["Phase 2: Admin Attendee UI\nAttendeesPage.jsx\nSearch + Filter + CSV Export"]

    F1 --> F2["Flutter Confirmation Screen\nMy Registrations Screen"]
    F2 --> F3["Flutter Join Link Display\nEvent Detail post-registration"]

    A2 --> B1["Phase 4: Beta Hardening"]
    F3 --> B1

    B1 --> B2["Staging Deployment"]
    B2 --> B3["Staff Walkthrough\nDemo Script\nKnown Issues List"]
    B3 --> BETA["Beta Release\nTarget: Jun 30, 2026"]

    style W3 fill:#22c55e,color:#fff
    style BETA fill:#3b82f6,color:#fff
```

---

*All textual descriptions for these diagrams are in: `docs/architecture/nitksaa_complete_architecture_v1.md`*
