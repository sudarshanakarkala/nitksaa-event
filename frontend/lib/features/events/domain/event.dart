class EventSponsor {
  const EventSponsor({
    required this.sponsorId,
    required this.eventId,
    required this.sponsorType,
    required this.name,
    this.logoUrl,
    this.websiteUrl,
    this.description,
    required this.displayOrder,
  });

  final int sponsorId;
  final int eventId;
  final String sponsorType;
  final String name;
  final String? logoUrl;
  final String? websiteUrl;
  final String? description;
  final int displayOrder;

  String get sponsorTypeLabel {
    switch (sponsorType) {
      case 'TITLE_SPONSOR':
        return 'Title Sponsor';
      case 'GOLD_SPONSOR':
        return 'Gold Sponsor';
      case 'SILVER_SPONSOR':
        return 'Silver Sponsor';
      case 'BRONZE_SPONSOR':
        return 'Bronze Sponsor';
      case 'ASSOCIATE_SPONSOR':
        return 'Associate Sponsor';
      default:
        return sponsorType
            .split('_')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
    }
  }

  factory EventSponsor.fromJson(Map<String, dynamic> json) {
    return EventSponsor(
      sponsorId: json['sponsor_id'] as int,
      eventId: json['event_id'] as int,
      sponsorType: json['sponsor_type'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      websiteUrl: json['website_url'] as String?,
      description: json['description'] as String?,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }
}

class EventPartner {
  const EventPartner({
    required this.partnerId,
    required this.eventId,
    required this.partnerType,
    required this.name,
    this.logoUrl,
    this.websiteUrl,
    this.description,
    required this.displayOrder,
  });

  final int partnerId;
  final int eventId;
  final String partnerType;
  final String name;
  final String? logoUrl;
  final String? websiteUrl;
  final String? description;
  final int displayOrder;

  String get partnerTypeLabel {
    switch (partnerType) {
      case 'COMMUNITY_PARTNER':
        return 'Community Partner';
      case 'KNOWLEDGE_PARTNER':
        return 'Knowledge Partner';
      case 'MEDIA_PARTNER':
        return 'Media Partner';
      case 'VENUE_PARTNER':
        return 'Venue Partner';
      case 'TECHNOLOGY_PARTNER':
        return 'Technology Partner';
      case 'ECOSYSTEM_PARTNER':
        return 'Ecosystem Partner';
      case 'HIRING_PARTNER':
        return 'Hiring Partner';
      default:
        return partnerType
            .split('_')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
            .join(' ');
    }
  }

  factory EventPartner.fromJson(Map<String, dynamic> json) {
    return EventPartner(
      partnerId: json['partner_id'] as int,
      eventId: json['event_id'] as int,
      partnerType: json['partner_type'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      websiteUrl: json['website_url'] as String?,
      description: json['description'] as String?,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }
}

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
    this.virtualUrl,
    required this.isVirtual,
    this.thumbnailUrl,
    this.bannerUrl,
    this.capacity,
    this.isFree = true,
    this.ticketPrice,
    this.registrationMinQuantity,
    this.registrationMaxQuantity,
    this.registrationOpensAt,
    this.registrationClosesAt,
    this.publishedAt,
    required this.registrationStatus,
    required this.registeredCount,
    this.sessions = const [],
    this.speakers = const [],
    this.sponsors = const [],
    this.partners = const [],
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
  final String? virtualUrl;
  final bool isVirtual;
  final String? thumbnailUrl;
  final String? bannerUrl;
  final int? capacity;
  /// Nullable on purpose: (1) older server payloads may omit `is_free` for
  /// events created before the column existed, and (2) Dart on the web (DDC)
  /// can read a non-nullable field as `null` for instances that were created
  /// before hot reload added it — a non-nullable `bool` would then throw a
  /// runtime `TypeError`. Consumers must fall back (e.g. `event.isFree ?? true`).
  final bool? isFree;
  final double? ticketPrice;
  final int? registrationMinQuantity;
  final int? registrationMaxQuantity;
  final DateTime? registrationOpensAt;
  final DateTime? registrationClosesAt;
  final DateTime? publishedAt;
  final String registrationStatus;
  final int registeredCount;
  final List<EventSession> sessions;
  final List<EventPerson> speakers;
  final List<EventSponsor> sponsors;
  final List<EventPartner> partners;

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
      virtualUrl: json['virtual_url'] as String?,
      isVirtual: json['is_virtual'] as bool? ?? false,
      thumbnailUrl: json['thumbnail_url'] as String?,
      bannerUrl: json['banner_url'] as String?,
      capacity: json['capacity'] as int?,
      isFree: json['is_free'] as bool? ?? true,
      ticketPrice: _parseTicketPrice(json['ticket_price']),
      registrationMinQuantity: json['registration_min_quantity'] as int?,
      registrationMaxQuantity: json['registration_max_quantity'] as int?,
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
      sponsors: (json['sponsors'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(EventSponsor.fromJson)
          .toList(),
      partners: (json['partners'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(EventPartner.fromJson)
          .toList(),
    );
  }

  /// Parses `ticket_price` from the API. The backend stores it as NUMERIC
  /// (Decimal), which may be serialized as a JSON number (`num`) or a string
  /// (e.g. `"150.00"`) depending on the FastAPI version, so both forms plus
  /// `null` must be handled.
  static double? _parseTicketPrice(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
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