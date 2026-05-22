# Event Platform — Architecture Review & Practical Constraints

## Context

The Event Platform direction is strong and aligns well with the broader NITKSAA digital ecosystem architecture. The current planning documents demonstrate thoughtful product thinking, modern engineering practices, and a coherent long-term vision.

The recommendations below are **not** about reducing quality or simplifying the platform into a prototype.

They are about:
- controlling operational complexity
- improving maintainability
- reducing live-event risk
- keeping the system sustainable for a 3-person team
- aligning the Event Platform with the broader ecosystem philosophy of deliberate, incremental evolution

---

# What Is Strong and Should Be Preserved

## 1. Core Technology Direction

The overall stack direction is sound and internally coherent:
- FastAPI backend
- React admin portal
- Flutter attendee app
- PostgreSQL
- Firebase identity
- Cloud Run deployment

This is a modern, maintainable architecture with good ecosystem alignment.

---

## 2. Shared Identity Model

The use of Firebase-based shared identity across the NITKSAA ecosystem is absolutely the right direction.

Keep:
- one Firebase project
- one alumni identity
- one stable `firebase_uid`
- shared auth across apps

This is one of the strongest aspects of the ecosystem architecture.

---

## 3. API-First Architecture

The strict API-driven design is correct and should remain:
- backend-controlled business logic
- no direct DB access from clients
- typed APIs
- clean frontend/backend separation

This will help long-term maintainability significantly.

---

## 4. Strong RBAC and Audit Design

The platform correctly treats:
- roles
- permissions
- payments
- admin actions
- check-ins
- exports

as auditable operational activities.

The audit and RBAC design is mature and appropriate for institutional systems.

Keep this rigor.

---

## 5. QR-Based Event Operations

QR check-in is core operational value and should remain a first-class feature.

This is one of the most practical and high-value parts of the system.

---

## 6. Payment Abstraction

The payment abstraction layer is good engineering and worth preserving.

Avoid deeply coupling the platform to a single payment provider.

---

## 7. P1 / P2 / P3 Scope Discipline

The phased delivery structure is one of the strongest parts of the Event Platform planning.

Continue enforcing:
- MVP first
- operational readiness before sophistication
- clear deferment of advanced features

---

## 8. Event-First Philosophy

The platform correctly avoids becoming:
- a social network
- a messaging system
- a community platform
- a virtual conference platform

The focus on:
- registration
- identity
- event operations
- sessions
- check-ins
- announcements
- logistics

is the correct product direction.

---

## 9. Consistency with Ecosystem Principles

The Event Platform should continue aligning with the broader NITKSAA philosophy:
- connective tissue
- structured interactions
- maintainability
- incremental evolution
- avoiding unnecessary platform sprawl

---

# Recommended Constraints & Guardrails

These constraints are intended to prevent operational overengineering during the current phase.

---

## 1. PostgreSQL Must Be the System of Record

All authoritative business data must live in PostgreSQL:
- registrations
- payments
- sessions
- check-ins
- attendees
- audit logs
- announcements

Firestore/cache/config systems may hold derived or transient data only.

No critical workflow should depend solely on Firestore or client state.

---

## 2. No Realtime Dependency for Core Flows

All critical workflows must function correctly using:
- polling
- refresh
- eventual consistency

Avoid:
- WebSocket infrastructure
- realtime-critical workflows
- realtime coupling between clients

Dashboard refresh every 15–30 seconds is sufficient initially.

---

## 3. Keep a Single Backend Service

Use:
- one FastAPI deployment
- modular internal architecture
- one operational unit

Do not split into:
- payment service
- analytics service
- notification service
- webhook service
- event service

Microservices would create unnecessary operational complexity at this stage.

---

## 4. Avoid “SaaS Platform” Thinking

We are building:
- the NITKSAA event platform

We are not yet building:
- a generalized multi-tenant event SaaS platform

Avoid premature:
- tenant abstraction
- plugin systems
- generalized workflow engines
- excessive runtime configurability

---

## 5. Keep Remote Config Cosmetic Initially

Remote Config may control:
- branding
- labels
- colors
- banners
- feature visibility

Remote Config should NOT control:
- business workflows
- payment logic
- RBAC logic
- registration rules
- backend branching behavior

---

## 6. No Offline-First Architecture

Allowed:
- limited caching
- retries
- temporary read resilience

Do NOT build:
- sync engines
- conflict resolution systems
- local-first writes
- distributed reconciliation

Temporary degraded operation is acceptable.
Full offline operation is not required initially.

---

## 7. Maintain Strict Webinar Scope

The platform manages:
- registrations
- reminders
- links
- attendance tracking
- recordings/resources

The platform should NOT become:
- Zoom
- Teams
- Hopin
- virtual conference infrastructure

Avoid:
- live chat
- breakout rooms
- embedded streaming
- virtual networking
- backstage systems

---

## 8. Keep Payments Operationally Simple

Initial payment model:
- one attendee = one registration
- one payment = one order
- one ticket = one attendee

Defer:
- coupon systems
- transfer tickets
- team registrations
- partial refunds
- complex GST workflows
- advanced reconciliation

---

## 9. Use One Unified Event Model

Avoid separate architectures for:
- webinars
- conferences
- reunions
- breakfast meetings

Use:
- one event model
- one registration model
- one session model

Differences should come from flags/configuration, not separate systems.

---

## 10. Avoid Dynamic Workflow Builders

Do not build:
- generalized approval engines
- configurable workflows
- arbitrary state-machine systems

Hardcoded operational workflows are acceptable and preferable initially.

---

## 11. Notifications Are Secondary

Priority:
1. email
2. push notifications
3. in-app notifications

No critical workflow should depend on push delivery.

---

## 12. Keep Analytics Lightweight Initially

Initial analytics should mean:
- SQL queries
- operational dashboards
- exports
- summary reporting

Do not introduce:
- analytics pipelines
- warehouse systems
- behavioral tracking infrastructure

---

## 13. Prioritize Operational Clarity Over UX Cleverness

Especially for:
- volunteers
- check-in staff
- event managers

Prefer:
- predictable flows
- obvious state transitions
- deterministic behavior
- explicit refresh/actions

Operational reliability matters more than sophisticated UI behavior.

---

## 14. Minimize Background Processing

Background jobs should be limited to:
- emails
- reminders
- webhook retries

Avoid complex asynchronous orchestration systems.

---

## 15. Limit Initial Scale Assumptions

Initial target:
- 100–3000 attendee events

Do not prematurely optimize for:
- massive concurrent scale
- enterprise multi-region deployment
- hyperscale registration spikes

---

# Recommended Decision Framework

For every new subsystem or architectural addition, ask:

> “Does this feature justify its operational and maintenance burden relative to the actual needs of NITKSAA events today?”

This should remain the primary architectural guardrail for the current phase.
