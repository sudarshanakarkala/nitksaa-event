import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('navigator')
external JSObject get _navigator;

@JS('navigator.share')
external JSPromise<JSAny?> _share(JSObject data);

@JS('history.replaceState')
external void _replaceState(JSAny? data, JSString unused, JSString url);

/// The phone's share sheet (WhatsApp, Messages…). Only on touch devices that
/// have one: computers get Copy link instead, which is what people expect
/// there.
bool canShareNatively() {
  try {
    if (!_navigator.has('share')) return false;
    final touch = _navigator.getProperty<JSNumber?>('maxTouchPoints'.toJS);
    return (touch?.toDartInt ?? 0) > 0;
  } catch (_) {
    return false;
  }
}

/// Opens the share sheet. Closing it without sharing is not an error.
Future<void> shareNatively({required String title, required String url}) async {
  final data = JSObject()
    ..setProperty('title'.toJS, title.toJS)
    ..setProperty('url'.toJS, url.toJS);
  try {
    await _share(data).toDart;
  } catch (_) {
    // Cancelled, or the browser refused: nothing to tell the person.
  }
}

/// `…/e/<slug>` (a readable link, without `#`) becomes `…/#/e/<slug>`, the
/// app's own address for it, before the app starts. Hosting already serves
/// the app for every path, so only the address needs moving.
void moveReadableLinkIntoApp() {
  final base = Uri.base;
  final fragment = base.fragment;
  if (!base.path.startsWith('/e/')) return;
  if (fragment.isNotEmpty && fragment != '/') return;
  final slug = base.path.substring(3).split('/').first;
  if (slug.isEmpty) return;
  _replaceState(null, ''.toJS, '${base.origin}/#/e/$slug'.toJS);
}
