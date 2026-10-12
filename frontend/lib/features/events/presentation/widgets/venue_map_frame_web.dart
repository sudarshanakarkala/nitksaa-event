import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

/// `document.createElement('iframe')`, typed directly: no runtime casts on
/// native browser objects (those fail in Flutter's web build).
@JS('document.createElement')
external _IFrame _createElement(JSString tag);

extension type _IFrame._(JSObject _) implements JSObject {
  external set src(String value);
  external set loading(String value);
  external set referrerPolicy(String value);
  external set title(String value);
  external _Style get style;
}

extension type _Style._(JSObject _) implements JSObject {
  external set border(String value);
  external set width(String value);
  external set height(String value);
  external set pointerEvents(String value);
}

final _registered = <String>{};

/// An iframe showing [embedUrl], lazily loaded. It ignores the mouse.
Widget? venueMapFrame(String embedUrl) {
  final viewType = 'venue-map-${embedUrl.hashCode}';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final frame = _createElement('iframe'.toJS)
        ..src = embedUrl
        ..loading = 'lazy'
        ..referrerPolicy = 'no-referrer-when-downgrade'
        ..title = 'Map of the venue';
      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%'
        // The map is a picture, not a control. A web page embedded in the
        // app sits above Flutter and would otherwise take every click over
        // it, even through dialogs opened on top (the event form's date
        // pickers stopped responding wherever the map was underneath).
        // "Open in Google Maps" is there for panning and zooming.
        ..pointerEvents = 'none';
      return frame;
    });
  }
  return HtmlElementView(viewType: viewType);
}
