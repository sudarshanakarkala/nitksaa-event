import 'dart:js_interop';

/// `window.history.replaceState`, bound directly. Reading `history` and
/// casting it to a JS interop type fails for native browser objects in
/// Flutter's web build, which threw and stopped sign-in-link handling.
@JS('history.replaceState')
external void _replaceState(JSAny? data, JSString unused, JSString url);

/// Replaces the current history entry with the same page minus its query,
/// without reloading.
void removeSignInLinkFromUrl() {
  final base = Uri.base;
  final clean = '${base.origin}${base.path}'
      '${base.hasFragment ? '#${base.fragment}' : ''}';
  _replaceState(null, ''.toJS, clean.toJS);
}
