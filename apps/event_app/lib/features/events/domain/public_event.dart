class PublicEvent {
  const PublicEvent({
    required this.eventId,
    required this.slug,
    required this.title,
    required this.status,
    required this.startDateTime,
    required this.endDateTime,
    required this.timezone,
    required this.isVirtual,
    required this.registeredCount,
    required this.registrationStatus,
    this.tagline,
    this.description,
    this.locationText,
    this.locationMapsUrl,
    this.thumbnailUrl,
    this.bannerUrl,
    this.capacity,
    this.publishedAt,
  });

  factory PublicEvent.fromJson(Map<String, dynamic> json) {
    return PublicEvent(
      eventId: _requiredInt(json, 'event_id'),
      slug: _requiredString(json, 'slug'),
      title: _requiredString(json, 'title'),
      tagline: _optionalString(json['tagline']),
      description: _optionalString(json['description']),
      status: _requiredString(json, 'status'),
      startDateTime: _requiredDateTime(json, 'start_datetime'),
      endDateTime: _requiredDateTime(json, 'end_datetime'),
      timezone: _requiredString(json, 'timezone'),
      locationText: _optionalString(json['location_text']),
      locationMapsUrl: _optionalString(json['location_maps_url']),
      isVirtual: _requiredBool(json, 'is_virtual'),
      thumbnailUrl: _optionalString(json['thumbnail_url']),
      bannerUrl: _optionalString(json['banner_url']),
      capacity: _optionalInt(json['capacity']),
      registeredCount: _optionalInt(json['registered_count']) ?? 0,
      registrationStatus: _requiredString(json, 'registration_status'),
      publishedAt: _optionalDateTime(json['published_at']),
    );
  }

  final int eventId;
  final String slug;
  final String title;
  final String? tagline;
  final String? description;
  final String status;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final String timezone;
  final String? locationText;
  final String? locationMapsUrl;
  final bool isVirtual;
  final String? thumbnailUrl;
  final String? bannerUrl;
  final int? capacity;
  final int registeredCount;
  final String registrationStatus;
  final DateTime? publishedAt;

  String get eventTypeLabel => isVirtual ? 'Virtual' : 'In-person';

  String get capacityLabel =>
      capacity == null ? 'Unlimited' : '$registeredCount / $capacity';

  String get registrationStatusLabel => switch (registrationStatus) {
    'open' => 'Open',
    'closed' => 'Closed',
    'full' => 'Full',
    'not_open_yet' => 'Not Open Yet',
    'not_applicable' => 'Not Applicable',
    _ =>
      registrationStatus
          .split('_')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' '),
  };
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = _optionalInt(json[key]);
  if (value == null) throw FormatException('Missing or invalid $key.');
  return value;
}

int? _optionalInt(dynamic value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => null,
};

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) throw FormatException('Missing or invalid $key.');
  return value;
}

String? _optionalString(dynamic value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Missing or invalid $key.');
  return value;
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = _optionalDateTime(json[key]);
  if (value == null) throw FormatException('Missing or invalid $key.');
  return value;
}

DateTime? _optionalDateTime(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
