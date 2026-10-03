/// Android / iOS implementation of Razorpay Checkout using the
/// `razorpay_flutter` native SDK. On other IO platforms (desktop) it throws
/// [RazorpayPlatformUnsupportedException].
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'razorpay_payment_models.dart';

Future<RazorpayCheckoutResult> openRazorpayCheckout(
  RazorpayCheckoutOptions options,
) async {
  if (!kIsWeb &&
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    throw const RazorpayPlatformUnsupportedException(
      'Payments are supported on Android, iOS, and Web only.',
    );
  }

  final completer = Completer<RazorpayCheckoutResult>();
  final razorpay = Razorpay();
  razorpay.clear();

  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) {
    if (completer.isCompleted) return;
    completer.complete(
      RazorpayCheckoutResult(
        paymentId: response.paymentId ?? '',
        orderId: response.orderId ?? '',
        signature: response.signature ?? '',
      ),
    );
  });

  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
    if (completer.isCompleted) return;
    final code = response.code;
    final message = response.message ?? 'Payment failed. Please try again.';
    if (code == 0 || message.toLowerCase().contains('cancel')) {
      completer.completeError(
        const RazorpayCheckoutCancelledException('Payment was cancelled.'),
      );
    } else {
      completer.completeError(RazorpayCheckoutFailureException(message));
    }
  });

  try {
    razorpay.open({
      'key': options.keyId,
      'amount': options.amountMinor,
      'currency': options.currency,
      'order_id': options.orderId,
      if (options.name != null) 'name': options.name,
      if (options.description != null) 'description': options.description,
      if (options.prefillName != null ||
          options.prefillEmail != null ||
          options.prefillContact != null)
        'prefill': {
          if (options.prefillName != null) 'name': options.prefillName,
          if (options.prefillEmail != null) 'email': options.prefillEmail,
          if (options.prefillContact != null) 'contact': options.prefillContact,
        },
      if (options.themeColor != null) 'theme': {'color': options.themeColor},
    });
  } catch (error) {
    completer.completeError(
      RazorpayCheckoutFailureException(
        'Could not open Razorpay checkout: $error',
      ),
    );
  }

  return completer.future;
}