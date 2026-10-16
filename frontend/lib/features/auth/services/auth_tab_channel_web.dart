import 'dart:js_interop';

import '../../../core/logger/app_logger.dart';

@JS('BroadcastChannel')
extension type _BroadcastChannel._(JSObject _) implements JSObject {
  external factory _BroadcastChannel(JSString name);
  external void postMessage(JSAny? message);
  external set onmessage(JSFunction? handler);
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

@JS('document.addEventListener')
external void _addDocumentListener(JSString type, JSFunction listener);

@JS('document.visibilityState')
external JSString get _visibilityState;

@JS('location.reload')
external void _reload();

_BroadcastChannel? _channel;
bool _channelFailed = false;

_BroadcastChannel? get _openChannel {
  if (_channel != null || _channelFailed) return _channel;
  try {
    return _channel = _BroadcastChannel('nitksaa-events-auth'.toJS);
  } catch (error) {
    // Very old browsers: tabs just don't hear each other.
    _channelFailed = true;
    AppLogger.warning('No BroadcastChannel: $error');
    return null;
  }
}

void post(String message) {
  try {
    _openChannel?.postMessage(message.toJS);
  } catch (error) {
    AppLogger.warning('Could not tell other tabs: $error');
  }
}

void listen(void Function(String message) onMessage) {
  final channel = _openChannel;
  if (channel == null) return;
  channel.onmessage = ((_MessageEvent event) {
    final data = event.data;
    if (data != null && data.isA<JSString>()) {
      onMessage((data as JSString).toDart);
    }
  }).toJS;
}

void onPageShown(void Function() onShown) {
  try {
    _addDocumentListener(
      'visibilitychange'.toJS,
      ((JSAny? _) {
        if (_visibilityState.toDart == 'visible') onShown();
      }).toJS,
    );
  } catch (error) {
    AppLogger.warning('No visibilitychange: $error');
  }
}

void reload() => _reload();
