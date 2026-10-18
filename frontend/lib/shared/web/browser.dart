/// Small browser features the app uses directly: the phone's share sheet,
/// and tidying a readable event link into the app's own `#/` address.
/// Off the web (tests) they do nothing.
library;

export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';
