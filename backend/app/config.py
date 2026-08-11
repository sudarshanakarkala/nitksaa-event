from functools import lru_cache
from pathlib import Path
from typing import Optional

from pydantic import Field
from pydantic_settings import BaseSettings


_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


class Settings(BaseSettings):
    app_env: str = Field("development", alias="APP_ENV")
    app_name: str = Field("NITKSAA Event API", alias="APP_NAME")
    app_version: str = Field("0.1.0-alpha", alias="APP_VERSION")
    allowed_origins: str = Field("http://localhost:5173", alias="ALLOWED_ORIGINS")

    # Database
    db_host: str = Field("127.0.0.1", alias="DB_HOST")
    db_port: int = Field(5432, alias="DB_PORT")
    db_user: str = Field("postgres", alias="DB_USER")
    db_password: str = Field("db123", alias="DB_PASSWORD")
    db_sslmode: str = Field("prefer", alias="DB_SSLMODE")
    events_db_name: str = Field("events_db", alias="EVENTS_DB_NAME")
    events_db_url: Optional[str] = Field(None, alias="EVENTS_DB_URL")
    alumni_db_name: str = Field("alumni_db", alias="ALUMNI_DB_NAME")
    alumni_db_url: Optional[str] = Field(None, alias="ALUMNI_DB_URL")

    # Auth
    secret_key: str = Field("dev-event-secret-change-me", alias="SECRET_KEY")
    access_token_expire_minutes: int = Field(480, alias="ACCESS_TOKEN_EXPIRE_MINUTES")
    firebase_project_id: str = Field(
        "project-d22bed42-f302-4e23-8dc",
        alias="FIREBASE_PROJECT_ID",
    )

    # Email
    email_mode: str = Field("log", alias="EMAIL_MODE")
    email_from: Optional[str] = Field(None, alias="EMAIL_FROM")
    email_reply_to: Optional[str] = Field(None, alias="EMAIL_REPLY_TO")
    smtp_host: str = Field("smtp.gmail.com", alias="SMTP_HOST")
    smtp_port: int = Field(587, alias="SMTP_PORT")
    smtp_user: Optional[str] = Field(None, alias="SMTP_USER")
    smtp_password: Optional[str] = Field(None, alias="SMTP_PASSWORD")
    app_public_base_url: str = Field("http://localhost:8000", alias="APP_PUBLIC_BASE_URL")

    # Payments (Phase 0 — deterministic sandbox gateway only)
    payment_gateway_mode: str = Field("deterministic_sandbox", alias="PAYMENT_GATEWAY_MODE")
    payment_sandbox_signing_secret: str = Field(
        "dev-payment-sandbox-secret-change-me", alias="PAYMENT_SANDBOX_SIGNING_SECRET"
    )
    payment_webhook_max_age_seconds: int = Field(300, alias="PAYMENT_WEBHOOK_MAX_AGE_SECONDS")
    payment_webhook_max_future_skew_seconds: int = Field(
        30, alias="PAYMENT_WEBHOOK_MAX_FUTURE_SKEW_SECONDS"
    )
    payment_diagnostics_enabled: bool = Field(True, alias="PAYMENT_DIAGNOSTICS_ENABLED")

    # Payment RBAC (production foundation) — comma-separated firebase_uids
    # that are always treated as platform_admin, independent of
    # payment_platform_roles rows. This is the bootstrap mechanism: the
    # first platform_admin has no one to grant them the role via the API,
    # so ops lists them here instead. Every subsequent grant goes through
    # the payment-roles API and is stored in payment_platform_roles.
    platform_admin_firebase_uids_raw: str = Field(
        "", alias="PLATFORM_ADMIN_FIREBASE_UIDS"
    )

    @property
    def events_db_dsn(self) -> str:
        if self.events_db_url:
            return self.events_db_url
        return self._postgres_url(self.events_db_name)

    @property
    def alumni_db_dsn(self) -> str:
        if self.alumni_db_url:
            return self.alumni_db_url
        return self._postgres_url(self.alumni_db_name)

    @property
    def origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.allowed_origins.split(",") if origin.strip()]

    @property
    def platform_admin_firebase_uids(self) -> list[str]:
        return [
            uid.strip()
            for uid in self.platform_admin_firebase_uids_raw.split(",")
            if uid.strip()
        ]

    def _postgres_url(self, database: str) -> str:
        url = f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{database}"
        if self.db_sslmode:
            return f"{url}?sslmode={self.db_sslmode}"
        return url

    class Config:
        env_file = _ENV_FILE
        env_file_encoding = "utf-8"
        populate_by_name = True
        extra = "ignore"


@lru_cache
def get_settings() -> Settings:
    return Settings()
