/// A stand-in for Razorpay's checkout.js, for browser tests.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// How the fake checkout ends once the app opens it.
enum FakeRazorpayOutcome {
  /// The attendee pays; Razorpay calls the success handler.
  paid,

  /// The attendee closes the checkout without paying.
  dismissed,
}

/// Puts a fake `window.Razorpay` in place of the real checkout script, which
/// the test page does not load. It records the options the app opens the
/// checkout with and ends the checkout at once, without any network call.
abstract final class FakeRazorpay {
  static const paymentId = 'pay_FAKE1';
  static const signature = 'sig_FAKE1';

  static void install({
    FakeRazorpayOutcome outcome = FakeRazorpayOutcome.paid,
  }) {
    globalContext.callMethod<JSAny?>('eval'.toJS, _script(outcome).toJS);
  }

  static void uninstall() {
    globalContext.delete('Razorpay'.toJS);
    globalContext.delete(_openedKey.toJS);
  }

  /// The options of each checkout the app opened, in order. `amount` is the
  /// number Razorpay would charge, in paise.
  static List<Map<String, dynamic>> get opened {
    final raw = globalContext[_openedKey];
    if (raw.isUndefinedOrNull) return const [];
    return [
      for (final entry in (raw as JSArray<JSString>).toDart)
        jsonDecode(entry.toDart) as Map<String, dynamic>,
    ];
  }

  static const _openedKey = '__fakeRazorpayOpened';

  static String _script(FakeRazorpayOutcome outcome) =>
      '''
(function () {
  window.$_openedKey = [];
  window.Razorpay = function (options) {
    this.on = function () {};
    this.open = function () {
      window.$_openedKey.push(JSON.stringify({
        key: options.key,
        amount: options.amount,
        currency: options.currency,
        order_id: options.order_id,
        name: options.name,
        description: options.description
      }));
      if ('${outcome.name}' === 'paid') {
        options.handler({
          razorpay_payment_id: '$paymentId',
          razorpay_order_id: options.order_id,
          razorpay_signature: '$signature'
        });
      } else {
        // checkout.js always calls ondismiss with one argument.
        options.modal.ondismiss(undefined);
      }
    };
  };
})();
''';
}
