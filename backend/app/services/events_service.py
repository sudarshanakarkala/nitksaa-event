from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

import asyncpg
from fastapi import HTTPException

from app.repositories.events_repository import EventsRepository
from app.schemas.event_create import EventCreate
from app.schemas.event_status import EventStatusUpdate
from app.schemas.event_update import EventUpdate
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

        record = await self.repo.update_event(event_id, {"status": new_status, **extra})
        await self._audit(user["firebase_uid"], audit_type, event_id)
        return _enrich(self._to_dict(record))

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
        d["speakers"] = []
        return d
