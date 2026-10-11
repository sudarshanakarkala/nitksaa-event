import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Replaces the current history entry with the same page minus its query,
/// without reloading.
void removeSignInLinkFromUrl() {
  final base = Uri.base;
  final clean = '${base.origin}${base.path}'
      '${base.hasFragment ? '#${base.fragment}' : ''}';
  final history = globalContext['history'] as JSObject;
  history.callMethod<JSAny?>('replaceState'.toJS, null, ''.toJS, clean.toJS);
}
