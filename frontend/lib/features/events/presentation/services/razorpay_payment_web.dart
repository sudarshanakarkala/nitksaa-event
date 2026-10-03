/// Web implementation of Razorpay Checkout.
///
/// Uses the Razorpay Checkout JS SDK loaded in web/index.html
/// (https://checkout.razorpay.com/v1/checkout.js). The order is created
/// server-side first; this only opens the checkout and bridges the
/// success/error callbacks back to Dart.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'razorpay_payment_models.dart';

Future<RazorpayCheckoutResult> openRazorpayCheckout(
  RazorpayCheckoutOptions options,
) async {
  final completer = Completer<RazorpayCheckoutResult>();

  if (!globalContext.has('Razorpay')) {
    throw const RazorpayCheckoutFailureException(
      'Razorpay checkout could not be loaded. Please refresh and try again.',
    );
  }
  final razorpayCtor = globalContext['Razorpay'] as JSFunction;

  final optionsObj = JSObject();
  optionsObj['key'] = options.keyId.toJS;
  optionsObj['amount'] = options.amountMinor.toJS;
  optionsObj['currency'] = options.currency.toJS;
  optionsObj['order_id'] = options.orderId.toJS;
  if (options.name != null) {
    optionsObj['name'] = options.name!.toJS;
  }
  if (options.description != null) {
    optionsObj['description'] = options.description!.toJS;
  }
  if (options.prefillName != null ||
      options.prefillEmail != null ||
      options.prefillContact != null) {
    final prefill = JSObject();
    if (options.prefillName != null) {
      prefill['name'] = options.prefillName!.toJS;
    }
    if (options.prefillEmail != null) {
      prefill['email'] = options.prefillEmail!.toJS;
    }
    if (options.prefillContact != null) {
      prefill['contact'] = options.prefillContact!.toJS;
    }
    optionsObj['prefill'] = prefill;
  }
  if (options.themeColor != null) {
    final theme = JSObject();
    theme['color'] = options.themeColor!.toJS;
    optionsObj['theme'] = theme;
  }

  // Success: called by Razorpay with {razorpay_payment_id, razorpay_order_id,
  // razorpay_signature}.
  optionsObj['handler'] = ((JSObject response) {
    if (completer.isCompleted) return;
    completer.complete(
      RazorpayCheckoutResult(
        paymentId: _strProp(response, 'razorpay_payment_id'),
        orderId: _strProp(response, 'razorpay_order_id'),
        signature: _strProp(response, 'razorpay_signature'),
      ),
    );
  }).toJS;

  // Dismissed modal (user pressed ESC / closed overlay) => cancellation.
  final modal = JSObject();
  modal['ondismiss'] = ((JSAny? _) {
    if (completer.isCompleted) return;
    completer.completeError(
      const RazorpayCheckoutCancelledException('Payment was cancelled.'),
    );
  }).toJS;
  optionsObj['modal'] = modal;

  // Razorpay must be constructed with `new Razorpay(options)`.
  // NOTE: JSFunction.callAsFunction's first argument is `this`, not a
  // parameter - calling it that way passed NO options and Razorpay replied
  // "Invalid options".
  final JSObject instance;
  try {
    instance = razorpayCtor.callAsConstructor<JSObject>(optionsObj);
  } catch (e) {
    throw RazorpayCheckoutFailureException(
      'Unable to open Razorpay checkout: $e',
    );
  }

  // Failure: Razorpay emits `payment.failed` with
  // {error: {code, description, source, step, reason, metadata}}.
  instance.callMethodVarArgs<JSAny?>(
    'on'.toJS,
    <JSAny?>[
      'payment.failed'.toJS,
      ((JSObject response) {
        if (completer.isCompleted) return;
        final errorValue = response['error'];
        final error =
            errorValue.isA<JSObject>() ? errorValue as JSObject : response;
        final description = _strProp(error, 'description');
        final reason = _strProp(error, 'reason');
        final message = description.isEmpty
            ? reason
            : (reason.isEmpty ? description : '$description ($reason)');
        final cancelled = message.toLowerCase().contains('cancel');
        if (cancelled) {
          completer.completeError(
            const RazorpayCheckoutCancelledException('Payment was cancelled.'),
          );
        } else {
          completer.completeError(
            RazorpayCheckoutFailureException(
              message.trim().isEmpty
                  ? 'Payment failed. Please try again.'
                  : message.trim(),
            ),
          );
        }
      }).toJS,
    ],
  );

  // `open()` triggers the async checkout UI; the success/error handlers
  // above resolve the completer when Razorpay reports the result.
  instance.callMethod<JSAny?>('open'.toJS);

  return completer.future;
}

String _strProp(JSObject obj, String key) {
  final value = obj[key];
  return value.isA<JSString>() ? (value as JSString).toDart : '';
}