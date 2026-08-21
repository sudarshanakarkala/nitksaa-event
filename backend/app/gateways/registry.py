"""Server-controlled gateway registry.

Gateway selection comes from `Settings.payment_gateway_mode` (an env var —
trusted server-side configuration) only. No request path in this codebase
accepts a client-supplied gateway name for payment *initiation*; the webhook
route's `{gateway}` path segment identifies who is delivering the callback,
not who the attendee gets charged through, and is validated against this
same registry before payment_service ever sees it.

Registering a new gateway means adding one line to `_REGISTRY` and importing
its adapter — no other module should import a concrete gateway class.
"""
from typing import Dict, List

from app.gateways.base import GatewayError, PaymentGateway
from app.gateways.deterministic_sandbox import DeterministicSandboxGateway

_REGISTRY: Dict[str, PaymentGateway] = {}


def _register(gateway: PaymentGateway) -> None:
    _REGISTRY[gateway.name] = gateway


_register(DeterministicSandboxGateway())


class UnknownGatewayError(GatewayError):
    """The requested gateway name is not registered at all."""


class GatewayDisabledError(GatewayError):
    """The gateway is registered but not permitted in the current
    environment (e.g. sandbox reachable in a real production deployment)."""


def get_gateway(name: str) -> PaymentGateway:
    """Look up a registered gateway by name. Raises UnknownGatewayError for
    anything not registered — never falls back to a default gateway."""
    gateway = _REGISTRY.get(name)
    if gateway is None:
        raise UnknownGatewayError(name)
    return gateway


def get_enabled_gateway(name: str, settings) -> PaymentGateway:
    """Look up a gateway and confirm it is permitted in the current
    environment. Raises UnknownGatewayError / GatewayDisabledError — callers
    must not silently substitute another gateway on either error."""
    gateway = get_gateway(name)
    if not gateway.is_enabled(settings):
        raise GatewayDisabledError(name)
    return gateway


def get_active_gateway(settings) -> PaymentGateway:
    """The one gateway payment initiation is allowed to use, per
    server-side configuration (`settings.payment_gateway_mode`). This is the
    only function payment_service.create_attempt calls — there is no path
    from an attendee request to gateway selection."""
    return get_enabled_gateway(settings.payment_gateway_mode, settings)


def list_registered_gateways() -> List[str]:
    return sorted(_REGISTRY.keys())
