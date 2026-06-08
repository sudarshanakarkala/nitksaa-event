# Event Management App — Requirements Document

- **Version:** 1.2
- **Status:** ~~Draft for Management Review~~ **In Development**
- **Document Type:** Product & Business Requirements
- **Prepared For:** NITKSAA / Event Management Stakeholders

| Version | Changes |
|---|---|
| 1.0 | Initial draft |
| 1.1 | Removed out-of-scope section; added organisational scope, event ownership, capacity behaviour, refund rules, check-in fallback, guest registration, payment gateway note; resolved open decisions |
| 1.2 | Added requirements from S. Bharathy legacy docs (2019–2020): attendee types with configurable fields, contact person per event, guest/family co-registration, discount coupons with expiry and flat/percentage types, payment detail in attendee view, real-time ticket inventory for admins, multi-step event creation wizard, distinct Published vs Registration Open event states. Replaced removed out-of-scope section with a Scope Boundaries table mapping each capability to its correct place in the ecosystem |

---

## 1. Executive Summary

The Event Management App is ~~proposed as~~ a dedicated digital platform for managing NITKSAA and alumni-community events end to end. The platform will support event creation, public event discovery, alumni/member registration, confirmation communication, attendee management, payment handling where applicable, QR-based check-in, and post-event reporting.

The solution is intended to reduce dependency on external event platforms and provide an integrated event experience connected with the existing and planned NITKSAA digital ecosystem. It should support multiple event formats such as annual events, breakfast meetings, webinars, chapter events, reunions, conferences, Global Convention, and future community initiatives.

---

## 2. Business Objective

The primary objective is to create a secure, reliable, and manageable event platform that allows NITKSAA and authorized event teams to run professional events using a common digital system.

The platform should:

- Enable staff and authorized coordinators to create and manage events.
- Allow alumni and community members to discover events.
- Support registrations for both free and paid events.
- Provide confirmation communication after successful registration.
- Maintain accurate attendee lists and exports.
- Support check-in and attendance tracking.
- Integrate with existing NITKSAA identity and alumni data where applicable.
- Provide auditability for sensitive actions.
- Improve operational control compared to fully outsourced event platforms.

---

## 3. Product Scope

The Event Management App will consist of two primary user-facing systems:

### 3.1 Admin Portal

The Admin Portal is used by event organizers, staff, event managers, finance users, volunteers, and super admins to manage event operations.

Core responsibilities:

- Event creation and management
- Event publishing and cancellation
- Registration monitoring
- Attendee search and export
- Payment monitoring
- Refund initiation where applicable
- QR check-in monitoring
- Session and speaker management
- Announcements and resources management
- Reports and audit review
- Role-based access control

### 3.2 Event App / Event User Interface

The Event App is used by alumni, attendees, volunteers, and registered users.

Core responsibilities:

- View upcoming and past events
- View event details
- Login or sign up
- Register for events
- Complete payment for paid events
- Receive registration confirmation
- View QR badge or registration proof
- Access event-specific links after registration
- View sessions, speakers, resources, announcements, and post-event content
- Support volunteer check-in flow where authorized

---

## 4. Event Types to Support

The platform should support the following event categories:

| Event Type | Requirement |
|---|---|
| Annual events | Large-format alumni gatherings and flagship events |
| Breakfast meetings | Smaller city or chapter-based networking meetings |
| Webinars | Online events with protected join links |
| Chapter events | Region-specific alumni events |
| Reunions | Batch, branch, or group-based reunion events |
| Conferences | Multi-session or multi-track events |
| Future initiatives | New event formats configurable without major redesign |

---

## 5. Target Users and Roles

| User Role | Description | Key Needs |
|---|---|---|
| Public visitor | User who views public event information | View published events without login where allowed |
| Attendee | Registered alumni/community member attending an event | Discover, register, pay, receive confirmation, attend |
| Verified alumnus/member | User whose identity is linked to the alumni/member database | Registration autofill and verified access |
| Volunteer / check-in staff | Authorized person managing entry at event venue | Scan QR, verify attendees, handle duplicate/invalid scans |
| Event manager | Person responsible for creating and running events | Create events, manage registrations, export attendees |
| Finance admin | Person responsible for payment and refund oversight | Monitor payments, reconcile, initiate refunds |
| Super admin | Platform-level administrator | Manage roles, configuration, audit, and event governance |

**[ADD]** Access for all roles below Super Admin is scoped to an organisational unit: Global, Chapter, or Event. An Event Manager can only manage events within their assigned chapter or event scope. A Finance Admin can only view payments within their assigned scope. A Volunteer can only perform check-in for events they are explicitly assigned to. This scope model must be enforced at the backend authorization layer.

---

## 6. In-Scope Capabilities

The following capabilities are in scope for the platform.

### 6.1 Authentication and Identity

The system shall support secure login for attendees, staff, administrators, and volunteers.

Requirements:

- Support email-based login.
- Support Google sign-in where applicable.
- Support identity integration with the existing NITKSAA digital ecosystem.
- Use a common identity anchor across related NITKSAA systems where possible.
- Maintain user session securely.
- Prevent unauthorized access to restricted screens and operations.
- Support role-based access for admin, event manager, finance, volunteer, and attendee roles.

### 6.2 Public Event Discovery

The system shall allow users to view published events.

Requirements:

- Show upcoming events.
- Show past events where enabled.
- Show event title, date, type, venue or online status, and registration status.
- Allow event detail viewing for published events.
- Hide restricted information such as webinar join links until successful registration.
- Support both physical and virtual event formats.

### 6.3 Event Detail

The system shall provide a clear event detail page.

Requirements:

- Display title, description, date, time, timezone, category, and event format.
- Display venue information for physical events.
- Display online event status for virtual events.
- Display capacity and registration availability where applicable.
- Display registration deadline where applicable.
- Display speakers, schedule, sponsors, resources, and post-event links where enabled.
- Show correct registration action based on user status and event status.

### 6.4 Event Creation and Management

Authorized staff shall be able to create and manage events.

Requirements:

- Create new events.
- Edit existing events.
- Save events as draft.
- Publish events.
- Unpublish or cancel events.
- Configure physical or virtual event type.
- Configure venue or online join URL.
- Configure capacity.
- Configure registration deadline.
- Configure free or paid registration.
- Configure event status.
- View all events with relevant status indicators.
- Maintain basic audit history for event creation and publishing actions.
- **[ADD]** Each event must have a designated owner (a named user with Event Manager or higher role) recorded at creation time. The event owner is the primary point of escalation for operational issues related to that event. Co-owners may optionally be assigned.
- **[NEW — S. Bharathy docs]** Event lifecycle must support the following distinct states: Draft → Published → Registration Open → Archived / Cancelled. Publishing an event makes it visible to users but does not open registration. Opening registration is a separate deliberate action by the event manager. This allows events to be promoted publicly before registration is ready.
- **[NEW — S. Bharathy docs]** Event creators must be able to define named attendee types (e.g. Alumni, Faculty, Guest, Family) for each event. For each attendee type, the creator configures which registration fields are shown and which are mandatory. Custom fields may also be added per attendee type. This supports events like NITKonnect where alumni, faculty, and guests have different data requirements.
- **[NEW — S. Bharathy docs]** Each event must capture a designated contact person (name, email, and phone number) at creation time. This contact is displayed on the event detail page and in confirmation emails so attendees have a direct point of contact for event-specific queries. This is separate from the event owner role.
- **[NEW — S. Bharathy docs]** Event creation must follow a structured multi-step workflow: (1) Basic details → (2) Attendee type configuration → (3) Ticket configuration → (4) Discount configuration → Save. Each step must be completed before proceeding. Cancelling on step 1 discards the event entirely. Cancelling on any later step saves the event as draft. A draft with incomplete steps cannot be published until all steps are complete.

### 6.5 Registration Management

The system shall support attendee registration for events.

Requirements:

- Allow logged-in users to register for an event.
- Support registration for verified alumni/members.
- Support configurable registration fields.
- Autofill available user information from the alumni/member database where permitted.
- Prevent duplicate registrations for the same user and event.
- Enforce capacity limits.
- Prevent registration after the registration deadline.
- Prevent registration for cancelled or closed events.
- Generate a registration confirmation number or identifier.
- Maintain registration status such as pending, confirmed, cancelled, refunded, or failed.
- Reveal protected event information only after successful registration.
- **[ADD]** When event capacity is reached, registration must close and display a clear capacity-full message to the user. No waitlist or queue behaviour is required unless separately approved.
- **[ADD]** Guest registration (non-alumni/non-member attendees such as faculty, industry guests, or family) is supported by the platform. Whether it is enabled at launch or in a subsequent release is a backlog prioritisation decision. NITKonnect (Feb) is a reference event that already includes non-alumni attendees.
- **[NEW — S. Bharathy docs]** A primary registrant must be able to add additional attendees (family members, guests) under their own registration, selecting the appropriate attendee type and ticket for each additional person. Total ticket count and capacity must be validated across the combined registration.

### 6.6 Confirmation Communication

The system shall send confirmation communication after successful registration.

Requirements:

- Send registration confirmation by email.
- Include event details, registration number, and attendee details.
- Include webinar join link only when applicable and permitted.
- Include venue details for physical events.
- Support future receipt or invoice attachment for paid events.
- Maintain a record of confirmation communication where required.

### 6.7 Attendee Management

Authorized staff shall be able to manage attendees for each event.

Requirements:

- View attendee list per event.
- Search attendees by name.
- Filter attendees by relevant fields such as batch year, branch, registration status, or ticket type.
- View registration timestamp and status.
- Export attendee list as CSV.
- View registered count against capacity.
- Support admin visibility for event-level attendee data only according to role.
- Protect attendee personal data from unauthorized access.
- **[NEW — S. Bharathy docs]** The registered attendee view for admins must display per-attendee: attendee type, original ticket price, discount applied, amount paid, and payment status. This information must be visible in the admin interface and included in exports.
- **[NEW — S. Bharathy docs]** Admins must be able to view real-time ticket inventory per attendee type — tickets configured, tickets sold, tickets remaining, discounts configured, discounts used, discounts remaining. This must be available in the event management view without requiring an export.

### 6.8 Payment Management

The system shall support payment workflows for paid events.

Requirements:

- Support free events without payment.
- Support paid events with online payment gateway integration.
- Support payment order creation.
- Support payment verification.
- Track payment status such as pending, success, failed, refunded.
- Confirm registration only after successful payment where payment is required.
- Support invoice or receipt generation where required.
- Support payment dashboard for admin and finance users.
- Support refund initiation by authorized finance or super admin users.
- Maintain audit trail for payment and refund actions.
- Support payment reconciliation and recovery for failed or incomplete payment states.
- **[ADD]** Refund eligibility rules (such as deadline, conditions, and approval workflow) must be configurable per event by the Super Admin or Finance Admin before the event is published. Refund initiation must validate against the configured rules before proceeding, unless overridden by a Super Admin with audit logging.
- **[ADD]** Paid event support is in scope. Payment gateway selection (Razorpay recommended as default for Indian transactions) is a PM-level procurement decision. The integration must be abstract enough to allow future gateway replacement (see Section 7.4).
- **[NEW — S. Bharathy docs]** The system must support discount coupons per ticket type. Each coupon configuration must include a validity end date and a maximum count. Discounts must not be available to users after the validity date has passed or the coupon count is exhausted. This supports early-bird pricing for events such as the Global Convention.
- **[NEW — S. Bharathy docs]** Discount value must be configurable as either a flat amount off or a percentage off the ticket price. Both types must be supported per discount configuration.

### 6.9 QR Badge and Check-In

The system shall support digital event check-in.

Requirements:

- Generate QR badge or QR code after confirmed registration.
- Allow authorized volunteers to scan QR codes.
- Validate QR code with backend before marking check-in.
- Detect duplicate check-in attempts.
- Detect invalid or cancelled registrations.
- Show immediate scan result to volunteer.
- Maintain check-in timestamp and scanner identity.
- Provide check-in statistics for admin users.
- Support physical event entry management.
- **[ADD]** The check-in flow must define a documented fallback procedure for network-unavailable conditions at a physical event. The fallback approach must be approved before the first live physical event and documented in the operational runbook.

### 6.10 Sessions and Schedule

The system shall support session-based events.

Requirements:

- Allow event managers to add sessions.
- Support session title, description, start time, end time, room, and track.
- Support multi-track events.
- Link speakers to sessions.
- Display sessions to attendees where enabled.
- Support large events such as conferences and annual gatherings.

### 6.11 Speakers and Sponsors

The system shall support event speaker and sponsor information.

Requirements:

- Add speaker profile with name, title, organization, bio, and photo where applicable.
- Link speakers to sessions.
- Display speaker details in the event app.
- Support sponsor information where required.
- Allow sponsor details to be shown on relevant event pages.

### 6.12 Event Resources and Post-Event Content

The system shall support event-related resources.

Requirements:

- Add PDF links, external links, presentation links, recording links, and gallery links.
- Control visibility of resources as public or registered-only.
- Support post-event recording and photo gallery links.
- Avoid hosting large media directly unless approved by management.
- Provide simple link-based access to external media where appropriate.

### 6.13 Announcements and Notifications

The system shall support event announcements.

Requirements:

- Allow authorized event managers to send event announcements.
- Support in-app announcements.
- Support push notifications where enabled.
- Support communication to all registered attendees of a specific event.
- Maintain record of announcement content, sender, and timestamp.

### 6.14 Reports and Exports

The system shall support operational and management reporting.

Requirements:

- Export attendee list.
- Export registrations.
- Export payment records.
- Export check-in records.
- Provide event summary such as total registrations, checked-in count, capacity usage, and payment totals.
- Provide audit-friendly reporting for sensitive administrative actions.

---

## 7. Scope Boundaries

The Event Management App is one component of a three-app NITKSAA digital ecosystem (Admin Portal, Website, Event App). Several capabilities that were listed as out-of-scope in earlier drafts of this document are in fact planned — they simply belong to a different part of the ecosystem. This section clarifies where each capability lives.

| Capability | Where it belongs |
|---|---|
| Alumni directory, profile search, member map | Admin Portal (`directory.nitkalumni.in`) — live in production |
| Community posts, discussion threads, batch/chapter feeds | Website — planned as Communities module |
| Mentorship network | Website — in active development |
| Startup / innovation ecosystem, investor connections | Website — planned post-MVP |
| Career opportunities, job board | Website — planned post-MVP |
| Life membership payment, membership status | Website / Admin Portal — planned |
| Initiatives / alumni crowdfunding campaigns | Website — planned as Giving or Initiatives module |
| Bulk / campaign email marketing | Admin Portal — operational communications capability |
| Full CRM | Admin Portal — alumni data management is its core function |
| Video conferencing or streaming | External platforms (Zoom, YouTube). The Event App links to these; it does not host them |
| Large media hosting (recordings, photo albums) | External platforms (YouTube, Google Photos, Drive). The Event App links to these; it does not host them |
| Public marketing website | Separate — `nitkalumni.in` (Website) |
| Complex waitlist automation | Not planned in any app currently. Simple capacity-full behaviour is sufficient (see Section 6.5) |
| Real-time chat or direct messaging | Explicitly out of scope across the entire ecosystem. Interaction moves to external platforms (WhatsApp, email, LinkedIn) once a connection is established |

The Event App's scope is defined positively by Section 6. It manages the lifecycle of an event — creation, registration, payment, check-in, and post-event content. Everything else is either handled by another app in the ecosystem or deliberately left to external platforms.

---

## 7. ~~8.~~ Integration Requirements

### 7.1 Existing NITKSAA Ecosystem

The Event Management App should integrate with the existing NITKSAA digital ecosystem where appropriate.

Requirements:

- Use the same identity foundation where possible.
- Recognize users through the same stable user identity across systems.
- Reuse alumni/member information for registration autofill where permitted.
- Avoid creating duplicate user records unnecessarily.
- Store event-specific data separately from core alumni data.
- Maintain compatibility with existing Admin Portal and Website systems.
- Support future integration with an Alumni Service when available.

### 7.2 Alumni / Member Data

Requirements:

- Resolve verified alumni/member identity during registration.
- Store event registration reference to alumni/member identity where applicable.
- Do not directly expose protected alumni data to unauthorized users.
- Follow privacy preferences and access rules from the source alumni/member system.
- Keep event registrations logically separate from master alumni records.

### 7.3 Email Service

Requirements:

- Send registration confirmation emails.
- Support event update or cancellation emails where enabled.
- Support receipt/invoice emails for paid events where applicable.
- Use an approved transactional email provider.
- Avoid exposing raw email infrastructure credentials in application code.

### 7.4 Payment Gateway

Requirements:

- Support at least one approved Indian payment gateway.
- Keep payment gateway integration abstract enough to allow future replacement.
- Never store card details on the platform.
- Verify payment signatures or callbacks securely.
- Maintain payment and refund audit trails.

### 7.5 Calendar and External Links

Requirements:

- Provide calendar-friendly event details where applicable.
- Support external webinar links after registration.
- Support external map links for physical venues.
- Support external recording and gallery links for post-event content.

---

## 8. ~~9.~~ Security Requirements

The platform shall follow secure-by-design principles.

Requirements:

- All protected APIs must require authenticated access.
- Role and event-scope authorization must be enforced on the backend.
- Admin-only functions must not be accessible to attendees.
- Volunteer access must be restricted to assigned event check-in functions.
- Sensitive data must be transmitted only over HTTPS.
- Secrets must not be stored in source code.
- Payment data must be handled according to payment gateway and compliance requirements.
- Personal data must be collected only where required for event operations.
- Application logs must not expose sensitive personal data.
- Administrative actions must be audited.
- Exports must be role-restricted.
- Rate limiting and abuse protection should be applied to sensitive endpoints.
- Session expiry and token refresh must be handled securely.
- Admin access should support stronger authentication where required.

---

## 9. ~~10.~~ Privacy and Data Protection Requirements

Requirements:

- Collect only data required for event registration and operations.
- Clearly separate public event data from attendee personal data.
- Protect attendee information from unauthorized access.
- Respect alumni/member privacy settings wherever applicable.
- Limit attendee exports to authorized users.
- Record export purpose where required.
- Avoid exposing raw email or phone details unless explicitly permitted.
- Support data correction through authorized workflows.
- Support retention and archival policy as defined by management.
- Maintain audit records for sensitive data access and exports.

---

## 10. ~~11.~~ Role-Based Access Requirements

| Role | Access Requirement |
|---|---|
| Public visitor | Can view published public events only |
| Attendee | Can register, view own registrations, access own QR badge |
| Verified alumnus/member | Can access member-only event registration where applicable |
| Volunteer | Can scan QR codes only for assigned events |
| Event manager | Can create/manage assigned events and view registrations |
| Finance admin | Can view payments and initiate approved refund workflows |
| Super admin | Can manage platform-wide roles, events, config, and audit |

Backend authorization must be the final source of truth. UI-level hiding of buttons or screens is not sufficient for security.

---

## 11. ~~12.~~ Audit Requirements

The system shall maintain audit records for sensitive operations.

Audit events should include:

- Login and failed login where applicable
- Event creation
- Event update
- Event publish/unpublish
- Event cancellation
- Registration creation
- Registration cancellation
- Payment initiation
- Payment success or failure
- Refund initiation and status change
- Attendee export
- QR check-in
- Role assignment or removal
- Configuration changes
- Announcement sending

Each audit record should include actor, action, target entity, timestamp, source application, and relevant metadata.

---

## 12. ~~13.~~ Data Requirements

The platform shall maintain structured data for event operations.

Core data entities:

| Entity | Purpose |
|---|---|
| User | Platform user identity linked to authentication provider |
| Role | User access level and scope |
| Event | Event details, status, capacity, format, schedule information |
| Registration | User's registration for an event |
| Attendee | Event-specific attendee information |
| Payment | Payment status and gateway references |
| Refund | Refund request and status |
| QR badge | Registration-linked check-in credential |
| Check-in | Attendance scan record |
| Session | Individual program item inside an event |
| Speaker | Speaker profile and session relationship |
| Resource | Event materials, links, recordings, gallery references |
| Announcement | Event-level communication |
| Audit log | Sensitive action record |
| Configuration | Event or platform-level configurable settings |
| Attendee type | Named category of attendee with configurable registration fields per event *(NEW — S. Bharathy docs)* |
| Discount coupon | Ticket-type discount with validity date and count limit per event *(NEW — S. Bharathy docs)* |
| Event contact | Designated contact person (name, email, phone) per event *(NEW — S. Bharathy docs)* |

---

## 13. ~~14.~~ Data Separation Requirements

Requirements:

- Core alumni/member data and event data must remain logically separated.
- Event registrations should reference alumni/member identity without duplicating the full alumni database.
- Event-specific data should be stored in an event data store.
- Business-critical data such as events, registrations, payments, check-ins, and audit logs must be queryable and exportable.
- Real-time or notification-specific data may use supporting services where appropriate.
- The system must avoid direct database access from client applications.

---

## 14. ~~15.~~ Configuration Requirements

The platform should support controlled configuration to reduce code changes for event variations.

Requirements:

- Support configurable event categories.
- Support configurable registration fields.
- Support enabling or disabling modules such as payments, sessions, speakers, resources, announcements, and directory.
- Support configurable legal links such as terms, privacy policy, and refund policy.
- Support configurable support contact details.
- Support brand-level naming and basic configuration where required.
- Provide safe fallback configuration when remote configuration is unavailable.
- Validate configuration before it affects live users.

This section defines functional configurability only and does not define UI design, visual themes, or color systems.

---

## 15. ~~16.~~ Localization Requirements

Requirements:

- Default language should be English.
- System should be prepared to support additional Indian languages where required.
- User-visible text should be externalized where feasible.
- Dates, times, and currency should respect locale and timezone settings.
- Event timezone should be displayed clearly, especially for webinars and multi-region audiences.

---

## 16. ~~17.~~ Non-Functional Requirements

### 16.1 Reliability

- The system should be reliable enough to support live event operations.
- Registration and check-in flows must be highly dependable.
- Critical user actions should return clear success or failure states.
- Payment confirmation should be resilient to network or gateway callback issues.

### 16.2 Performance

- Public event listing should load quickly.
- Registration submission should complete within acceptable user experience limits.
- QR check-in should provide near-immediate scan response.
- Admin attendee list should support search and export for expected event sizes.

### 16.3 Scalability

- The platform should support small meetings and larger annual events.
- The data model should support multiple events over time.
- The platform should support multiple chapters or event organizers with appropriate access controls.
- Large exports and reports should not degrade live registration or check-in flows.

### 16.4 Maintainability

- The system should remain understandable and maintainable by a small technical team.
- Requirements should avoid unnecessary feature expansion.
- Each module should have clear ownership and boundaries.
- Reusable patterns should be followed across related NITKSAA systems where appropriate.

### 16.5 Availability

- The platform should be available during event discovery, registration windows, and live check-in periods.
- Critical event-day functionality should be monitored.
- Operational fallback procedures should exist for live events.

---

## 17. ~~18.~~ Administrative Requirements

Requirements:

- Admin users should be able to manage event lifecycle without developer involvement.
- Management should be able to review event-level operational data.
- Staff should be able to export attendee lists.
- Finance users should be able to review payment status.
- Super admins should be able to manage access control.
- Operational activities should be auditable.
- Known issues and deferred capabilities should be tracked transparently.

---

## 18. ~~19.~~ Acceptance Requirements

The platform can be considered acceptable for operational use when the following are true:

1. Authorized staff can create, edit, publish, and manage an event.
2. Public users can view published events.
3. Attendees can log in and register for an event.
4. Duplicate registration is prevented.
5. Capacity and registration deadline rules are enforced.
6. Confirmation email is sent after successful registration.
7. Registered users can access protected event information where applicable.
8. Admin users can view, search, filter, and export attendee lists.
9. Paid event registration works end to end where payment is enabled.
10. Payment status is visible to authorized admin or finance users.
11. QR badge is generated for confirmed registration.
12. Authorized volunteers can validate QR check-in.
13. Invalid and duplicate check-in attempts are handled clearly.
14. Sensitive actions are recorded in audit logs.
15. Role-based access is enforced by backend authorization.
16. Client applications do not directly access protected databases.
17. Personal data is protected and visible only to authorized roles.
18. The platform can support both physical and virtual event workflows.
19. Event cancellation or closure states are handled correctly.
20. Operational exports are available for management and staff use.

---

*End of document.*
