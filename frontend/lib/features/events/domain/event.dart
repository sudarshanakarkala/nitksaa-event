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
    );
  }
}
