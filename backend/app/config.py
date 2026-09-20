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
    db_password: str = Field("postgres", alias="DB_PASSWORD")
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

    # Payments — gateway-neutral foundation (Sprint 7). payment_gateway_mode
    # selects which app.gateways.registry entry payment initiation uses;
    # server-side config only, never client-supplied (see app/gateways/registry.py).
    payment_gateway_mode: str = Field("deterministic_sandbox", alias="PAYMENT_GATEWAY_MODE")
    payment_sandbox_signing_secret: str = Field(
        "dev-payment-sandbox-secret-change-me", alias="PAYMENT_SANDBOX_SIGNING_SECRET"
    )
    payment_webhook_max_age_seconds: int = Field(300, alias="PAYMENT_WEBHOOK_MAX_AGE_SECONDS")
    payment_webhook_max_future_skew_seconds: int = Field(
        30, alias="PAYMENT_WEBHOOK_MAX_FUTURE_SKEW_SECONDS"
    )
    payment_diagnostics_enabled: bool = Field(True, alias="PAYMENT_DIAGNOSTICS_ENABLED")
    # Fail-closed guard (DeterministicSandboxGateway.is_enabled): the
    # no-real-money sandbox gateway must never be silently reachable in a
    # real production deployment. False unless explicitly opted in — see
    # app/gateways/deterministic_sandbox.py.
    payment_sandbox_allow_in_production: bool = Field(
        False, alias="PAYMENT_SANDBOX_ALLOW_IN_PRODUCTION"
    )

    # Razorpay — legacy single-profile credentials. DEPRECATED: kept only as
    # a back-compat seed for the TEST profile (see razorpay_credentials_for)
    # so an existing local .env with only these three vars keeps working.
    # New deployments should set RAZORPAY_TEST_* / RAZORPAY_LIVE_* instead.
    # Server-only — never returned in an API response, never logged, never
    # surfaced by diagnostics.
    razorpay_key_id: str = Field("", alias="RAZORPAY_KEY_ID")
    razorpay_key_secret: str = Field("", alias="RAZORPAY_KEY_SECRET")
    razorpay_webhook_secret: str = Field("", alias="RAZORPAY_WEBHOOK_SECRET")
    razorpay_mode: str = Field("test", alias="RAZORPAY_MODE")

    # Razorpay TEST/LIVE mode separation. Two fully independent credential
    # profiles — a payment_mode of "test" only ever resolves to the
    # razorpay_test_* triple, "live" only ever to razorpay_live_*. There is
    # no fallback from live to test or vice versa (see
    # razorpay_credentials_for + RazorpayGateway fail-closed prefix check).
    razorpay_test_key_id: str = Field("", alias="RAZORPAY_TEST_KEY_ID")
    razorpay_test_key_secret: str = Field("", alias="RAZORPAY_TEST_KEY_SECRET")
    razorpay_test_webhook_secret: str = Field("", alias="RAZORPAY_TEST_WEBHOOK_SECRET")
    razorpay_live_key_id: str = Field("", alias="RAZORPAY_LIVE_KEY_ID")
    razorpay_live_key_secret: str = Field("", alias="RAZORPAY_LIVE_KEY_SECRET")
    razorpay_live_webhook_secret: str = Field("", alias="RAZORPAY_LIVE_WEBHOOK_SECRET")

    razorpay_api_base: str = Field("https://api.razorpay.com/v1", alias="RAZORPAY_API_BASE")
    # Network timeout (seconds) for every outbound Razorpay REST call.
    razorpay_http_timeout_seconds: float = Field(20.0, alias="RAZORPAY_HTTP_TIMEOUT_SECONDS")

    def razorpay_credentials_for(self, payment_mode: str) -> tuple[str, str, str]:
        """(key_id, key_secret, webhook_secret) for `payment_mode`, with NO
        cross-mode fallback. "test" additionally falls back to the legacy
        RAZORPAY_KEY_ID/KEY_SECRET/WEBHOOK_SECRET vars when RAZORPAY_TEST_*
        is blank, purely for existing-deployment back-compat — "live" never
        falls back to anything. Returns empty strings (never raises) when
        unconfigured; callers (RazorpayGateway) are responsible for failing
        closed."""
        if payment_mode == "live":
            return (
                self.razorpay_live_key_id,
                self.razorpay_live_key_secret,
                self.razorpay_live_webhook_secret,
            )
        if payment_mode == "test":
            return (
                self.razorpay_test_key_id or self.razorpay_key_id,
                self.razorpay_test_key_secret or self.razorpay_key_secret,
                self.razorpay_test_webhook_secret or self.razorpay_webhook_secret,
            )
        return ("", "", "")

    @property
    def razorpay_configured(self) -> bool:
        """True only when both TEST-profile credentials are present
        (legacy-fallback inclusive). Retained for existing callers that
        don't yet reason about mode; RazorpayGateway.is_enabled() now checks
        per-mode via razorpay_credentials_for."""
        key_id, key_secret, _ = self.razorpay_credentials_for("test")
        return bool(key_id and key_secret)

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
