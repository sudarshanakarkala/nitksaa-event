"""Gateway-neutral payment contract.

The payment domain (app.services.payment_service) talks to this interface
only — never to a specific provider module directly. Every concrete gateway
(deterministic_sandbox today; a real provider later) implements
`PaymentGateway` and is looked up through `app.gateways.registry`, never
imported by name from business logic.

Design notes:
 - Capability declaration over branching: a gateway that does not support an
   operation (e.g. refund — no gateway implements this yet) raises
   `GatewayCapabilityNotSupportedError` rather than the domain layer special
   -casing provider names.
 - `NormalizedGatewayEvent` is the one shape payment_service ever reads for a
   webhook outcome. Provider-specific vocabulary (e.g. "payment.captured")
   is translated to `NormalizedStatus` inside the adapter, not the domain.
 - Nothing here talks to the database or FastAPI — this module has no
   knowledge of orders/attempts/registrations, only of "a payment with this
   gateway".
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from decimal import Decimal
from enum import Enum
from typing import Any, FrozenSet, Optional


class NormalizedStatus(str, Enum):
    """Provider-independent outcome of a gateway webhook/status event.
    Adapters translate their own vocabulary into these five values; the
    payment domain branches on this enum only, never on raw provider text."""

    PAYMENT_SUCCESS = "PAYMENT_SUCCESS"
    PAYMENT_FAILED = "PAYMENT_FAILED"
    PAYMENT_PENDING = "PAYMENT_PENDING"
    PAYMENT_CANCELLED = "PAYMENT_CANCELLED"
    UNKNOWN = "UNKNOWN"


class NormalizedRefundStatus(str, Enum):
    """Provider-independent refund state. Adapters map their own vocabulary
    (Razorpay: created/processed/failed) into these; the refund domain
    (app.services.refund_service) branches on this enum only."""

    REFUND_PENDING = "REFUND_PENDING"      # accepted, not yet settled
    REFUND_PROCESSED = "REFUND_PROCESSED"  # provider reports done/settled
    REFUND_FAILED = "REFUND_FAILED"        # provider rejected — retryable
    UNKNOWN = "UNKNOWN"


class RefundFailureReason(str, Enum):
    """Why a provider refused or couldn't process a refund, in plain,
    provider-neutral terms. Adapters classify their own errors into these;
    the provider's raw error text is never kept (it can carry card or
    contact details)."""

    INSUFFICIENT_BALANCE = "insufficient_balance"   # not enough in the account yet
    PROVIDER_UNAVAILABLE = "provider_unavailable"   # outage, timeout, network
    PAYMENT_TOO_OLD = "payment_too_old"
    ALREADY_REFUNDED = "already_refunded"
    AMOUNT_NOT_ALLOWED = "amount_not_allowed"
    PAYMENT_NOT_CAPTURED = "payment_not_captured"
    REFUNDED_OUTSIDE_APP = "refunded_outside_app"   # found a refund we didn't make
    DECLINED = "declined"                           # refused, reason not recognised


# Worth trying again later on their own; anything else needs a person.
TEMPORARY_REFUND_FAILURES = frozenset({
    RefundFailureReason.INSUFFICIENT_BALANCE,
    RefundFailureReason.PROVIDER_UNAVAILABLE,
})


class GatewayCapability(str, Enum):
    """Operations a gateway may or may not support. See PaymentGateway
    docstring — declared per-adapter in `capabilities`, checked by the
    default method implementations below (not by domain-layer branching)."""

    CREATE_PAYMENT = "create_payment"
    VERIFY_PAYMENT = "verify_payment"
    QUERY_PAYMENT_STATUS = "query_payment_status"
    PROCESS_WEBHOOK = "process_webhook"
    VERIFY_WEBHOOK = "verify_webhook"
    REFUND = "refund"
    QUERY_REFUND = "query_refund"


@dataclass(frozen=True)
class SignedWebhookDelivery:
    """A ready-to-process webhook delivery: exactly what would arrive over
    HTTP from a real gateway. Used by adapters (today, only the sandbox)
    that can produce a delivery synchronously as part of `create_payment`."""

    raw_body: bytes
    signature: str


@dataclass(frozen=True)
class DelayedWebhookDelivery:
    """Same as SignedWebhookDelivery, but intended for delivery after
    `delay_seconds` — a deterministic-sandbox-only testing concept (DELAYED_*
    scenarios). No production gateway is expected to need this; kept on the
    interface only so the sandbox's existing behavior has somewhere to live
    without payment_service reaching into the sandbox module directly."""

    raw_body: bytes
    signature: str
    delay_seconds: int


@dataclass(frozen=True)
class GatewayCheckout:
    """Frontend-safe payload the client needs to open a hosted checkout
    (Razorpay Checkout). Contains ONLY public values — never key_secret or
    webhook_secret. `amount_minor` is the smallest currency unit (paise for
    INR); the client must not be trusted to recompute it — it is echoed here
    purely so the checkout widget can render, and is re-validated
    server-side against the order on the verify-checkout call."""

    provider_order_id: str
    key_id: str
    amount_minor: int
    currency: str


@dataclass(frozen=True)
class GatewayInitiationResult:
    """Result of PaymentGateway.create_payment().

    - deterministic sandbox: sets immediate_webhook OR delayed_webhook (it
      simulates the whole round trip in-process).
    - hosted-checkout gateway (Razorpay): sets `checkout` and neither
      webhook field — the real webhook arrives later over HTTP, and the
      client drives the checkout widget with `checkout`.

    `gateway_order_ref` is the authoritative provider-side order reference to
    persist on the payment_attempts row. For a provider that mints the order
    id itself (Razorpay `order_xxx`), this is that id — which may differ from
    any placeholder the caller passed in; payment_service persists whatever
    is returned here."""

    gateway_order_ref: str
    immediate_webhook: Optional[SignedWebhookDelivery] = None
    delayed_webhook: Optional[DelayedWebhookDelivery] = None
    checkout: Optional[GatewayCheckout] = None


@dataclass(frozen=True)
class PaymentDetails:
    """Provider-neutral facts about one payment, for support, finance, Audit
    and NITiKa. Each adapter maps its own fields into these names; anything a
    provider doesn't report stays None. Never personal data (no email, phone,
    UPI id or card details). Amounts are in the smallest currency unit, as
    the provider reports them."""

    method: Optional[str] = None          # upi / card / netbanking / wallet / emi
    instrument: Optional[str] = None      # bank or wallet code
    international: Optional[bool] = None
    fee_minor: Optional[int] = None       # gateway fee incl. tax
    tax_minor: Optional[int] = None
    failure_source: Optional[str] = None  # who/where it failed: customer, bank ...
    failure_step: Optional[str] = None    # at which step
    failure_reason: Optional[str] = None  # why, e.g. incorrect_otp
    bank_reference: Optional[str] = None  # bank/network reference (RRN etc.)

    def to_context(self) -> dict:
        """Compact, JSON-safe form for audit entries (None values dropped)."""
        out = {
            "method": self.method,
            "instrument": self.instrument,
            "international": self.international,
            "fee": _minor_to_str(self.fee_minor),
            "tax": _minor_to_str(self.tax_minor),
            "bank_reference": self.bank_reference,
        }
        failure = {k: v for k, v in (("source", self.failure_source), ("step", self.failure_step),
                                     ("reason", self.failure_reason)) if v}
        if failure:
            out["failure"] = failure
        return {k: v for k, v in out.items() if v is not None}


def _minor_to_str(minor: Optional[int]) -> Optional[str]:
    if minor is None:
        return None
    return str((Decimal(int(minor)) / 100).quantize(Decimal("0.01")))


@dataclass(frozen=True)
class NormalizedGatewayEvent:
    """Provider-independent webhook/status event. Field names mirror what
    payment_service.process_webhook already needed from the raw sandbox
    payload; amount is kept as the provider's raw string (not Decimal) so
    the domain layer's existing `Decimal(amount_raw)` comparison semantics
    are unchanged by this refactor."""

    event_id: str
    status: NormalizedStatus
    gateway_order_ref: str
    amount_raw: str
    currency: Optional[str]
    # The provider's own status/event-type text (e.g. "payment.captured"),
    # kept only for storage in payment_webhook_events / diagnostics. Never
    # branched on outside the adapter that produced it — the domain layer
    # uses `status` exclusively (see module docstring, §15 normalization).
    raw_event_type: str = ""
    # Exactly `payload.get("issued_at")` for the sandbox today — None if
    # absent, otherwise whatever type the provider sent (freshness parsing/
    # error classification stays in payment_service, since max-age/skew
    # policy is a domain-wide security rule, not provider-specific).
    issued_at_raw: Any = None
    gateway_payment_ref: str = ""
    failure_code: str = "UNKNOWN"
    failure_message: str = "Payment failed"
    # Set only by a status query that found NO payment at all for the
    # provider order (hosted checkout opened and closed without paying).
    # `status` is still PAYMENT_PENDING for such an event, so a consumer that
    # ignores this flag behaves exactly as before; webhooks never set it.
    no_payment: bool = False
    # How the payment was made / why it failed, when the provider says.
    details: Optional[PaymentDetails] = None
    # Set for a refund event (e.g. Razorpay refund.processed). `status` is
    # then UNKNOWN: refund events never drive the payment state machine; the
    # refund domain applies `refund` instead.
    refund: Optional["NormalizedRefundResult"] = None


@dataclass(frozen=True)
class NormalizedRefundResult:
    """Provider-independent result of refund() / query_refund(). `amount_minor`
    is the refunded amount in the smallest currency unit as the provider
    reports it — the refund domain re-checks it against the internal row."""

    provider_refund_id: str
    status: "NormalizedRefundStatus"
    amount_minor: int
    currency: str
    raw_status: str = ""
    failure_reason: Optional[str] = None
    # The reference the customer quotes to their bank (ARN/RRN/UTR), once the
    # provider has one, and how the refund was actually sent (normal/instant).
    bank_reference: Optional[str] = None
    speed_processed: Optional[str] = None
    # The provider's payment id the refund belongs to (refund webhooks).
    provider_payment_id: str = ""
    # Our refund number (RFND-…) as sent in the refund's notes, when the
    # provider returns it. Tells our refunds apart when one payment has
    # several (one per cancelled guest).
    refund_number: Optional[str] = None


class GatewayError(Exception):
    """Base class for all gateway-layer errors."""


class GatewayWebhookUnparseableError(GatewayError):
    """Raised by parse_webhook() when the raw body is not a valid delivery
    for this gateway (e.g. malformed JSON)."""


class GatewayRefundRefusedError(GatewayError):
    """A refund call the provider refused or couldn't complete, with the
    reason classified (RefundFailureReason). Adapters raise this (or a
    subclass) from refund(); the refund domain decides retry vs. a person."""

    def __init__(self, reason: "RefundFailureReason", message: str = ""):
        self.reason = reason
        super().__init__(message or f"refund refused: {reason.value}")


class GatewayCapabilityNotSupportedError(GatewayError):
    """Raised when an operation is called on a gateway that does not
    declare that capability — e.g. refund() on the deterministic sandbox."""

    def __init__(self, gateway_name: str, capability: "GatewayCapability | str"):
        self.gateway_name = gateway_name
        self.capability = capability
        super().__init__(f"gateway {gateway_name!r} does not support {capability!r}")


class PaymentGateway(ABC):
    """Gateway-neutral contract every payment provider adapter implements.

    Subclasses must set `name` and `capabilities` as class attributes and
    implement the abstract methods. Operations not in `capabilities` should
    be left at their default implementation below, which raises
    GatewayCapabilityNotSupportedError — do not override an unsupported
    operation just to raise the same error more verbosely.
    """

    name: str
    capabilities: FrozenSet[GatewayCapability] = frozenset()
    # Sandbox-only testing concept (SUCCESS/FAILURE/PENDING/... simulated
    # outcomes). Empty for any gateway that doesn't have this concept — a
    # real provider determines its own outcome, the caller cannot select it.
    supported_scenarios: FrozenSet[str] = frozenset()

    def is_enabled(self, settings: Any) -> bool:
        """Whether this gateway may be used at all in the current
        environment. Default: always enabled. Adapters that carry real-money
        risk if reachable somewhere they shouldn't be (the sandbox, in a
        real production deployment) override this — see
        DeterministicSandboxGateway.is_enabled."""
        return True

    @abstractmethod
    def create_gateway_order_ref(self) -> str:
        """Generate an opaque reference used to correlate a later webhook
        back to the payment_attempts row that initiated it."""

    @abstractmethod
    def create_payment(
        self,
        *,
        gateway_order_ref: str,
        amount: Decimal,
        currency: str,
        scenario: Optional[str] = None,
        payment_mode: Optional[str] = None,
    ) -> GatewayInitiationResult:
        """Initiate a payment with this gateway. `scenario` is meaningful
        only to gateways that declare `supported_scenarios` (sandbox only).
        `payment_mode` ("test"/"live") selects which credential profile a
        mode-aware gateway (Razorpay) uses; adapters without that concept
        (the sandbox) ignore it."""

    @abstractmethod
    def verify_webhook(
        self, raw_body: bytes, signature: str, *, payment_mode: Optional[str] = None
    ) -> bool:
        """Cryptographically verify an inbound webhook delivery. Must not
        raise on a malformed/absent signature — return False. `payment_mode`
        selects which webhook secret a mode-aware gateway checks against;
        ignored by adapters without that concept."""

    @abstractmethod
    def parse_webhook(self, raw_body: bytes) -> NormalizedGatewayEvent:
        """Parse and normalize an inbound webhook body. Raises
        GatewayWebhookUnparseableError if the body cannot be parsed at all.
        Does not itself check the signature — callers must call
        verify_webhook independently (this mirrors the existing payment
        _service.process_webhook ordering: signature and parseability are
        independent checks)."""

    def verify_payment(self, **kwargs: Any) -> bool:
        """Client-return-based verification (e.g. a gateway.js callback
        signature). Deliberately unsupported by every adapter today: this
        architecture never treats a browser/app redirect or client-supplied
        reference as authoritative (see docs/payments — redirect security
        principle); payment truth comes from verify_webhook +
        query_payment_status only."""
        raise GatewayCapabilityNotSupportedError(self.name, GatewayCapability.VERIFY_PAYMENT)

    def query_payment_status(
        self, gateway_order_ref: str, *, payment_mode: Optional[str] = None
    ) -> NormalizedGatewayEvent:
        """Authoritative server-side status query against the gateway
        itself (for reconciliation / stuck-payment recovery). Not supported
        by the sandbox: there is no separate gateway-side state to query
        beyond what its own webhook already delivers, and fabricating one
        would be a fake production response. BLOCKED until a real gateway
        is selected — see REAL_GATEWAY_DECISION_REQUIRED."""
        raise GatewayCapabilityNotSupportedError(self.name, GatewayCapability.QUERY_PAYMENT_STATUS)

    def refund(
        self,
        *,
        provider_payment_id: str,
        amount_minor: int,
        currency: str,
        idempotency_key: str,
        payment_mode: Optional[str] = None,
        refund_number: Optional[str] = None,
    ) -> "NormalizedRefundResult":
        """Create a refund (full or partial) against a captured payment.
        `refund_number` is our RFND-… id, stored with the provider's refund. Adapters that
        declare GatewayCapability.REFUND override this. `idempotency_key` is
        a stable per-logical-refund string the adapter should forward to the
        provider's own idempotency mechanism where one exists (an extra
        safeguard — the database uniqueness on payment_refunds is the
        primary guarantee). `payment_mode` must match the mode the original
        payment was captured under — a mode-aware adapter resolves
        credentials from it and fails closed on a mismatch/missing value."""
        raise GatewayCapabilityNotSupportedError(self.name, GatewayCapability.REFUND)

    def query_refund(
        self,
        *,
        provider_payment_id: str,
        provider_refund_id: str,
        payment_mode: Optional[str] = None,
    ) -> "NormalizedRefundResult":
        """Authoritative provider-side refund status query, for refreshing a
        pending/processing refund."""
        raise GatewayCapabilityNotSupportedError(self.name, GatewayCapability.QUERY_REFUND)

    def verify_checkout_signature(
        self,
        *,
        provider_order_id: str,
        provider_payment_id: str,
        signature: str,
        payment_mode: Optional[str] = None,
    ) -> bool:
        """First gate for a hosted-checkout return: verify the client-echoed
        (order_id, payment_id, signature) triple cryptographically. This is
        NOT authoritative on its own — payment_service always follows a
        successful check with query_payment_status() against the provider
        before confirming anything. Adapters without hosted checkout leave
        this at the default (unsupported)."""
        raise GatewayCapabilityNotSupportedError(self.name, GatewayCapability.VERIFY_PAYMENT)

    def rebuild_checkout(
        self,
        *,
        gateway_order_ref: str,
        amount: Decimal,
        currency: str,
        payment_mode: Optional[str] = None,
    ) -> Optional[GatewayCheckout]:
        """Re-issue the frontend checkout payload for an attempt whose
        provider order already exists (the attendee closed hosted checkout
        without paying), without calling the provider. None when this
        gateway has no hosted checkout or `gateway_order_ref` is not a real
        provider order yet — callers then keep the one-unresolved-attempt
        rule. Default: None."""
        return None


def payload_hash(raw_body: bytes) -> str:
    """SHA-256 hex digest of a raw webhook body. Provider-independent
    (moved here from deterministic_sandbox — it was never sandbox-specific,
    just colocated with it)."""
    import hashlib

    return hashlib.sha256(raw_body).hexdigest()
