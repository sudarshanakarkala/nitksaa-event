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
class GatewayInitiationResult:
    """Result of PaymentGateway.create_payment(). Exactly one of
    immediate_webhook / delayed_webhook is set today, because the only
    adapter that exists (deterministic sandbox) simulates the whole round
    trip itself. A real hosted-checkout gateway would instead populate a
    (not-yet-defined) redirect/checkout field here and set neither webhook
    field — deferred until a real provider is selected (see
    REAL_GATEWAY_DECISION_REQUIRED), since adding that field now with no
    consumer or adapter to exercise it would be speculative."""

    gateway_order_ref: str
    immediate_webhook: Optional[SignedWebhookDelivery] = None
    delayed_webhook: Optional[DelayedWebhookDelivery] = None


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


class GatewayError(Exception):
    """Base class for all gateway-layer errors."""


class GatewayWebhookUnparseableError(GatewayError):
    """Raised by parse_webhook() when the raw body is not a valid delivery
    for this gateway (e.g. malformed JSON)."""


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
    ) -> GatewayInitiationResult:
        """Initiate a payment with this gateway. `scenario` is meaningful
        only to gateways that declare `supported_scenarios` (sandbox only)."""

    @abstractmethod
    def verify_webhook(self, raw_body: bytes, signature: str) -> bool:
        """Cryptographically verify an inbound webhook delivery. Must not
        raise on a malformed/absent signature — return False."""

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

    def query_payment_status(self, gateway_order_ref: str) -> NormalizedGatewayEvent:
        """Authoritative server-side status query against the gateway
        itself (for reconciliation / stuck-payment recovery). Not supported
        by the sandbox: there is no separate gateway-side state to query
        beyond what its own webhook already delivers, and fabricating one
        would be a fake production response. BLOCKED until a real gateway
        is selected — see REAL_GATEWAY_DECISION_REQUIRED."""
        raise GatewayCapabilityNotSupportedError(self.name, GatewayCapability.QUERY_PAYMENT_STATUS)

    def refund(self, **kwargs: Any) -> Any:
        """Out of scope for this sprint by explicit instruction — declared
        on the interface for future capability discovery only."""
        raise GatewayCapabilityNotSupportedError(self.name, GatewayCapability.REFUND)

    def query_refund(self, **kwargs: Any) -> Any:
        raise GatewayCapabilityNotSupportedError(self.name, GatewayCapability.QUERY_REFUND)


def payload_hash(raw_body: bytes) -> str:
    """SHA-256 hex digest of a raw webhook body. Provider-independent
    (moved here from deterministic_sandbox — it was never sandbox-specific,
    just colocated with it)."""
    import hashlib

    return hashlib.sha256(raw_body).hexdigest()
