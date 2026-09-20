from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Dict, List, Optional, Tuple

import asyncpg
from fastapi import HTTPException

from app.repositories.events_repository import EventsRepository
from app.repositories.payment_repository import PaymentRepository
from app.repositories.people_repository import PeopleRepository
from app.repositories.sponsors_partners_repository import SponsorsRepository, PartnersRepository
from app.schemas.event_create import EventCreate
from app.schemas.event_status import EventStatusUpdate
from app.schemas.event_update import EventUpdate
from app.schemas.events import SessionCreate
from app.services.slug_service import SlugService

_VALID_TRANSITIONS: Dict[str, set] = {
    "draft": {"published", "cancelled"},
    "published": {"draft", "cancelled", "completed"},
    "cancelled": set(),
    "completed": set(),
}

_AUDIT_TYPES = {
    ("any", "published"): "event_published",
    ("published", "draft"): "event_unpublished",
    ("any", "cancelled"): "event_cancelled",
}


def _compute_registration_status(event: Dict[str, Any]) -> str:
    if event.get("status") != "published":
        return "not_applicable"
    now = datetime.now(timezone.utc)
    capacity = event.get("capacity")
    registered = event.get("registered_count", 0)
    if capacity is not None and registered >= capacity:
        return "full"
    opens_at = event.get("registration_opens_at")
    if opens_at and now < opens_at:
        return "not_open_yet"
    closes_at = event.get("registration_closes_at")
    if closes_at and now > closes_at:
        return "closed"
    return "open"


def _enrich(d: Dict[str, Any]) -> Dict[str, Any]:
    d.setdefault("registered_count", 0)
    d["registration_status"] = _compute_registration_status(d)
    return d


def _with_public_card_metadata(d: Dict[str, Any]) -> Dict[str, Any]:
    d.setdefault("registered_count", 0)
    d["registration_status"] = _compute_registration_status(d)
    return d


class EventsService:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn
        self.repo = EventsRepository(conn)
        self.slug_svc = SlugService(conn)

    def _to_dict(self, record: asyncpg.Record) -> Dict[str, Any]:
        return dict(record)

    async def _audit(self, actor_uid: str, event_type: str, entity_id: int) -> None:
        await self.conn.execute(
            """
            INSERT INTO event_audit_log (actor_uid, event_type, entity_type, entity_id)
            VALUES ($1, $2, 'event', $3)
            """,
            actor_uid, event_type, entity_id,
        )

    # ── Admin: Create ────────────────────────────────────────────────────────

    async def create_event(
        self, data: EventCreate, user: Dict[str, Any]
    ) -> Dict[str, Any]:
        slug = await self.slug_svc.generate_slug(data.title)
        record = await self.repo.create_event(data, slug, user["firebase_uid"])
        d = self._to_dict(record)
        await self._audit(user["firebase_uid"], "event_created", d["event_id"])
        return _enrich(d)

    # ── Admin: List ──────────────────────────────────────────────────────────

    async def list_events(
        self,
        page: int = 1,
        per_page: int = 20,
        status: Optional[str] = None,
        is_virtual: Optional[bool] = None,
        search: Optional[str] = None,
    ) -> Tuple[List[Dict[str, Any]], int]:
        rows, total = await self.repo.list_events(page, per_page, status, is_virtual, search)
        return [_enrich(self._to_dict(r)) for r in rows], total

    # ── Admin: Get ───────────────────────────────────────────────────────────

    async def get_event(self, event_id: int) -> Dict[str, Any]:
        record = await self.repo.get_event(event_id)
        if not record:
            raise HTTPException(status_code=404, detail="event_not_found")
        return _enrich(self._to_dict(record))

    # ── Admin: Update ────────────────────────────────────────────────────────

    async def update_event(
        self, event_id: int, data: EventUpdate, user: Dict[str, Any]
    ) -> Dict[str, Any]:
        existing = await self.repo.get_event(event_id)
        if not existing:
            raise HTTPException(status_code=404, detail="event_not_found")

        fields = data.model_dump(exclude_unset=True)
        if not fields:
            return _enrich(self._to_dict(existing))

        record = await self.repo.update_event(event_id, fields)
        await self._audit(user["firebase_uid"], "event_updated", event_id)
        return _enrich(self._to_dict(record))

    # ── Admin: Status ────────────────────────────────────────────────────────

    async def update_status(
        self, event_id: int, data: EventStatusUpdate, user: Dict[str, Any]
    ) -> Dict[str, Any]:
        existing = await self.repo.get_event(event_id)
        if not existing:
            raise HTTPException(status_code=404, detail="event_not_found")

        current = existing["status"]
        new_status = data.status

        allowed = _VALID_TRANSITIONS.get(current, set())
        if new_status not in allowed:
            raise HTTPException(
                status_code=409,
                detail=f"invalid_status_transition_{current}_to_{new_status}",
            )

        extra: Dict[str, Any] = {}
        audit_type = "event_updated"

        if new_status == "published":
            self._validate_for_publish(self._to_dict(existing))
            if not existing["published_at"]:
                extra["published_at"] = datetime.now(timezone.utc)
            audit_type = "event_published"
        elif new_status == "draft" and current == "published":
            audit_type = "event_unpublished"
        elif new_status == "cancelled":
            extra["cancelled_at"] = datetime.now(timezone.utc)
            audit_type = "event_cancelled"
        elif new_status == "completed":
            audit_type = "event_completed"

        # Conditional on the status we actually read (Sprint 3
        # Verification Closure — reproduced two concurrent callers both
        # reading the same pre-transition status, both passing validation,
        # both writing, both auditing a "success" for what was really one
        # transition and one redundant no-op. The WHERE clause is the
        # real guard, same principle as payment_orders/payment_attempts
        # and the check_ins uniqueness index: a caller that loses the
        # race updates zero rows and must not audit a success it didn't
        # actually cause.
        record = await self.repo.update_event_if_status(event_id, current, {"status": new_status, **extra})
        if record is None:
            raise HTTPException(
                status_code=409,
                detail=f"status_changed_concurrently_expected_{current}",
            )
        await self._audit(user["firebase_uid"], audit_type, event_id)
        if new_status == "published":
            await self._ensure_payment_configuration(self._to_dict(record), user)
        return _enrich(self._to_dict(record))

    async def _ensure_payment_configuration(self, event: Dict[str, Any], user: Dict[str, Any]) -> None:
        """Auto-provision a baseline Razorpay payment configuration for a
        newly-published paid event that doesn't have one yet. The admin
        portal's event form only sets events.ticket_price — it has no UI to
        create a payment_configurations row — so without this, every
        admin-created paid event would be unpayable in the payment app.
        Idempotent (skipped once a published configuration exists) and a
        no-op for free events."""
        if event.get("is_free") or not event.get("ticket_price"):
            return
        event_id = event["event_id"]
        pay_repo = PaymentRepository(self.conn)
        if await pay_repo.get_published_config_for_event(event_id):
            return
        await pay_repo.create_new_config_version(
            configuration_key=f"auto-event-{event_id}",
            event_id=event_id,
            base_amount=Decimal(str(event["ticket_price"])),
            gst_enabled=False,
            gst_rate=Decimal("0"),
            gst_mode="exclusive",
            convenience_fee_enabled=False,
            convenience_fee_type="fixed",
            convenience_fee_value=Decimal("0"),
            seat_hold_minutes=15,
            payment_session_expiry_minutes=15,
            created_by=user["firebase_uid"],
            gateway="razorpay",
            # Admin-portal-published events must never silently become
            # Live-charging — LIVE requires an explicit, platform_admin-gated
            # publish through the payment-config admin API.
            payment_mode="test",
        )
        await self._audit(user["firebase_uid"], "payment_configuration_auto_created", event_id)

    # ── Admin: Sessions ──────────────────────────────────────────────────────

    async def create_session(
        self, event_id: int, data: SessionCreate, user: Dict[str, Any]
    ) -> Dict[str, Any]:
        existing = await self.repo.get_event(event_id)
        if not existing:
            raise HTTPException(status_code=404, detail="event_not_found")
        record = await self.repo.create_session(event_id, data)
        await self._audit(user["firebase_uid"], "session_created", event_id)
        return self._to_dict(record)

    async def list_sessions(self, event_id: int) -> List[Dict[str, Any]]:
        existing = await self.repo.get_event(event_id)
        if not existing:
            raise HTTPException(status_code=404, detail="event_not_found")
        rows = await self.repo.list_sessions(event_id)
        return [self._to_dict(r) for r in rows]

    def _validate_for_publish(self, event: Dict[str, Any]) -> None:
        required = ["title", "description", "start_datetime", "end_datetime", "timezone", "capacity"]
        if event.get("is_virtual"):
            required.append("virtual_url")
        else:
            required.append("location_text")
        missing = [f for f in required if not event.get(f)]
        if missing:
            raise HTTPException(
                status_code=422,
                detail=f"missing_fields_for_publish: {', '.join(missing)}",
            )

    # ── Public: List ─────────────────────────────────────────────────────────

    async def list_public_events(
        self, period: Optional[str], page: int, per_page: int
    ) -> Tuple[List[Dict[str, Any]], int]:
        rows, total = await self.repo.list_public_events(period, page, per_page)
        result = []
        for r in rows:
            d = self._to_dict(r)
            result.append(_with_public_card_metadata(d))
        return result, total

    # ── Public: Get ──────────────────────────────────────────────────────────

    async def get_public_event(self, event_id: int) -> Dict[str, Any]:
        record = await self.repo.get_public_event(event_id)
        if not record:
            raise HTTPException(status_code=404, detail="event_not_found")
        d = self._to_dict(record)
        _with_public_card_metadata(d)
        d["sessions"] = []

        people_rows = await PeopleRepository(self.conn).list_public_by_event(event_id)
        people = [dict(r) for r in people_rows]
        d["people"] = people
        _SPEAKER_ROLES = frozenset({"SPEAKER", "PANELIST", "CHIEF_GUEST", "GUEST_OF_HONOUR"})
        d["speakers"] = [p for p in people if p["role"] in _SPEAKER_ROLES]

        sponsor_rows = await SponsorsRepository(self.conn).list_public_by_event(event_id)
        d["sponsors"] = [dict(r) for r in sponsor_rows]

        partner_rows = await PartnersRepository(self.conn).list_public_by_event(event_id)
        d["partners"] = [dict(r) for r in partner_rows]

        return d
