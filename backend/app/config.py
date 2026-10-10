from functools import lru_cache
from pathlib import Path
from typing import Optional
from urllib.parse import quote

from pydantic import Field
from pydantic_settings import BaseSettings


_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"

# Razorpay modes and the key_id prefix each one requires. Shared by
# Settings.razorpay_credential_problem, RazorpayGateway and
# payment_config_service so the fail-closed rules can never disagree.
RAZORPAY_MODES = ("test", "live")
RAZORPAY_KEY_PREFIX = {"test": "rzp_test_", "live": "rzp_live_"}


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
    # Oldest signed webhook `created_at` still accepted. Razorpay retries a
    # failed delivery for 24 hours after event creation, so the default is
    # 25 hours: a genuine retry must not be rejected as stale. Replay of an
    # already-processed event is stopped by event-id dedupe, not by this.
    payment_webhook_max_age_seconds: int = Field(90000, alias="PAYMENT_WEBHOOK_MAX_AGE_SECONDS")
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

    # Razorpay — ONE active credential set per deployment. RAZORPAY_MODE
    # declares which Razorpay mode these keys belong to: beta runs
    # RAZORPAY_MODE=test with rzp_test_ keys, production RAZORPAY_MODE=live
    # with rzp_live_ keys. A payment/refund/webhook whose payment_mode
    # differs from RAZORPAY_MODE never resolves to these credentials (see
    # razorpay_credential_problem). Server-only — never returned in an API
    # response, never logged, never surfaced by diagnostics.
    razorpay_key_id: str = Field("", alias="RAZORPAY_KEY_ID")
    razorpay_key_secret: str = Field("", alias="RAZORPAY_KEY_SECRET")
    razorpay_webhook_secret: str = Field("", alias="RAZORPAY_WEBHOOK_SECRET")
    razorpay_mode: str = Field("test", alias="RAZORPAY_MODE")

    razorpay_api_base: str = Field("https://api.razorpay.com/v1", alias="RAZORPAY_API_BASE")
    # Network timeout (seconds) for every outbound Razorpay REST call.
    razorpay_http_timeout_seconds: float = Field(20.0, alias="RAZORPAY_HTTP_TIMEOUT_SECONDS")

    def razorpay_credential_problem(self, payment_mode: Optional[str]) -> Optional[str]:
        """None when the active credential set may serve `payment_mode`,
        else a short secret-free reason. Fail closed on: an unknown
        payment_mode, an invalid RAZORPAY_MODE, a payment_mode that isn't
        this deployment's RAZORPAY_MODE, a missing key id/secret, or a key
        id without the mode's rzp_test_/rzp_live_ prefix."""
        if payment_mode not in RAZORPAY_MODES:
            return "payment_mode must be 'test' or 'live'"
        if self.razorpay_mode not in RAZORPAY_MODES:
            return "are unavailable: RAZORPAY_MODE must be 'test' or 'live'"
        if payment_mode != self.razorpay_mode:
            return f"are unavailable: this deployment runs RAZORPAY_MODE={self.razorpay_mode}"
        if not self.razorpay_key_id or not self.razorpay_key_secret:
            return "are not configured"
        expected_prefix = RAZORPAY_KEY_PREFIX[payment_mode]
        if not self.razorpay_key_id.startswith(expected_prefix):
            return f"key_id does not start with {expected_prefix!r}"
        return None

    def razorpay_credentials_for(self, payment_mode: Optional[str]) -> tuple[str, str, str]:
        """(key_id, key_secret, webhook_secret) of the active set when it
        may serve `payment_mode`, else empty strings. Never raises;
        RazorpayGateway._resolve_credentials is the choke point that turns
        a problem into RazorpayModeCredentialError."""
        if self.razorpay_credential_problem(payment_mode) is not None:
            return ("", "", "")
        return (self.razorpay_key_id, self.razorpay_key_secret, self.razorpay_webhook_secret)

    @property
    def razorpay_configured(self) -> bool:
        """True only when the active credential set is usable for this
        deployment's own RAZORPAY_MODE (valid mode, key id + secret present,
        correct key prefix)."""
        return self.razorpay_credential_problem(self.razorpay_mode) is None

    # Payment RBAC (production foundation) — comma-separated firebase_uids
    # that are always treated as platform_admin, independent of
    # payment_platform_roles rows. This is the bootstrap mechanism: the
    # first platform_admin has no one to grant them the role via the API,
    # so ops lists them here instead. Every subsequent grant goes through
    # the payment-roles API and is stored in payment_platform_roles.
    platform_admin_firebase_uids_raw: str = Field(
        "", alias="PLATFORM_ADMIN_FIREBASE_UIDS"
    )

    # NITiKa — the events assistant, a separate Cloud Run service called
    # only from app/api/nitika.py. NITIKA_URL is the service's base URL;
    # NITIKA_CLIENT_KEY comes from the secret nitika-client-key-events.
    # Either one empty → the chat route answers 404 (not configured).
    # Server-only — never returned in an API response, never logged.
    nitika_url: str = Field("", alias="NITIKA_URL")
    nitika_client_key: str = Field("", alias="NITIKA_CLIENT_KEY")
    # NITiKa's own deadline is 20 s; this leaves room for a cold start.
    nitika_timeout_seconds: float = Field(25.0, alias="NITIKA_TIMEOUT_SECONDS")

    @property
    def nitika_configured(self) -> bool:
        return bool(self.nitika_url.strip() and self.nitika_client_key.strip())

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
        user = quote(self.db_user, safe="")
        password = quote(self.db_password, safe="")
        database = quote(database, safe="")

        # Cloud Run + Cloud SQL Unix-domain socket.
        if self.db_host.startswith("/"):
            host = quote(self.db_host, safe="")
            url = f"postgresql://{user}:{password}@/{database}?host={host}&port={self.db_port}"
            return url

        # Normal TCP connection for local/dev environments.
        url = f"postgresql://{user}:{password}@{self.db_host}:{self.db_port}/{database}"
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
