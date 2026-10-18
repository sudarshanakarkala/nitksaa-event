import re
import asyncpg

# An event link someone types: lower-case letters and numbers, single
# hyphens between them (e.g. "bangalore-breakfast-oct-2026").
SLUG_PATTERN = r"^[a-z0-9]+(?:-[a-z0-9]+)*$"

_NON_SLUG = re.compile(r"[^\w\s-]")
_WHITESPACE = re.compile(r"[\s_]+")


def make_base_slug(title: str) -> str:
    slug = title.lower().strip()
    slug = _NON_SLUG.sub("", slug)
    slug = _WHITESPACE.sub("-", slug)
    slug = slug.strip("-")
    return slug or "event"


class SlugService:
    def __init__(self, conn: asyncpg.Connection):
        self.conn = conn

    async def generate_slug(self, title: str) -> str:
        base = make_base_slug(title)
        slug = base
        counter = 2
        while True:
            exists = await self.conn.fetchval(
                "SELECT 1 FROM events WHERE slug = $1", slug
            )
            if not exists:
                return slug
            slug = f"{base}-{counter}"
            counter += 1
