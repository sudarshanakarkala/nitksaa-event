class Registration {
  const Registration({
    required this.registrationId,
    required this.eventId,
    required this.status,
    required this.registeredAt,
    this.registrationNumber,
    this.fullnameSnapshot,
    this.emailSnapshot,
    this.phoneSnapshot,
    this.batchYearSnapshot,
    this.branchSnapshot,
    this.attendeeNote,
    this.cancelledAt,
    this.confirmationEmailStatus,
    this.joinUrl,
    this.event,
  });

  factory Registration.fromJson(Map<String, dynamic> json) {
    return Registration(
      registrationId: _requiredInt(json, 'registration_id'),
      registrationNumber: _str(json['registration_number']),
      eventId: _requiredInt(json, 'event_id'),
      status: json['status']?.toString() ?? '',
      fullnameSnapshot: _str(json['fullname_snapshot']),
      emailSnapshot: _str(json['email_snapshot']),
      phoneSnapshot: _str(json['phone_snapshot']),
      batchYearSnapshot: _optionalInt(json['batch_year_snapshot']),
      branchSnapshot: _str(json['branch_snapshot']),
      attendeeNote: _str(json['attendee_note']),
      registeredAt: DateTime.parse(json['registered_at'] as String),
      cancelledAt: _optionalDateTime(json['cancelled_at']),
      confirmationEmailStatus: _str(json['confirmation_email_status']),
      joinUrl: _str(json['join_url']),
      event: json['event'] is Map
          ? RegistrationEventSummary.fromJson(
              Map<String, dynamic>.from(json['event'] as Map))
          : null,
    );
  }

  final int registrationId;
  final String? registrationNumber;
  final int eventId;
  final String status;
  final String? fullnameSnapshot;
  final String? emailSnapshot;
  final String? phoneSnapshot;
  final int? batchYearSnapshot;
  final String? branchSnapshot;
  final String? attendeeNote;
  final DateTime registeredAt;
  final DateTime? cancelledAt;
  final String? confirmationEmailStatus;
  final String? joinUrl;
  final RegistrationEventSummary? event;

  bool get isActive => status == 'registered';
}

class RegistrationEventSummary {
  const RegistrationEventSummary({
    required this.eventId,
    required this.title,
    required this.startDateTime,
    required this.endDateTime,
    required this.timezone,
    required this.isVirtual,
    this.locationText,
  });

  factory RegistrationEventSummary.fromJson(Map<String, dynamic> json) {
    return RegistrationEventSummary(
      eventId: _requiredInt(json, 'event_id'),
      title: json['title']?.toString() ?? '',
      startDateTime: DateTime.parse(json['start_datetime'] as String),
      endDateTime: DateTime.parse(json['end_datetime'] as String),
      timezone: json['timezone']?.toString() ?? 'UTC',
      isVirtual: json['is_virtual'] as bool? ?? false,
      locationText: _str(json['location_text']),
    );
  }

  final int eventId;
  final String title;
  final DateTime startDateTime;
  final DateTime endDateTime;
  final String timezone;
  final bool isVirtual;
  final String? locationText;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  throw FormatException('Missing or invalid $key');
}

int? _optionalInt(dynamic v) => switch (v) {
      int n => n,
      num n => n.toInt(),
      _ => null,
    };

String? _str(dynamic v) {
  if (v is! String || v.trim().isEmpty) return null;
  return v.trim();
}

DateTime? _optionalDateTime(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}
