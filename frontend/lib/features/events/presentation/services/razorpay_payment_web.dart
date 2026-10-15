/// Web implementation of Razorpay Checkout.
///
/// Uses the Razorpay Checkout JS SDK
/// (https://checkout.razorpay.com/v1/checkout.js), loaded here the first
/// time someone pays rather than by web/index.html: on every page load it
/// pulled in about a hundred Razorpay files nobody needed until Pay. The
/// order is created server-side first; this only opens the checkout and
/// bridges the success/error callbacks back to Dart.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'razorpay_payment_models.dart';

Future<RazorpayCheckoutResult> openRazorpayCheckout(
  RazorpayCheckoutOptions options,
) async {
  final completer = Completer<RazorpayCheckoutResult>();

  await _loadRazorpay();
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

  // The last failure Razorpay reported while its window stayed open. A
  // failed payment does NOT end the checkout: Razorpay keeps the window
  // open so the person can try again, and a retry there can still succeed
  // (the success handler above). So a failure is only remembered here, and
  // reported if the window is then closed without a success.
  String? lastFailure;
  // Whether that failure was a cancellation, by Razorpay's words or code.
  var lastFailureCancelled = false;

  // Window closed (ESC / close button). After a failure: that failure.
  // Otherwise: a cancellation.
  final modal = JSObject();
  modal['ondismiss'] = ((JSAny? _) {
    if (completer.isCompleted) return;
    final failure = lastFailure;
    if (failure != null && !lastFailureCancelled) {
      completer.completeError(RazorpayCheckoutFailureException(failure));
    } else {
      completer.completeError(
        const RazorpayCheckoutCancelledException('Payment was cancelled.'),
      );
    }
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
    throw const RazorpayCheckoutFailureException(
      'Razorpay could not be opened. Please try again.',
    );
  }

  // Failure: Razorpay emits `payment.failed` with
  // {error: {code, description, source, step, reason, metadata}} and keeps
  // its window open for another try. Remember it; don't finish yet (see
  // lastFailure above).
  instance.callMethodVarArgs<JSAny?>(
    'on'.toJS,
    <JSAny?>[
      'payment.failed'.toJS,
      ((JSObject response) {
        if (completer.isCompleted) return;
        final errorValue = response['error'];
        final error =
            errorValue.isA<JSObject>() ? errorValue as JSObject : response;
        final description = _strProp(error, 'description').trim();
        final reason = _strProp(error, 'reason');
        // The description is Razorpay's plain words. The reason is a code
        // (e.g. payment_failed): it only tells a cancellation apart, and is
        // not shown (ISSUE-018).
        lastFailureCancelled =
            '$description $reason'.toLowerCase().contains('cancel');
        lastFailure = description.isEmpty
            ? 'Payment failed. Please try again.'
            : description;
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

const _checkoutScript = 'https://checkout.razorpay.com/v1/checkout.js';

/// The script load in progress or done, shared so a second Pay press
/// doesn't add the script twice. Reset after a failure, so the next press
/// tries again.
Future<void>? _loading;

/// Adds Razorpay's checkout script to the page, once, and waits for it.
/// Does nothing if `window.Razorpay` is already there (a test's fake, or an
/// earlier payment). A failed or slow load leaves `window.Razorpay` unset,
/// and the caller shows its "could not be loaded" message.
Future<void> _loadRazorpay() {
  if (globalContext.has('Razorpay')) return Future.value();
  return _loading ??= _injectScript().catchError((Object _) {
    _loading = null;
  });
}

Future<void> _injectScript() {
  final done = Completer<void>();
  final document = globalContext['document'] as JSObject;
  final script = document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
  script['src'] = _checkoutScript.toJS;
  script['async'] = true.toJS;
  script['onload'] = ((JSAny? _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  script['onerror'] = ((JSAny? _) {
    // Remove it, so the next press adds a fresh one.
    script.callMethod<JSAny?>('remove'.toJS);
    if (!done.isCompleted) done.completeError(StateError('Razorpay script failed to load'));
  }).toJS;
  (document['head'] as JSObject).callMethod<JSAny?>('appendChild'.toJS, script);
  return done.future.timeout(const Duration(seconds: 20));
}
