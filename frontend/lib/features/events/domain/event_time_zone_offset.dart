/// Minutes east of UTC in an IANA timezone at a moment, or null for an
/// unknown zone. The browser's data on the web; a small fixed table
/// elsewhere (tests).
library;

export 'event_time_zone_offset_stub.dart'
    if (dart.library.js_interop) 'event_time_zone_offset_web.dart';
