"""RazorpayGateway adapter — unit tests against the offline fake REST client.

No DB, no ASGI app. Proves the provider-vocabulary -> normalized mapping,
amount unit conversion, INR enforcement, fail-closed behaviour, raw-body
signature verification, and that no secret is ever returned.
"""
import json
from decimal import Decimal

import pytest
import requests

from app.gateways import razorpay_gateway as _rg
from tests import _razorpay_fakes as fakes

# The production seam, captured before any fixture swaps in the fake.
_REAL_BUILD_CLIENT = _rg._build_client


@pytest.fixture(autouse=True)
def _env(monkeypatch):
    fakes.set_razorpay_env(monkeypatch)
    fakes.install(monkeypatch)
    yield
    from app.config import get_settings
    get_settings.cache_clear()


def _gw():
    from app.gateways.razorpay_gateway import RazorpayGateway
    return RazorpayGateway()


# ── registration / capabilities ──────────────────────────────────────────

def test_adapter_registered_in_registry():
    from app.gateways import registry
    assert "razorpay" in registry.list_registered_gateways()
    gw = registry.get_gateway("razorpay")
    from app.gateways.base import GatewayCapability
    for cap in (GatewayCapability.CREATE_PAYMENT, GatewayCapability.VERIFY_WEBHOOK,
                GatewayCapability.PROCESS_WEBHOOK, GatewayCapability.QUERY_PAYMENT_STATUS,
                GatewayCapability.REFUND, GatewayCapability.QUERY_REFUND,
                GatewayCapability.VERIFY_PAYMENT):
        assert cap in gw.capabilities


# ── fail closed ──────────────────────────────────────────────────────────

def test_is_enabled_false_without_credentials(monkeypatch):
    from app.config import get_settings
    # setenv("") — an explicit empty env var overrides any value coming from
    # backend/.env (env source outranks the dotenv source in pydantic-settings),
    # so this stays correct whether or not real creds are present locally.
    fakes.clear_razorpay_env(monkeypatch)
    assert get_settings().razorpay_configured is False
    assert _gw().is_enabled(get_settings()) is False


def test_is_enabled_true_with_test_credentials():
    from app.config import get_settings
    assert _gw().is_enabled(get_settings()) is True


def test_is_enabled_true_for_live_deployment_with_live_key(monkeypatch):
    from app.config import get_settings
    fakes.set_razorpay_live_env(monkeypatch)
    assert _gw().is_enabled(get_settings()) is True


# ── single active credential set (RAZORPAY_MODE) ────────────────────────

def _create(payment_mode):
    return _gw().create_payment(
        gateway_order_ref="r", amount=Decimal("1.00"), currency="INR", payment_mode=payment_mode
    )


def test_test_deployment_with_test_key_works():
    from app.config import get_settings
    from app.gateways.razorpay_gateway import _resolve_credentials
    assert _resolve_credentials(get_settings(), "test") == ("rzp_test_fake", "secret_fake", "whsec_fake")
    assert _create("test").checkout.key_id == "rzp_test_fake"


def test_test_deployment_with_live_key_fails_closed(monkeypatch):
    from app.config import get_settings
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    fakes.set_razorpay_env(monkeypatch, key_id="rzp_live_wrongprefix", mode="test")
    assert _gw().is_enabled(get_settings()) is False
    with pytest.raises(RazorpayModeCredentialError, match="rzp_test_"):
        _create("test")


def test_live_deployment_with_live_key_works(monkeypatch):
    # Fake credentials and the offline fake REST client only.
    from app.config import get_settings
    from app.gateways.razorpay_gateway import _resolve_credentials
    fakes.set_razorpay_live_env(monkeypatch)
    assert _resolve_credentials(get_settings(), "live") == (
        "rzp_live_fake", "live_secret_fake", "live_whsec_fake"
    )
    gw = _gw()
    assert _create("live").checkout.key_id == "rzp_live_fake"
    sig = fakes.checkout_signature("order_X", "pay_Y", key_secret="live_secret_fake")
    assert gw.verify_checkout_signature(
        provider_order_id="order_X", provider_payment_id="pay_Y", signature=sig, payment_mode="live"
    ) is True
    raw, wsig = fakes.webhook_body_and_sig("payment.captured", order_id="order_1", webhook_secret="live_whsec_fake")
    assert gw.verify_webhook(raw, wsig, payment_mode="live") is True
    res = gw.refund(provider_payment_id="pay_1", amount_minor=100, currency="INR",
                    idempotency_key="k", payment_mode="live")
    assert res.status.value == "REFUND_PROCESSED"


def test_live_deployment_with_test_key_fails_closed(monkeypatch):
    from app.config import get_settings
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    fakes.set_razorpay_live_env(monkeypatch, key_id="rzp_test_wrongprefix")
    assert _gw().is_enabled(get_settings()) is False
    with pytest.raises(RazorpayModeCredentialError, match="rzp_live_"):
        _create("live")


@pytest.mark.parametrize("deployment_mode,payment_mode", [("test", "live"), ("live", "test")])
def test_payment_mode_other_than_deployment_mode_fails_closed(monkeypatch, deployment_mode, payment_mode):
    """The active credentials are valid, yet a payment/refund/webhook
    recorded under the other mode must never be served with them."""
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    if deployment_mode == "live":
        fakes.set_razorpay_live_env(monkeypatch)
        secret, whsec = "live_secret_fake", "live_whsec_fake"
    else:
        secret, whsec = "secret_fake", "whsec_fake"
    gw = _gw()

    with pytest.raises(RazorpayModeCredentialError, match="RAZORPAY_MODE"):
        _create(payment_mode)
    with pytest.raises(RazorpayModeCredentialError):
        gw.query_payment_status("order_1", payment_mode=payment_mode)
    with pytest.raises(RazorpayModeCredentialError):
        gw.refund(provider_payment_id="pay_1", amount_minor=100, currency="INR",
                  idempotency_key="k", payment_mode=payment_mode)
    with pytest.raises(RazorpayModeCredentialError):
        gw.query_refund(provider_payment_id="pay_1", provider_refund_id="rfnd_1", payment_mode=payment_mode)

    # Signed with the ACTIVE secrets, yet rejected: a mismatched mode never
    # reaches them. The same deliveries verify under the deployment's mode.
    sig = fakes.checkout_signature("order_X", "pay_Y", key_secret=secret)
    raw, wsig = fakes.webhook_body_and_sig("payment.captured", order_id="order_1", webhook_secret=whsec)
    for mode, expected in ((payment_mode, False), (deployment_mode, True)):
        assert gw.verify_checkout_signature(
            provider_order_id="order_X", provider_payment_id="pay_Y", signature=sig, payment_mode=mode
        ) is expected
        assert gw.verify_webhook(raw, wsig, payment_mode=mode) is expected


@pytest.mark.parametrize("payment_mode", [None, "", "staging", "LIVE"])
def test_unknown_payment_mode_fails_closed(payment_mode):
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    with pytest.raises(RazorpayModeCredentialError, match="payment_mode"):
        _create(payment_mode)


@pytest.mark.parametrize("mode", ["", "TEST", "production", "sandbox"])
def test_invalid_razorpay_mode_fails_closed(monkeypatch, mode):
    from app.config import get_settings
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError, _resolve_credentials
    fakes.set_razorpay_env(monkeypatch, mode=mode)
    assert get_settings().razorpay_configured is False
    assert _gw().is_enabled(get_settings()) is False
    for payment_mode in ("test", "live"):
        with pytest.raises(RazorpayModeCredentialError, match="RAZORPAY_MODE"):
            _resolve_credentials(get_settings(), payment_mode)


@pytest.mark.parametrize("missing", ["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET"])
def test_missing_key_id_or_secret_fails_closed(monkeypatch, missing):
    from app.config import get_settings
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    monkeypatch.setenv(missing, "")
    get_settings.cache_clear()
    gw = _gw()
    assert get_settings().razorpay_configured is False
    assert gw.is_enabled(get_settings()) is False
    with pytest.raises(RazorpayModeCredentialError, match="not configured"):
        _create("test")
    with pytest.raises(RazorpayModeCredentialError):
        gw.refund(provider_payment_id="pay_1", amount_minor=100, currency="INR",
                  idempotency_key="k", payment_mode="test")
    sig = fakes.checkout_signature("order_X", "pay_Y")
    assert gw.verify_checkout_signature(
        provider_order_id="order_X", provider_payment_id="pay_Y", signature=sig, payment_mode="test"
    ) is False


def test_missing_webhook_secret_rejects_every_webhook(monkeypatch):
    from app.config import get_settings
    monkeypatch.setenv("RAZORPAY_WEBHOOK_SECRET", "")
    get_settings.cache_clear()
    raw, sig = fakes.webhook_body_and_sig("payment.captured", order_id="order_1")
    assert _gw().verify_webhook(raw, sig, payment_mode="test") is False
    # nor may a delivery "signed" with the empty secret pass
    raw, sig = fakes.webhook_body_and_sig("payment.captured", order_id="order_1", webhook_secret="")
    assert _gw().verify_webhook(raw, sig, payment_mode="test") is False


def test_removed_dual_profile_vars_are_ignored(monkeypatch):
    """The old per-mode vars are no longer settings: leftovers in an old
    .env or deployment must never activate a credential set."""
    from app.config import get_settings
    fakes.clear_razorpay_env(monkeypatch)
    for name, value in (
        ("RAZORPAY_TEST_KEY_ID", "rzp_test_leftover"), ("RAZORPAY_TEST_KEY_SECRET", "leftover"),
        ("RAZORPAY_LIVE_KEY_ID", "rzp_live_leftover"), ("RAZORPAY_LIVE_KEY_SECRET", "leftover"),
    ):
        monkeypatch.setenv(name, value)
    get_settings.cache_clear()
    settings = get_settings()
    assert settings.razorpay_configured is False
    assert settings.razorpay_credentials_for("test") == ("", "", "")
    assert settings.razorpay_credentials_for("live") == ("", "", "")


# ── amount conversion / INR ──────────────────────────────────────────────

@pytest.mark.parametrize("rupees,paise", [("1.00", 100), ("1", 100), ("1.5", 150),
                                          ("100.00", 10000), ("0.01", 1), ("2499.99", 249999)])
def test_rupees_to_paise(rupees, paise):
    from app.gateways.razorpay_gateway import rupees_to_paise
    assert rupees_to_paise(Decimal(rupees)) == paise


def test_create_payment_one_rupee_is_100_paise():
    gw = _gw()
    res = gw.create_payment(
        gateway_order_ref="rcpt-1", amount=Decimal("1.00"), currency="INR", payment_mode="test"
    )
    assert res.checkout is not None
    assert res.checkout.amount_minor == 100
    assert res.checkout.currency == "INR"
    assert res.gateway_order_ref.startswith("order_")
    assert res.checkout.provider_order_id == res.gateway_order_ref
    # neither webhook field — hosted checkout, not in-process
    assert res.immediate_webhook is None and res.delayed_webhook is None


def test_create_payment_rejects_non_inr():
    from app.gateways.base import GatewayError
    with pytest.raises(GatewayError):
        _gw().create_payment(
            gateway_order_ref="r", amount=Decimal("1.00"), currency="USD", payment_mode="test"
        )


def test_checkout_payload_carries_no_secret():
    res = _gw().create_payment(
        gateway_order_ref="r", amount=Decimal("1.00"), currency="INR", payment_mode="test"
    )
    blob = repr(res)
    assert "secret_fake" not in blob
    assert "whsec_fake" not in blob
    assert res.checkout.key_id == "rzp_test_fake"


def test_live_checkout_payload_carries_no_secret(monkeypatch):
    fakes.set_razorpay_live_env(monkeypatch)
    res = _create("live")
    blob = repr(res)
    assert "live_secret_fake" not in blob
    assert "live_whsec_fake" not in blob
    assert res.checkout.key_id == "rzp_live_fake"


def test_credential_errors_never_contain_secrets(monkeypatch):
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    fakes.set_razorpay_env(monkeypatch, key_id="rzp_live_wrongprefix",
                           key_secret="s3cr3t_value", webhook_secret="wh_s3cr3t_value")
    for payment_mode in (None, "test", "live"):
        with pytest.raises(RazorpayModeCredentialError) as exc:
            _create(payment_mode)
        assert "s3cr3t" not in str(exc.value)
        assert "wrongprefix" not in str(exc.value)


# ── checkout signature (first gate) ──────────────────────────────────────

def test_checkout_signature_valid_and_invalid():
    gw = _gw()
    good = fakes.checkout_signature("order_X", "pay_Y")
    assert gw.verify_checkout_signature(provider_order_id="order_X", provider_payment_id="pay_Y", signature=good, payment_mode="test") is True
    assert gw.verify_checkout_signature(provider_order_id="order_X", provider_payment_id="pay_Y", signature="deadbeef", payment_mode="test") is False
    # tampered payment id -> signature no longer matches
    assert gw.verify_checkout_signature(provider_order_id="order_X", provider_payment_id="pay_TAMPER", signature=good, payment_mode="test") is False
    assert gw.verify_checkout_signature(provider_order_id="order_X", provider_payment_id="pay_Y", signature="", payment_mode="test") is False


# ── webhook raw-body signature ──────────────────────────────────────────

def test_webhook_signature_over_raw_bytes():
    gw = _gw()
    raw, sig = fakes.webhook_body_and_sig("payment.captured", order_id="order_1", amount_paise=100)
    assert gw.verify_webhook(raw, sig, payment_mode="test") is True
    # any mutation of the bytes breaks it
    assert gw.verify_webhook(raw + b" ", sig, payment_mode="test") is False
    assert gw.verify_webhook(raw, "00" + sig[2:], payment_mode="test") is False
    assert gw.verify_webhook(raw, "", payment_mode="test") is False


def test_parse_webhook_maps_events_and_converts_amount():
    from app.gateways.base import NormalizedStatus
    gw = _gw()
    raw, _ = fakes.webhook_body_and_sig("payment.captured", order_id="order_9", payment_id="pay_9", amount_paise=100)
    ev = gw.parse_webhook(raw)
    assert ev.status == NormalizedStatus.PAYMENT_SUCCESS
    assert ev.gateway_order_ref == "order_9"
    assert ev.gateway_payment_ref == "pay_9"
    assert Decimal(ev.amount_raw) == Decimal("1.00")   # 100 paise -> ₹1.00
    assert ev.event_id == "payment.captured:pay_9"      # body-derived dedupe id
    assert ev.issued_at_raw is not None

    raw_f, _ = fakes.webhook_body_and_sig("payment.failed", order_id="order_9", payment_id="pay_9")
    assert gw.parse_webhook(raw_f).status == NormalizedStatus.PAYMENT_FAILED


def test_parse_webhook_unparseable_raises():
    from app.gateways.base import GatewayWebhookUnparseableError
    with pytest.raises(GatewayWebhookUnparseableError):
        _gw().parse_webhook(b"not json")


def test_parse_webhook_unknown_event_is_unknown_not_crash():
    from app.gateways.base import NormalizedStatus
    raw, _ = fakes.webhook_body_and_sig("payment.dispute.created", order_id="order_1")
    assert _gw().parse_webhook(raw).status == NormalizedStatus.UNKNOWN


# ── query payment status ────────────────────────────────────────────────

@pytest.mark.parametrize("provider_status,expected", [
    ("captured", "PAYMENT_SUCCESS"),
    ("failed", "PAYMENT_FAILED"),
    ("authorized", "PAYMENT_PENDING"),
])
def test_query_payment_status_mapping(provider_status, expected):
    fakes.STATE["payment_status"] = provider_status
    fakes._ORDERS["order_qp"] = {"amount": 100, "currency": "INR"}
    ev = _gw().query_payment_status("order_qp", payment_mode="test")
    assert ev.status.value == expected
    assert Decimal(ev.amount_raw) == Decimal("1.00")


def test_query_payment_status_no_payments_is_pending_not_crash():
    from app.gateways.base import NormalizedStatus
    fakes.STATE["payments_empty"] = True
    ev = _gw().query_payment_status("order_none", payment_mode="test")
    assert ev.status == NormalizedStatus.PAYMENT_PENDING


# ── refunds ────────────────────────────────────────────────────────────

@pytest.mark.parametrize("provider_status,expected", [
    ("processed", "REFUND_PROCESSED"),
    ("pending", "REFUND_PENDING"),
    ("failed", "REFUND_FAILED"),
])
def test_refund_status_mapping(provider_status, expected):
    fakes.STATE["refund_status"] = provider_status
    res = _gw().refund(provider_payment_id="pay_1", amount_minor=100, currency="INR",
                       idempotency_key="refund:order:1", payment_mode="test")
    assert res.status.value == expected
    assert res.amount_minor == 100
    assert res.provider_refund_id.startswith("rfnd_")


def test_refund_rejects_non_inr():
    from app.gateways.base import GatewayError
    with pytest.raises(GatewayError):
        _gw().refund(provider_payment_id="pay_1", amount_minor=100, currency="USD",
                     idempotency_key="k", payment_mode="test")


def test_refund_provider_error_propagates_as_gateway_error():
    from app.gateways.base import GatewayError
    fakes.STATE["refund_raises"] = True
    with pytest.raises(GatewayError):
        _gw().refund(provider_payment_id="pay_1", amount_minor=100, currency="INR",
                     idempotency_key="k", payment_mode="test")


def test_query_refund_mapping():
    fakes._REFUNDS["rfnd_q"] = {"id": "rfnd_q", "amount": 100, "currency": "INR", "status": "processed"}
    fakes.STATE["refund_status"] = "processed"
    res = _gw().query_refund(provider_payment_id="pay_1", provider_refund_id="rfnd_q", payment_mode="test")
    assert res.status.value == "REFUND_PROCESSED"


# ── official SDK surface (SDK-shaped fake) ──────────────────────────────

def _timeout():
    from app.config import get_settings
    return get_settings().razorpay_http_timeout_seconds


def test_create_payment_uses_sdk_order_create():
    _create("test")
    (call,) = fakes.CALLS
    assert call["method"] == "order.create"
    assert call["data"] == {"amount": 100, "currency": "INR", "receipt": "r",
                            "payment_capture": 1, "notes": {"source": "nitksaa-event"}}
    assert call["kwargs"] == {"timeout": _timeout()}


def test_query_payment_status_uses_sdk_order_payments():
    _gw().query_payment_status("order_qp", payment_mode="test")
    (call,) = fakes.CALLS
    assert (call["method"], call["args"], call["kwargs"]) == (
        "order.payments", ("order_qp",), {"timeout": _timeout()}
    )


def test_refund_uses_sdk_payment_refund_with_idempotency_key():
    _gw().refund(provider_payment_id="pay_1", amount_minor=100, currency="INR",
                 idempotency_key="refund:order:1", payment_mode="test")
    (call,) = fakes.CALLS
    assert (call["method"], call["args"]) == ("payment.refund", ("pay_1",))
    assert call["data"] == {"amount": 100, "speed": "normal",
                            "notes": {"reason": "attendee_cancellation"}}
    assert call["kwargs"] == {"headers": {"Idempotency-Key": "refund:order:1"}, "timeout": _timeout()}


def test_query_refund_uses_sdk_refund_fetch():
    _gw().query_refund(provider_payment_id="pay_1", provider_refund_id="rfnd_q", payment_mode="test")
    (call,) = fakes.CALLS
    assert (call["method"], call["args"], call["kwargs"]) == (
        "refund.fetch", ("rfnd_q",), {"timeout": _timeout()}
    )


def test_sdk_exception_is_converted_without_its_text():
    from app.gateways.razorpay_gateway import RazorpayApiError
    fakes.STATE["orders_create_raises"] = True
    with pytest.raises(RazorpayApiError) as exc:
        _create("test")
    assert exc.value.code == "SERVER_ERROR"
    assert "4111" not in str(exc.value) and "payer@" not in str(exc.value)
    assert exc.value.__cause__ is None and exc.value.__context__ is None


def test_checkout_signature_non_ascii_is_rejected_not_raised():
    assert _gw().verify_checkout_signature(
        provider_order_id="order_X", provider_payment_id="pay_Y", signature="é" * 64, payment_mode="test"
    ) is False


def test_webhook_non_utf8_body_or_non_ascii_signature_is_rejected_not_raised():
    gw = _gw()
    raw, sig = fakes.webhook_body_and_sig("payment.captured", order_id="order_1")
    assert gw.verify_webhook(b"\xff\xfe" + raw, sig, payment_mode="test") is False
    assert gw.verify_webhook(raw, "é" * 64, payment_mode="test") is False


# ── real razorpay.Client, in-process transport (no network) ─────────────

class _Transport:
    """Stands in for requests.Session.request under the REAL razorpay.Client:
    the SDK's own URL building, auth, header/timeout forwarding and error
    mapping all run, but every request is recorded and answered here."""

    def __init__(self):
        self.calls = []
        self.status = 200
        self.body = {}
        self.raises = None

    def __call__(self, method, url, **kwargs):
        self.calls.append({"method": method, "url": url, **kwargs})
        if self.raises is not None:
            raise self.raises
        resp = requests.Response()
        resp.status_code = self.status
        resp._content = self.body if isinstance(self.body, bytes) else json.dumps(self.body).encode()
        return resp


@pytest.fixture
def sdk(monkeypatch):
    monkeypatch.setattr(_rg, "_build_client", _REAL_BUILD_CLIENT)
    transport = _Transport()
    monkeypatch.setattr(requests.Session, "request", transport)
    return transport


def test_build_client_is_the_official_sdk_client(sdk):
    import razorpay
    from app.config import get_settings
    client = _rg._build_client(get_settings(), "test")
    assert isinstance(client, razorpay.Client)
    assert client.auth == ("rzp_test_fake", "secret_fake")
    assert client.retry_enabled is False


def test_real_sdk_order_create_request(sdk):
    sdk.body = {"id": "order_sdk1", "amount": 100, "currency": "INR", "status": "created"}
    res = _create("test")
    assert res.gateway_order_ref == "order_sdk1"
    assert res.checkout.key_id == "rzp_test_fake"
    (call,) = sdk.calls
    assert (call["method"], call["url"]) == ("POST", "https://api.razorpay.com/v1/orders")
    assert call["auth"] == ("rzp_test_fake", "secret_fake")
    assert call["timeout"] == _timeout()
    assert json.loads(call["data"])["amount"] == 100


def test_real_sdk_order_payments_request(sdk):
    from app.gateways.base import NormalizedStatus
    sdk.body = {"count": 1, "items": [{"id": "pay_1", "order_id": "order_1", "amount": 100,
                                       "currency": "INR", "status": "captured"}]}
    ev = _gw().query_payment_status("order_1", payment_mode="test")
    assert ev.status == NormalizedStatus.PAYMENT_SUCCESS
    (call,) = sdk.calls
    assert (call["method"], call["url"]) == ("GET", "https://api.razorpay.com/v1/orders/order_1/payments")
    assert call["timeout"] == _timeout()


def test_real_sdk_refund_sends_idempotency_key_header(sdk):
    sdk.body = {"id": "rfnd_1", "amount": 100, "currency": "INR", "status": "processed"}
    res = _gw().refund(provider_payment_id="pay_1", amount_minor=100, currency="INR",
                       idempotency_key="refund:order:42", payment_mode="test")
    assert res.status.value == "REFUND_PROCESSED"
    (call,) = sdk.calls
    assert (call["method"], call["url"]) == ("POST", "https://api.razorpay.com/v1/payments/pay_1/refund")
    assert call["headers"]["Idempotency-Key"] == "refund:order:42"
    assert json.loads(call["data"]) == {"amount": 100, "speed": "normal",
                                        "notes": {"reason": "attendee_cancellation"}}
    assert call["timeout"] == _timeout()


def test_real_sdk_refund_fetch_request(sdk):
    sdk.body = {"id": "rfnd_1", "amount": 100, "currency": "INR", "status": "pending"}
    res = _gw().query_refund(provider_payment_id="pay_1", provider_refund_id="rfnd_1", payment_mode="test")
    assert res.status.value == "REFUND_PENDING"
    (call,) = sdk.calls
    assert (call["method"], call["url"]) == ("GET", "https://api.razorpay.com/v1/refunds/rfnd_1")


@pytest.mark.parametrize("api_base", [
    "https://mock.razorpay.test/v1", "https://mock.razorpay.test/v1/", "https://mock.razorpay.test",
])
def test_real_sdk_honours_api_base_and_timeout_settings(monkeypatch, sdk, api_base):
    from app.config import get_settings
    monkeypatch.setenv("RAZORPAY_API_BASE", api_base)
    monkeypatch.setenv("RAZORPAY_HTTP_TIMEOUT_SECONDS", "7.5")
    get_settings.cache_clear()
    sdk.body = {"id": "order_b", "amount": 100, "currency": "INR"}
    _create("test")
    (call,) = sdk.calls
    assert call["url"] == "https://mock.razorpay.test/v1/orders"
    assert call["timeout"] == 7.5


_SENSITIVE = "card 4111-1111 payer@example.com secret_fake"


@pytest.mark.parametrize("status,body,raises,code", [
    (400, {"error": {"code": "BAD_REQUEST_ERROR", "description": _SENSITIVE}}, None, "BAD_REQUEST_ERROR"),
    (502, {"error": {"code": "GATEWAY_ERROR", "description": _SENSITIVE}}, None, "GATEWAY_ERROR"),
    (500, {"error": {"code": "SERVER_ERROR", "description": _SENSITIVE}}, None, "SERVER_ERROR"),
    (502, f"<html>{_SENSITIVE}</html>".encode(), None, "TRANSPORT_ERROR"),
    (204, b"", None, "UNEXPECTED_RESPONSE"),
    (200, {}, requests.exceptions.ConnectionError(_SENSITIVE), "TRANSPORT_ERROR"),
    (200, {}, requests.exceptions.ReadTimeout(_SENSITIVE), "TIMEOUT"),
])
def test_real_sdk_errors_are_sanitized(sdk, capsys, status, body, raises, code):
    from app.gateways.base import GatewayError
    from app.gateways.razorpay_gateway import RazorpayApiError
    sdk.status, sdk.body, sdk.raises = status, body, raises
    with pytest.raises(RazorpayApiError) as exc:
        _gw().refund(provider_payment_id="pay_1", amount_minor=100, currency="INR",
                     idempotency_key="k", payment_mode="test")
    err = exc.value
    assert isinstance(err, GatewayError)          # payment/refund services catch this
    assert err.code == code and err.operation == "payments.refund"
    for text in (str(err), repr(err), capsys.readouterr().out):
        assert "4111" not in text and "payer@" not in text and "secret_fake" not in text
    assert err.__cause__ is None and err.__context__ is None


def test_real_sdk_checkout_signature_verification(sdk):
    gw = _gw()
    good = fakes.checkout_signature("order_X", "pay_Y")
    kw = dict(provider_order_id="order_X", provider_payment_id="pay_Y", payment_mode="test")
    assert gw.verify_checkout_signature(signature=good, **kw) is True
    assert gw.verify_checkout_signature(signature="deadbeef", **kw) is False
    assert gw.verify_checkout_signature(signature="é" * 64, **kw) is False
    assert sdk.calls == []   # verification is local HMAC, never a network call


def test_real_sdk_webhook_signature_verification(sdk):
    gw = _gw()
    raw, sig = fakes.webhook_body_and_sig("payment.captured", order_id="order_1")
    assert gw.verify_webhook(raw, sig, payment_mode="test") is True
    assert gw.verify_webhook(raw + b" ", sig, payment_mode="test") is False
    assert gw.verify_webhook(b"\xff" + raw, sig, payment_mode="test") is False
    assert gw.verify_webhook(raw, "é" * 64, payment_mode="test") is False
    assert sdk.calls == []


# ── rebuild_checkout (retry after Checkout was closed) ──────────────────

def test_rebuild_checkout_reissues_same_order_without_any_sdk_call():
    c = _gw().rebuild_checkout(
        gateway_order_ref="order_abc123", amount=Decimal("1.00"), currency="INR", payment_mode="test"
    )
    assert (c.provider_order_id, c.key_id, c.amount_minor, c.currency) == ("order_abc123", "rzp_test_fake", 100, "INR")
    assert fakes.CALLS == []
    assert "secret_fake" not in repr(c) and "whsec_fake" not in repr(c)


@pytest.mark.parametrize("ref", ["rzp_pending_abc123", "", "sbx_ord_abc123"])
def test_rebuild_checkout_never_exposes_a_non_razorpay_ref(ref):
    assert _gw().rebuild_checkout(
        gateway_order_ref=ref, amount=Decimal("1.00"), currency="INR", payment_mode="test"
    ) is None


def test_rebuild_checkout_fails_closed_on_mode_mismatch_and_non_inr():
    from app.gateways.base import GatewayError
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    with pytest.raises(RazorpayModeCredentialError):
        _gw().rebuild_checkout(gateway_order_ref="order_abc", amount=Decimal("1.00"), currency="INR", payment_mode="live")
    with pytest.raises(GatewayError):
        _gw().rebuild_checkout(gateway_order_ref="order_abc", amount=Decimal("1.00"), currency="USD", payment_mode="test")


def test_sandbox_gateway_has_no_checkout_to_rebuild():
    from app.gateways.deterministic_sandbox import DeterministicSandboxGateway
    assert DeterministicSandboxGateway().rebuild_checkout(
        gateway_order_ref="sbx_ord_abc", amount=Decimal("1.00"), currency="INR"
    ) is None


@pytest.mark.parametrize("empty,provider_status,expected_no_payment", [
    (True, "captured", True),
    (False, "authorized", False),
    (False, "captured", False),
    (False, "failed", False),
])
def test_query_payment_status_flags_only_an_order_with_no_payment(empty, provider_status, expected_no_payment):
    fakes.STATE["payments_empty"] = empty
    fakes.STATE["payment_status"] = provider_status
    fakes._ORDERS["order_np"] = {"amount": 100, "currency": "INR"}
    ev = _gw().query_payment_status("order_np", payment_mode="test")
    assert ev.no_payment is expected_no_payment
