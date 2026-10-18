/// No share sheet off the web.
bool canShareNatively() => false;

/// Off the web there is nothing to share to; never called (see
/// [canShareNatively]).
Future<void> shareNatively({required String title, required String url}) async {}

/// Off the web there is no address bar to tidy.
void moveReadableLinkIntoApp() {}
