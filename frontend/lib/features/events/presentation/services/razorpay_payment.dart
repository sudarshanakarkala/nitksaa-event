/// Platform-agnostic entry point for opening Razorpay Checkout.
///
/// - Web: drives the global Razorpay Checkout JS (`checkout.razorpay.com/v1/checkout.js`).
/// - Android / iOS: wraps the `razorpay_flutter` native SDK.
/// - Any other platform: throws [RazorpayPlatformUnsupportedException].
library;

import 'razorpay_payment_models.dart';
import 'razorpay_payment_stub.dart'
    if (dart.library.io) 'razorpay_payment_io.dart'
    if (dart.library.js_interop) 'razorpay_payment_web.dart' as impl;

export 'razorpay_payment_models.dart';

/// Opens the Razorpay Standard Checkout for the given order.
///
/// Completes with the Razorpay success payload (`paymentId`, `orderId`,
/// `signature`) which the caller must pass to the backend's
/// verify-checkout endpoint. Throws [RazorpayCheckoutCancelledException] /
/// [RazorpayCheckoutFailureException] / [RazorpayPlatformUnsupportedException]
/// on failure or cancellation.
Future<RazorpayCheckoutResult> openRazorpayCheckout(
  RazorpayCheckoutOptions options,
) {
  return impl.openRazorpayCheckout(options);
}