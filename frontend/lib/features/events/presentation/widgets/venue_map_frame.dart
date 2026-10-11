/// An embedded Google map for a venue. On the web it is an iframe; elsewhere
/// there is no embed and [venueMapFrame] returns null (the venue section
/// still offers "Open in Google Maps").
library;

export 'venue_map_frame_stub.dart'
    if (dart.library.js_interop) 'venue_map_frame_web.dart';
