/// Removes Firebase's sign-in parameters (`?apiKey=…&oobCode=…&mode=signIn`)
/// from the address bar once a sign-in link has been read, so a refresh or
/// a bookmark doesn't try to reuse the link. A no-op off the web.
library;

export 'email_link_url_stub.dart'
    if (dart.library.js_interop) 'email_link_url_web.dart';
