import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Time window for the dashboard's tiles and decade chart.
enum DashboardPeriod {
  days30('30d', 'Last 30 days'),
  days90('90d', 'Last 90 days'),
  year('year', 'This year'),
  all('all', 'All time');

  const DashboardPeriod(this.value, this.label);
  final String value;
  final String label;
}

/// An upcoming event's progress.
@immutable
class DashboardUpcoming {
  const DashboardUpcoming({
    required this.eventId,
    required this.title,
    required this.start,
    required this.status,
    required this.registered,
    required this.newThisWeek,
    required this.checkedIn,
    required this.registrationStatus,
    this.end,
    this.capacity,
  });

  final int eventId;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String status;
  final int? capacity;
  final int registered;
  final int newThisWeek;
  final int checkedIn;

  /// open / closed / full / not_open_yet / not_applicable (drafts).
  final String registrationStatus;

  /// The event is happening now.
  bool get isToday {
    final now = DateTime.now();
    return !start.isAfter(now) && !(end ?? start.add(const Duration(hours: 6))).isBefore(now);
  }

  factory DashboardUpcoming.fromJson(Map<String, dynamic> j) => DashboardUpcoming(
        eventId: _int(j['event_id']),
        title: j['title']?.toString() ?? '',
        start: _date(j['start_datetime']) ?? DateTime.now(),
        end: _date(j['end_datetime']),
        status: j['status']?.toString() ?? '',
        capacity: j['capacity'] == null ? null : _int(j['capacity']),
        registered: _int(j['registered']),
        newThisWeek: _int(j['new_7d']),
        checkedIn: _int(j['checked_in']),
        registrationStatus: j['registration_status']?.toString() ?? '',
      );
}

/// How a past event went.
@immutable
class DashboardRecent {
  const DashboardRecent({
    required this.eventId,
    required this.title,
    required this.start,
    required this.registered,
    required this.checkedIn,
    required this.noShows,
    required this.money,
  });

  final int eventId;
  final String title;
  final DateTime start;
  final int registered;
  final int checkedIn;
  final int noShows;
  final double money;

  factory DashboardRecent.fromJson(Map<String, dynamic> j) => DashboardRecent(
        eventId: _int(j['event_id']),
        title: j['title']?.toString() ?? '',
        start: _date(j['start_datetime']) ?? DateTime.now(),
        registered: _int(j['registered']),
        checkedIn: _int(j['checked_in']),
        noShows: _int(j['no_shows']),
        money: _double(j['money_collected']),
      );
}

@immutable
class DashboardWeek {
  const DashboardWeek(this.week, this.registrations, this.cancellations);

  final DateTime week;
  final int registrations;
  final int cancellations;
}

/// `GET /api/v1/admin/dashboard`, scoped to the events you administer.
@immutable
class DashboardData {
  const DashboardData({
    required this.upcomingEvents,
    required this.registrations,
    required this.cancellations,
    required this.money,
    required this.upcoming,
    required this.recent,
    required this.weekly,
    required this.byDecade,
  });

  final int upcomingEvents;
  final int registrations;
  final int cancellations;

  /// LIVE payments only.
  final double money;
  final List<DashboardUpcoming> upcoming;
  final List<DashboardRecent> recent;
  final List<DashboardWeek> weekly;

  /// Decade (1990, 2000 …) → registrations.
  final Map<int, int> byDecade;

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final tiles = j['tiles'] as Map<String, dynamic>? ?? const {};
    List<Map<String, dynamic>> list(String key) =>
        (j[key] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().toList();
    return DashboardData(
      upcomingEvents: _int(tiles['upcoming_events']),
      registrations: _int(tiles['registrations']),
      cancellations: _int(tiles['cancellations']),
      money: _double(tiles['money_collected']),
      upcoming: list('upcoming').map(DashboardUpcoming.fromJson).toList(),
      recent: list('recent').map(DashboardRecent.fromJson).toList(),
      weekly: [
        for (final w in list('weekly'))
          DashboardWeek(
            DateTime.tryParse(w['week']?.toString() ?? '') ?? DateTime.now(),
            _int(w['registrations']),
            _int(w['cancellations']),
          ),
      ],
      byDecade: {for (final d in list('by_decade')) _int(d['decade']): _int(d['count'])},
    );
  }
}

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

double _double(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class DashboardApi {
  DashboardApi({Dio? dio}) : _dio = dio ?? _createDio();

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
        receiveTimeout: const Duration(seconds: 90),
        headers: const {'Content-Type': 'application/json'},
      ),
    );
  }

  Future<DashboardData> load({
    required String accessToken,
    required DashboardPeriod period,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/dashboard',
      queryParameters: {'period': period.value},
      options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
    );
    return DashboardData.fromJson(response.data ?? const {});
  }
}

final dashboardApiProvider = Provider<DashboardApi>((ref) => DashboardApi());
