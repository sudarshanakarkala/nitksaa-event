class PublicEventDetail {
  const PublicEventDetail({
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
    this.showAttendeeList = false,
    this.publishedAt,
    this.speakers = const [],
    this.sessions = const [],
    this.isFullDay = false,
    this.isFree = true,
    this.ticketPrice,
  });

  factory PublicEventDetail.fromJson(Map<String, dynamic> json) {
    return PublicEventDetail(
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
      showAttendeeList: _optionalBool(json['show_attendee_list']) ?? false,
      registeredCount: _optionalInt(json['registered_count']) ?? 0,
      registrationStatus: _requiredString(json, 'registration_status'),
      publishedAt: _optionalDateTime(json['published_at']),
      speakers: _parseSpeakers(json['speakers']),
      sessions: _parseSessions(json['sessions']),
      isFullDay: _optionalBool(json['is_full_day']) ?? false,
      isFree: _optionalBool(json['is_free']) ?? true,
      ticketPrice: _optionalDouble(json['ticket_price']),
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
  final bool showAttendeeList;
  final int registeredCount;
  final String registrationStatus;
  final DateTime? publishedAt;
  final List<PublicEventSpeaker> speakers;
  final List<PublicEventSession> sessions;
  final bool isFullDay;
  final bool isFree;
  final double? ticketPrice;

  String get priceLabel => isFree ? 'Free' : (ticketPrice != null ? '₹${ticketPrice!.toStringAsFixed(0)}' : 'Paid');

  String get eventTypeLabel => isVirtual ? 'Virtual' : 'In-person';

  String get capacityLabel =>
      capacity == null ? 'Unlimited' : '$registeredCount / $capacity';

  String get capacityLimitLabel => capacity?.toString() ?? 'Unlimited';

  String get registrationStatusLabel => _formatStatus(registrationStatus);
}

class PublicEventSpeaker {
  const PublicEventSpeaker({required this.name, this.title});

  factory PublicEventSpeaker.fromJson(Map<String, dynamic> json) {
    final name = _optionalString(json['name']) ??
        _optionalString(json['full_name']) ??
        _optionalString(json['speaker_name']);
    if (name == null) throw const FormatException('Speaker name is missing.');
    return PublicEventSpeaker(
      name: name,
      title: _optionalString(json['title']) ??
          _optionalString(json['designation']),
    );
  }

  final String name;
  final String? title;
}

class PublicEventSession {
  const PublicEventSession({required this.title, this.description});

  factory PublicEventSession.fromJson(Map<String, dynamic> json) {
    return PublicEventSession(
      title: _requiredString(json, 'title'),
      description: _optionalString(json['description']),
    );
  }

  final String title;
  final String? description;
}

List<PublicEventSpeaker> _parseSpeakers(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (speaker) =>
            PublicEventSpeaker.fromJson(Map<String, dynamic>.from(speaker)),
      )
      .toList(growable: false);
}

List<PublicEventSession> _parseSessions(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (session) =>
            PublicEventSession.fromJson(Map<String, dynamic>.from(session)),
      )
      .toList(growable: false);
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

bool? _optionalBool(dynamic value) => value is bool ? value : null;

double? _optionalDouble(dynamic value) => switch (value) {
      double d => d,
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = _optionalDateTime(json[key]);
  if (value == null) throw FormatException('Missing or invalid $key.');
  return value;
}

DateTime? _optionalDateTime(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

String _formatStatus(String status) {
  return switch (status) {
    'open' => 'Open',
    'closed' => 'Closed',
    'full' => 'Full',
    'not_open_yet' => 'Not Open Yet',
    'not_applicable' => 'Not Applicable',
    _ => status
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' '),
  };
}
