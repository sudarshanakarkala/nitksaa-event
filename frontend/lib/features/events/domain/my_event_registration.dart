import 'event.dart';

class MyEventRegistration {
  const MyEventRegistration({
    required this.registrationId,
    this.registrationNumber,
    required this.eventId,
    required this.status,
    this.attendeeNote,
    required this.registeredAt,
    this.cancelledAt,
    this.joinUrl,
    this.event,
    this.publicEvent,
  });

  final int registrationId;
  final String? registrationNumber;
  final int eventId;
  final String status;
  final String? attendeeNote;
  final DateTime registeredAt;
  final DateTime? cancelledAt;
  final String? joinUrl;
  final RegisteredEventSummary? event;
  final AppEvent? publicEvent;

  bool get isActive => status == 'registered';
  bool get canCancel =>
      isActive && publicEvent?.registrationStatus.toLowerCase() == 'open';

  MyEventRegistration copyWith({AppEvent? publicEvent, String? status}) {
    return MyEventRegistration(
      registrationId: registrationId,
      registrationNumber: registrationNumber,
      eventId: eventId,
      status: status ?? this.status,
      attendeeNote: attendeeNote,
      registeredAt: registeredAt,
      cancelledAt: cancelledAt,
      joinUrl: joinUrl,
      event: event,
      publicEvent: publicEvent ?? this.publicEvent,
    );
  }

  factory MyEventRegistration.fromJson(Map<String, dynamic> json) {
    return MyEventRegistration(
      registrationId: json['registration_id'] as int,
      registrationNumber: json['registration_number'] as String?,
      eventId: json['event_id'] as int,
      status: json['status'] as String? ?? 'registered',
      attendeeNote: json['attendee_note'] as String?,
      registeredAt: DateTime.parse(json['registered_at'] as String).toLocal(),
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.parse(json['cancelled_at'] as String).toLocal()
          : null,
      joinUrl: json['join_url'] as String?,
      event: json['event'] != null
          ? RegisteredEventSummary.fromJson(json['event'] as Map<String, dynamic>)
          : null,
    );
  }
}

class RegisteredEventSummary {
  const RegisteredEventSummary({
    required this.eventId,
    required this.title,
    required this.startDatetime,
    this.endDatetime,
    required this.timezone,
    required this.isVirtual,
    this.locationText,
    this.locationMapsUrl,
  });

  final int eventId;
  final String title;
  final DateTime startDatetime;
  final DateTime? endDatetime;
  final String timezone;
  final bool isVirtual;
  final String? locationText;
  final String? locationMapsUrl;

  factory RegisteredEventSummary.fromJson(Map<String, dynamic> json) {
    return RegisteredEventSummary(
      eventId: json['event_id'] as int,
      title: json['title'] as String,
      startDatetime: DateTime.parse(json['start_datetime'] as String).toLocal(),
      endDatetime: json['end_datetime'] != null
          ? DateTime.parse(json['end_datetime'] as String).toLocal()
          : null,
      timezone: json['timezone'] as String,
      isVirtual: json['is_virtual'] as bool? ?? false,
      locationText: json['location_text'] as String?,
      locationMapsUrl: json['location_maps_url'] as String?,
    );
  }
}
