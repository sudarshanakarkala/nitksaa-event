/// Shared models for opening Razorpay Checkout from the Flutter app.
library;

/// Options needed to open Razorpay Standard Checkout. All values come from
/// the backend's payment attempt response (`checkout` object) plus event /
/// session data used for display and pre-fill. Public values only — never a
/// key secret.
class RazorpayCheckoutOptions {
  const RazorpayCheckoutOptions({
    required this.keyId,
    required this.orderId,
    required this.amountMinor,
    this.currency = 'INR',
    this.name,
    this.description,
    this.prefillName,
    this.prefillEmail,
    this.prefillContact,
    this.themeColor,
  });

  /// Razorpay Key ID (public, `rzp_*`). Mirrors `checkout.key_id`.
  final String keyId;

  /// Razorpay order id. Mirrors `checkout.provider_order_id`.
  final String orderId;

  /// Amount in the smallest currency unit (paise for INR), mirrors
  /// `checkout.amount_minor`.
  final int amountMinor;

  final String currency;

  /// Merchant name shown in the checkout, e.g. the event title.
  final String? name;

  final String? description;

  final String? prefillName;
  final String? prefillEmail;
  final String? prefillContact;

  /// Theme accent colour as hex string, e.g. `#C9952A`.
  final String? themeColor;
}

/// Result delivered by the Razorpay success handler. This is a first gate
/// only — the backend re-verifies everything before confirming.
class RazorpayCheckoutResult {
  const RazorpayCheckoutResult({
    required this.paymentId,
    required this.orderId,
    required this.signature,
  });

  final String paymentId;
  final String orderId;
  final String signature;
}

/// Thrown when the user closes / cancels the Razorpay checkout.
class RazorpayCheckoutCancelledException implements Exception {
  const RazorpayCheckoutCancelledException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when Razorpay reports a payment failure or the checkout cannot be
/// opened.
class RazorpayCheckoutFailureException implements Exception {
  const RazorpayCheckoutFailureException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the current platform cannot host the Razorpay checkout
/// (Android, iOS, and Web are supported).
class RazorpayPlatformUnsupportedException implements Exception {
  const RazorpayPlatformUnsupportedException(this.message);

  final String message;

  @override
  String toString() => message;
}