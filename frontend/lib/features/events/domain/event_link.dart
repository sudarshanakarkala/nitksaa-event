import 'package:flutter/services.dart';

/// An event's readable link, e.g. `https://events.nitkalumni.in/e/nitkonnect-2027`.
/// It uses the address the app is running on, so a beta link opens beta.
/// The plain `/e/…` form (no `#`) works because the app moves it to `#/e/…`
/// as it starts (`moveReadableLinkIntoApp`).
String eventLinkUrl(String slug) => '${eventLinkPrefix()}$slug';

/// Everything before the slug: `https://events.nitkalumni.in/e/`.
String eventLinkPrefix() {
  final base = Uri.base;
  final origin = base.scheme == 'http' || base.scheme == 'https'
      ? base.origin
      : 'https://events.nitkalumni.in'; // e.g. in tests
  return '$origin/e/';
}

/// The link as typed, tidied: lower case, spaces and underscores become
/// hyphens, anything else that can't be in a link is dropped, no double
/// hyphens. A trailing hyphen is kept while typing (the next word follows).
String tidySlug(String typed) => typed
    .toLowerCase()
    .replaceAll(RegExp(r'[\s_]+'), '-')
    .replaceAll(RegExp(r'[^a-z0-9-]'), '')
    .replaceAll(RegExp(r'-{2,}'), '-')
    .replaceFirst(RegExp(r'^-+'), '');

/// What's wrong with a link, in plain words; null when it's fine. The server
/// checks the same rules (`SLUG_PATTERN`, 3–60 characters).
String? slugProblem(String slug) {
  if (slug.length < 3) return 'Use at least 3 letters or numbers';
  if (slug.length > 60) return 'Use at most 60 characters';
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
    return 'Use letters, numbers and single hyphens, not at the end';
  }
  return null;
}

/// Tidies the link field as people type (see [tidySlug]).
class SlugInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final tidy = tidySlug(newValue.text);
    if (tidy == newValue.text) return newValue;
    return TextEditingValue(
      text: tidy,
      selection: TextSelection.collapsed(offset: tidy.length),
    );
  }
}
