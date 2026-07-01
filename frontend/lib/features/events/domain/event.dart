class AppEvent {
  const AppEvent({
    required this.eventId,
    required this.slug,
    required this.title,
    this.tagline,
    this.description,
    required this.status,
    required this.startDatetime,
    this.endDatetime,
    required this.timezone,
    this.locationText,
    this.locationMapsUrl,
    required this.isVirtual,
    this.thumbnailUrl,
    this.bannerUrl,
    this.capacity,
    this.registrationOpensAt,
    this.registrationClosesAt,
    this.publishedAt,
    required this.registrationStatus,
    required this.registeredCount,
    this.sessions = const [],
    this.speakers = const [],
  });

  final int eventId;
  final String slug;
  final String title;
  final String? tagline;
  final String? description;
  final String status;
  final DateTime startDatetime;
  final DateTime? endDatetime;
  final String timezone;
  final String? locationText;
  final String? locationMapsUrl;
  final bool isVirtual;
  final String? thumbnailUrl;
  final String? bannerUrl;
  final int? capacity;
  final DateTime? registrationOpensAt;
  final DateTime? registrationClosesAt;
  final DateTime? publishedAt;
  final String registrationStatus;
  final int registeredCount;
  final List<EventSession> sessions;
  final List<EventPerson> speakers;

  factory AppEvent.fromJson(Map<String, dynamic> json) {
    return AppEvent(
      eventId: json['event_id'] as int,
      slug: json['slug'] as String,
      title: json['title'] as String,
      tagline: json['tagline'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String,
      startDatetime: DateTime.parse(json['start_datetime'] as String).toLocal(),
      endDatetime: json['end_datetime'] != null
          ? DateTime.parse(json['end_datetime'] as String).toLocal()
          : null,
      timezone: json['timezone'] as String,
      locationText: json['location_text'] as String?,
      locationMapsUrl: json['location_maps_url'] as String?,
      isVirtual: json['is_virtual'] as bool? ?? false,
      thumbnailUrl: json['thumbnail_url'] as String?,
      bannerUrl: json['banner_url'] as String?,
      capacity: json['capacity'] as int?,
      registrationOpensAt: json['registration_opens_at'] != null
          ? DateTime.parse(json['registration_opens_at'] as String).toLocal()
          : null,
      registrationClosesAt: json['registration_closes_at'] != null
          ? DateTime.parse(json['registration_closes_at'] as String).toLocal()
          : null,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String).toLocal()
          : null,
      registrationStatus: json['registration_status'] as String? ?? 'not_applicable',
      registeredCount: json['registered_count'] as int? ?? 0,
      sessions: (json['sessions'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(EventSession.fromJson)
          .toList(),
      speakers: (json['speakers'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(EventPerson.fromJson)
          .toList(),
    );
  }
}

class EventSession {
  const EventSession({
    required this.sessionId,
    required this.title,
    this.description,
    this.speakerName,
    this.locationText,
    this.track,
    required this.startDatetime,
    this.endDatetime,
  });

  final int sessionId;
  final String title;
  final String? description;
  final String? speakerName;
  final String? locationText;
  final String? track;
  final DateTime startDatetime;
  final DateTime? endDatetime;

  factory EventSession.fromJson(Map<String, dynamic> json) {
    final start = json['start_datetime'] ?? json['starts_at'];
    final end = json['end_datetime'] ?? json['ends_at'];
    return EventSession(
      sessionId: json['session_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String?,
      speakerName: json['speaker_name'] as String?,
      locationText: (json['location_text'] ?? json['location']) as String?,
      track: (json['track'] ?? json['track_name']) as String?,
      startDatetime: DateTime.parse(start as String).toLocal(),
      endDatetime: end != null ? DateTime.parse(end as String).toLocal() : null,
    );
  }
}

class EventPerson {
  const EventPerson({
    required this.personId,
    required this.role,
    required this.fullname,
    this.title,
    this.organisation,
    this.bio,
    this.photoUrl,
    this.linkedinUrl,
  });

  final int personId;
  final String role;
  final String fullname;
  final String? title;
  final String? organisation;
  final String? bio;
  final String? photoUrl;
  final String? linkedinUrl;

  String get initials {
    final parts = fullname.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  String get subtitle {
    final details = [
      if (title != null && title!.trim().isNotEmpty) title!.trim(),
      if (organisation != null && organisation!.trim().isNotEmpty) organisation!.trim(),
    ];
    if (details.isNotEmpty) return details.join(', ');
    return role
        .toLowerCase()
        .split('_')
        .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  factory EventPerson.fromJson(Map<String, dynamic> json) {
    return EventPerson(
      personId: json['person_id'] as int,
      role: json['role'] as String,
      fullname: json['fullname'] as String,
      title: json['title'] as String?,
      organisation: json['organisation'] as String?,
      bio: json['bio'] as String?,
      photoUrl: json['photo_url'] as String?,
      linkedinUrl: json['linkedin_url'] as String?,
    );
  }
}
