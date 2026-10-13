import json
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import asyncpg
from fastapi import HTTPException

from app.repositories.events_repository import EventsRepository
from app.repositories.payment_role_repository import PaymentRoleRepository
from app.repositories.people_repository import PeopleRepository
from app.repositories.sponsors_partners_repository import SponsorsRepository, PartnersRepository
from app.schemas.event_create import EventCreate
from app.schemas.event_status import EventStatusUpdate
from app.schemas.event_update import EventUpdate
from app.schemas.events import SessionCreate
from app.services.payment_config_sync import sync_event_payment_configuration
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


def _update_context(event_id: int, before: Dict[str, Any], after: Dict[str, Any],
                    requested: Dict[str, Any]) -> Dict[str, Any]:
    """What an edit changed: field names only (not their values, which can
    be long or personal), except the price, the free/paid switch and
    registration closing, which matter for payments and support."""
    changed = sorted(k for k in requested if before.get(k) != after.get(k))
    ctx: Dict[str, Any] = {"event_id": event_id, "fields": changed}
    if "ticket_price" in changed or "is_free" in changed:
        def price(row):
            return "free" if row.get("is_free") else (str(row.get("ticket_price")) if row.get("ticket_price") is not None else None)
        ctx["price"] = {"from": price(before), "to": price(after)}
    if "registration_closes_at" in changed:
        now = datetime.now(timezone.utc)
        was_closed = before.get("registration_closes_at") is not None and before["registration_closes_at"] <= now
        is_closed = after.get("registration_closes_at") is not None and after["registration_closes_at"] <= now
        if is_closed and not was_closed:
            ctx["registration"] = "closed"
        elif was_closed and not is_closed:
            ctx["registration"] = "reopened"
    return ctx


class EventsService:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn
        self.repo = EventsRepository(conn)
        self.slug_svc = SlugService(conn)

    def _to_dict(self, record: asyncpg.Record) -> Dict[str, Any]:
        return dict(record)

    async def _audit(
        self,
        actor_uid: str,
        event_type: str,
        entity_id: int,
        context: Optional[Dict[str, Any]] = None,
    ) -> None:
        await self.conn.execute(
            """
            INSERT INTO event_audit_log (actor_uid, event_type, entity_type, entity_id, context)
            VALUES ($1, $2, 'event', $3, $4::jsonb)
            """,
            actor_uid, event_type, entity_id,
            json.dumps(context) if context is not None else None,
        )

    # ── Admin: Create ────────────────────────────────────────────────────────

    async def create_event(
        self, data: EventCreate, user: Dict[str, Any]
    ) -> Dict[str, Any]:
        creator_uid = user["firebase_uid"]
        # One transaction: the event, its creator's event_admin membership
        # and both audit rows land together or not at all (admin revamp 1.3).
        async with self.conn.transaction():
            slug = await self.slug_svc.generate_slug(data.title)
            record = await self.repo.create_event(data, slug, creator_uid)
            d = self._to_dict(record)
            event_id = d["event_id"]
            await self._audit(creator_uid, "event_created", event_id,
                              {"event_id": event_id, "title": d.get("title"), "status": d.get("status")})

            # event_members.firebase_uid references event_users; an
            # env-var-only emergency admin may never have signed in, and
            # overall admins see every event anyway.
            has_user_row = await self.conn.fetchval(
                "SELECT EXISTS(SELECT 1 FROM event_users WHERE firebase_uid = $1)",
                creator_uid,
            )
            if has_user_row:
                await PaymentRoleRepository(self.conn).grant_event_admin(event_id, creator_uid)
                await self._audit(
                    creator_uid,
                    "event_admin_granted",
                    event_id,
                    {"target_uid": creator_uid, "role": "event_admin",
                     "event_id": event_id, "reason": "creator"},
                )
        return _enrich(d)

    # ── Admin: List ──────────────────────────────────────────────────────────

    async def list_events(
        self,
        page: int = 1,
        per_page: int = 20,
        status: Optional[str] = None,
        is_virtual: Optional[bool] = None,
        search: Optional[str] = None,
        period: Optional[str] = None,
        event_ids: Optional[List[int]] = None,
    ) -> Tuple[List[Dict[str, Any]], int]:
        """event_ids=None lists every event (overall admin); a list —
        even an empty one — restricts to exactly those events."""
        rows, total = await self.repo.list_events(
            page, per_page, status, is_virtual, search, period=period, event_ids=event_ids
        )
        return [_enrich(self._to_dict(r)) for r in rows], total

    # ── Admin: Get ───────────────────────────────────────────────────────────

    async def get_event(self, event_id: int) -> Dict[str, Any]:
        record = await self.repo.get_event(event_id)
        if not record:
            raise HTTPException(status_code=404, detail="event_not_found")
        d = _enrich(self._to_dict(record))
        await self._attach_details(d, event_id)
        return d

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
        await self._audit(user["firebase_uid"], "event_updated", event_id,
                          _update_context(event_id, dict(existing), dict(record), fields))
        # A price change on a published paid event must reach checkout.
        await self._ensure_payment_configuration(self._to_dict(record), user)
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
        await self._audit(user["firebase_uid"], audit_type, event_id,
                          {"event_id": event_id, "from": current, "to": new_status})
        if new_status == "published":
            await self._ensure_payment_configuration(self._to_dict(record), user)
        return _enrich(self._to_dict(record))

    async def _ensure_payment_configuration(self, event: Dict[str, Any], user: Dict[str, Any]) -> None:
        """Keep a published paid event's payment setup in step with its
        price and the server's Razorpay mode (see payment_config_sync).
        The event form is the one place a creator sets the price. No-op for
        free events, drafts, and when nothing changed."""
        created = await sync_event_payment_configuration(self.conn, event, user["firebase_uid"])
        if created is not None:
            await self._audit(user["firebase_uid"], "payment_configuration_synced", event["event_id"], {
                "event_id": event["event_id"],
                "price": str(created["base_amount"]),
                "mode": created["payment_mode"] if "payment_mode" in created else None,
                "version": created["version"],
            })

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

    async def _attach_details(self, d: Dict[str, Any], event_id: int) -> None:
        """What the event page shows besides the event itself: sessions,
        fee tiers, speakers (and other people), sponsors and partners.
        Shared by the public page and the admin view, so a draft previews
        exactly as it will look once published."""
        d["sessions"] = [self._to_dict(r) for r in await self.repo.list_sessions(event_id)]
        fee_rows = await self.conn.fetch(
            "SELECT fee_id, name, fee_type, amount FROM event_fees"
            " WHERE event_id = $1::int ORDER BY display_order, fee_id",
            event_id,
        )
        d["fees"] = [{**dict(r), "amount": float(r["amount"])} for r in fee_rows]

        people_rows = await PeopleRepository(self.conn).list_public_by_event(event_id)
        people = [dict(r) for r in people_rows]
        d["people"] = people
        _SPEAKER_ROLES = frozenset({"SPEAKER", "PANELIST", "CHIEF_GUEST", "GUEST_OF_HONOUR"})
        d["speakers"] = [p for p in people if p["role"] in _SPEAKER_ROLES]

        sponsor_rows = await SponsorsRepository(self.conn).list_public_by_event(event_id)
        d["sponsors"] = [dict(r) for r in sponsor_rows]

        partner_rows = await PartnersRepository(self.conn).list_public_by_event(event_id)
        d["partners"] = [dict(r) for r in partner_rows]

    # ── Public: Get ──────────────────────────────────────────────────────────

    async def get_public_event(self, event_id: int) -> Dict[str, Any]:
        record = await self.repo.get_public_event(event_id)
        if not record:
            raise HTTPException(status_code=404, detail="event_not_found")
        d = self._to_dict(record)
        _with_public_card_metadata(d)
        await self._attach_details(d, event_id)
        return d
