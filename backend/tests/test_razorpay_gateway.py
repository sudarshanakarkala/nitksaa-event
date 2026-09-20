"""RazorpayGateway adapter — unit tests against the offline fake REST client.

No DB, no ASGI app. Proves the provider-vocabulary -> normalized mapping,
amount unit conversion, INR enforcement, fail-closed behaviour, raw-body
signature verification, and that no secret is ever returned.
"""
from decimal import Decimal

import pytest

from tests import _razorpay_fakes as fakes


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
    # so this stays correct whether or not real test/live creds are present
    # locally. is_enabled() is True if EITHER profile is configured, so every
    # credential var (legacy + TEST + LIVE) must be blanked here.
    fakes.clear_razorpay_env(monkeypatch)
    assert get_settings().razorpay_configured is False
    assert _gw().is_enabled(get_settings()) is False


def test_is_enabled_true_with_test_credentials():
    from app.config import get_settings
    assert _gw().is_enabled(get_settings()) is True


def test_is_enabled_true_with_only_live_credentials(monkeypatch):
    from app.config import get_settings
    fakes.clear_razorpay_env(monkeypatch)
    fakes.set_razorpay_live_env(monkeypatch)
    assert _gw().is_enabled(get_settings()) is True


def test_is_enabled_false_with_no_credentials_at_all(monkeypatch):
    from app.config import get_settings
    fakes.clear_razorpay_env(monkeypatch)
    assert _gw().is_enabled(get_settings()) is False


# ── mode-aware credential resolution (TEST/LIVE separation) ─────────────

def test_call_without_payment_mode_fails_closed():
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    with pytest.raises(RazorpayModeCredentialError):
        _gw().create_payment(gateway_order_ref="r", amount=Decimal("1.00"), currency="INR")


def test_call_with_unknown_payment_mode_fails_closed():
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    with pytest.raises(RazorpayModeCredentialError):
        _gw().create_payment(
            gateway_order_ref="r", amount=Decimal("1.00"), currency="INR", payment_mode="staging"
        )


def test_live_mode_without_live_credentials_fails_closed(monkeypatch):
    from app.config import get_settings
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    # Only TEST creds configured (autouse fixture) — explicitly blank
    # RAZORPAY_LIVE_* so this holds regardless of whether real Live
    # credentials happen to be configured in local backend/.env.
    monkeypatch.setenv("RAZORPAY_LIVE_KEY_ID", "")
    monkeypatch.setenv("RAZORPAY_LIVE_KEY_SECRET", "")
    monkeypatch.setenv("RAZORPAY_LIVE_WEBHOOK_SECRET", "")
    get_settings.cache_clear()
    with pytest.raises(RazorpayModeCredentialError):
        _gw().create_payment(
            gateway_order_ref="r", amount=Decimal("1.00"), currency="INR", payment_mode="live"
        )


def test_live_mode_with_test_prefixed_key_fails_closed(monkeypatch):
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    # a misconfigured live profile carrying a rzp_test_ key must never be used.
    fakes.set_razorpay_live_env(monkeypatch, key_id="rzp_test_wrongprefix")
    with pytest.raises(RazorpayModeCredentialError):
        _gw().create_payment(
            gateway_order_ref="r", amount=Decimal("1.00"), currency="INR", payment_mode="live"
        )


def test_test_mode_with_live_prefixed_key_fails_closed(monkeypatch):
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    fakes.clear_razorpay_env(monkeypatch)
    fakes.set_razorpay_test_env(monkeypatch, key_id="rzp_live_wrongprefix")
    with pytest.raises(RazorpayModeCredentialError):
        _gw().create_payment(
            gateway_order_ref="r", amount=Decimal("1.00"), currency="INR", payment_mode="test"
        )


def test_live_mode_never_falls_back_to_test_credentials(monkeypatch):
    """A live call must fail closed even though valid TEST credentials exist
    — there is no cross-mode fallback in either direction."""
    from app.config import get_settings
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError
    monkeypatch.setenv("RAZORPAY_LIVE_KEY_ID", "")
    monkeypatch.setenv("RAZORPAY_LIVE_KEY_SECRET", "")
    monkeypatch.setenv("RAZORPAY_LIVE_WEBHOOK_SECRET", "")
    get_settings.cache_clear()
    with pytest.raises(RazorpayModeCredentialError):
        _gw().create_payment(
            gateway_order_ref="r", amount=Decimal("1.00"), currency="INR", payment_mode="live"
        )


def test_live_mode_create_payment_uses_live_key(monkeypatch):
    fakes.set_razorpay_live_env(monkeypatch)
    res = _gw().create_payment(
        gateway_order_ref="r", amount=Decimal("1.00"), currency="INR", payment_mode="live"
    )
    assert res.checkout.key_id == "rzp_live_fake"


def test_verify_checkout_signature_requires_matching_mode(monkeypatch):
    fakes.set_razorpay_live_env(monkeypatch)
    good_test = fakes.checkout_signature("order_X", "pay_Y", key_secret="secret_fake")
    good_live = fakes.checkout_signature("order_X", "pay_Y", key_secret="live_secret_fake")
    gw = _gw()
    assert gw.verify_checkout_signature(
        provider_order_id="order_X", provider_payment_id="pay_Y", signature=good_test, payment_mode="test"
    ) is True
    assert gw.verify_checkout_signature(
        provider_order_id="order_X", provider_payment_id="pay_Y", signature=good_live, payment_mode="live"
    ) is True
    # cross-mode: a test-secret signature must not validate against live mode
    assert gw.verify_checkout_signature(
        provider_order_id="order_X", provider_payment_id="pay_Y", signature=good_test, payment_mode="live"
    ) is False


def test_verify_webhook_requires_matching_mode(monkeypatch):
    fakes.set_razorpay_live_env(monkeypatch)
    raw_test, sig_test = fakes.webhook_body_and_sig(
        "payment.captured", order_id="order_1", amount_paise=100, webhook_secret="whsec_fake"
    )
    raw_live, sig_live = fakes.webhook_body_and_sig(
        "payment.captured", order_id="order_1", amount_paise=100, webhook_secret="live_whsec_fake"
    )
    gw = _gw()
    assert gw.verify_webhook(raw_test, sig_test, payment_mode="test") is True
    assert gw.verify_webhook(raw_live, sig_live, payment_mode="live") is True
    # a delivery signed with the TEST webhook secret must not verify as LIVE
    assert gw.verify_webhook(raw_test, sig_test, payment_mode="live") is False


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


def test_resolve_credentials_fails_closed_without_payment_mode(monkeypatch):
    # refund()/query_refund()/query_payment_status() reach the real provider
    # only through _resolve_credentials (via _build_client) — the fake in
    # this test file bypasses it, so the fail-closed behaviour it guards is
    # exercised directly here instead.
    from app.config import get_settings
    from app.gateways.razorpay_gateway import RazorpayModeCredentialError, _resolve_credentials

    monkeypatch.setenv("RAZORPAY_LIVE_KEY_ID", "")
    monkeypatch.setenv("RAZORPAY_LIVE_KEY_SECRET", "")
    monkeypatch.setenv("RAZORPAY_LIVE_WEBHOOK_SECRET", "")
    get_settings.cache_clear()
    with pytest.raises(RazorpayModeCredentialError):
        _resolve_credentials(get_settings(), None)
    with pytest.raises(RazorpayModeCredentialError):
        _resolve_credentials(get_settings(), "live")  # no live creds configured
