/// Sign-in news between this site's open tabs, and the page events that
/// matter for staying signed in.
///
/// - One tab signs out: every other tab drops its session too.
/// - One tab signs in as someone else: a tab signed in as another person
///   reloads as the new one, so it never shows the previous person's data.
/// - A tab coming back to the front checks whether its session needs
///   renewing.
///
/// On the web this is the browser's `BroadcastChannel` (other tabs of the
/// same site only; a tab doesn't hear itself). Off the web it does nothing.
library;

import 'auth_tab_channel_platform.dart' as platform;

class AuthTabChannel {
  const AuthTabChannel();

  /// Tells the other tabs.
  void post(String message) => platform.post(message);

  /// [onMessage] gets what other tabs post.
  void listen(void Function(String message) onMessage) =>
      platform.listen(onMessage);

  /// [onShown] runs when this tab comes back to the front.
  void onPageShown(void Function() onShown) => platform.onPageShown(onShown);

  /// Reloads this tab.
  void reload() => platform.reload();
}
