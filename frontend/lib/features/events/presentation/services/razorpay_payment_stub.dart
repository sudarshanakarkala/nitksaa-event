/// Fallback implementation for platforms that cannot host the Razorpay
/// checkout (e.g. desktop). Also used as the compile-time default for the
/// conditional import.
library;

import 'razorpay_payment_models.dart';

Future<RazorpayCheckoutResult> openRazorpayCheckout(
  RazorpayCheckoutOptions options,
) async {
  throw const RazorpayPlatformUnsupportedException(
    'Payments are supported on Android, iOS, and Web only.',
  );
}