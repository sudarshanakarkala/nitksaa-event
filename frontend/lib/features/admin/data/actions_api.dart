import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logger/app_logger.dart';
import '../../auth/services/auth_controller.dart';

/// An event listed under a per-event queue (closing soon, nearly full,
/// confirmation emails failed).
@immutable
class PendingEvent {
  const PendingEvent({
    required this.eventId,
    required this.title,
    required this.start,
    this.closesAt,
    this.capacity,
    this.registered = 0,
    this.failed = 0,
  });

  final int eventId;
  final String title;
  final DateTime start;
  final DateTime? closesAt;
  final int? capacity;
  final int registered;

  /// Failed confirmation emails (failed-emails queue only).
  final int failed;

  factory PendingEvent.fromJson(Map<String, dynamic> j) => PendingEvent(
        eventId: _int(j['event_id']),
        title: j['title']?.toString() ?? '',
        start: _date(j['start_datetime']) ?? DateTime.now(),
        closesAt: _date(j['registration_closes_at']),
        capacity: j['capacity'] == null ? null : _int(j['capacity']),
        registered: _int(j['registered']),
        failed: _int(j['failed']),
      );
}

/// `GET /api/v1/admin/pending-count`: the Actions tab's queues, scoped to
/// the events the person administers. [total] is the Admin badge: only the
/// queues someone has to act on.
@immutable
class PendingCounts {
  const PendingCounts({
    this.total = 0,
    this.drafts = 0,
    this.closingSoon = 0,
    this.nearCapacity = 0,
    this.failedEmails = 0,
    this.stuckPayments = 0,
    this.failedRefunds = 0,
    this.closingSoonEvents = const [],
    this.nearCapacityEvents = const [],
    this.failedEmailEvents = const [],
  });

  final int total;
  final int drafts;
  final int closingSoon;
  final int nearCapacity;
  final int failedEmails;
  final int stuckPayments;
  final int failedRefunds;
  final List<PendingEvent> closingSoonEvents;
  final List<PendingEvent> nearCapacityEvents;
  final List<PendingEvent> failedEmailEvents;

  factory PendingCounts.fromJson(Map<String, dynamic> j) {
    final events = j['events'] is Map ? Map<String, dynamic>.from(j['events'] as Map) : const <String, dynamic>{};
    List<PendingEvent> list(String key) => [
          for (final e in (events[key] is List ? events[key] as List : const []))
            if (e is Map) PendingEvent.fromJson(Map<String, dynamic>.from(e)),
        ];
    return PendingCounts(
      total: _int(j['total']),
      drafts: _int(j['drafts']),
      closingSoon: _int(j['closing_soon']),
      nearCapacity: _int(j['near_capacity']),
      failedEmails: _int(j['failed_emails']),
      stuckPayments: _int(j['stuck_payments']),
      failedRefunds: _int(j['failed_refunds']),
      closingSoonEvents: list('closing_soon'),
      nearCapacityEvents: list('near_capacity'),
      failedEmailEvents: list('failed_emails'),
    );
  }
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class ActionsApi {
  ActionsApi({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    const devConfigured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
    final baseUrl = configured.isNotEmpty
        ? configured
        : devConfigured.isNotEmpty
        ? devConfigured
        : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ? 'http://10.0.2.2:8000'
        : 'http://127.0.0.1:8000';
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
  }

  Future<PendingCounts> pendingCount(String accessToken) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/pending-count',
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return PendingCounts.fromJson(response.data ?? const {});
  }
}

final actionsApiProvider = Provider<ActionsApi>((ref) => ActionsApi());

/// The Actions queues for the signed-in admin; null for anyone who isn't
/// one (finance-only people have no Actions tab). Shared by the Admin badge
/// and the Actions tab, so both show the same numbers. Invalidate it after
/// an admin change (see refreshEventLists) and when the window regains
/// focus.
final pendingCountProvider = FutureProvider<PendingCounts?>((ref) async {
  final session = ref.watch(authControllerProvider).session;
  if (session == null || !session.access.isAnyAdmin) return null;
  try {
    return await ref.read(actionsApiProvider).pendingCount(session.accessToken);
  } catch (error, stackTrace) {
    AppLogger.error('Admin actions: pending count failed', error, stackTrace);
    rethrow;
  }
});
