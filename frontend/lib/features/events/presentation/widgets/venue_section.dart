import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../theme/app_palette.dart';
import '../../domain/event.dart';
import 'venue_map_frame.dart';

/// "Venue" on the event page: the address, an embedded Google map (web) and
/// "Open in Google Maps". Nothing for virtual events or an unknown venue.
///
/// The map uses the Maps Embed API when the build has
/// `--dart-define=MAPS_EMBED_API_KEY=…` (Google's supported embed, needs a
/// key restricted to the sites); without a key it uses Google Maps' keyless
/// `output=embed` page.
class VenueSection extends StatelessWidget {
  const VenueSection({super.key, required this.event});

  final AppEvent event;

  static const _embedKey = String.fromEnvironment('MAPS_EMBED_API_KEY');

  static bool hasVenue(AppEvent event) =>
      !event.isVirtual && (event.locationText?.trim().isNotEmpty ?? false);

  String get _query => event.locationText!.trim();

  String get _embedUrl {
    final q = Uri.encodeQueryComponent(_query);
    return _embedKey.isNotEmpty
        ? 'https://www.google.com/maps/embed/v1/place?key=$_embedKey&q=$q'
        : 'https://maps.google.com/maps?q=$q&z=15&output=embed';
  }

  /// The organiser's own Maps link when set, otherwise a search for the
  /// address.
  Uri get _openUrl {
    final custom = event.locationMapsUrl?.trim();
    if (custom != null && custom.isNotEmpty) return Uri.parse(custom);
    return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': _query});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final map = venueMapFrame(_embedUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Venue',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: p.primary),
        ),
        const SizedBox(height: 10),
        Text(_query, style: const TextStyle(fontSize: 14, height: 1.5)),
        if (map != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: p.border)),
              // The map ignores the mouse (see venueMapFrame); a click
              // on it opens Google Maps.
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => launchUrl(_openUrl, mode: LaunchMode.externalApplication),
                  child: SizedBox(height: 240, width: double.infinity, child: map),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => launchUrl(_openUrl, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open in Google Maps'),
        ),
      ],
    );
  }
}
