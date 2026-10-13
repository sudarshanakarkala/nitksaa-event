import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One "label: value" line of an entry's recorded details.
@immutable
class AuditDetail {
  const AuditDetail(this.label, this.value, {this.copy = false});

  final String label;
  final String value;

  /// A reference worth copying (Razorpay ids, bank reference).
  final bool copy;

  factory AuditDetail.fromJson(Map<String, dynamic> j) =>
      AuditDetail(j['label']?.toString() ?? '', j['value']?.toString() ?? '', copy: j['copy'] == true);
}

/// One audit log entry (`GET /api/v1/admin/audit-log`). People come by
/// name only; the server never sends uids.
@immutable
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.at,
    required this.type,
    required this.label,
    required this.category,
    required this.who,
    required this.actor,
    required this.details,
    this.eventId,
    this.eventTitle,
    this.registrationNumber,
    this.orderNumber,
  });

  final int id;
  final DateTime at;
  final String type;
  final String label;

  /// events / registrations / payments / roles.
  final String category;

  /// admin / attendee / system.
  final String who;
  final String actor;
  final int? eventId;

  /// "Deleted event #N" for an event that no longer exists.
  final String? eventTitle;
  final String? registrationNumber;
  final String? orderNumber;
  final List<AuditDetail> details;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: (j['log_id'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        type: j['event_type']?.toString() ?? '',
        label: j['event_label']?.toString() ?? '',
        category: j['category']?.toString() ?? '',
        who: j['who']?.toString() ?? '',
        actor: j['actor_fullname']?.toString() ?? '',
        eventId: (j['event_id'] as num?)?.toInt(),
        eventTitle: j['event_title']?.toString(),
        registrationNumber: j['registration_number']?.toString(),
        orderNumber: j['order_number']?.toString(),
        details: [
          for (final d in (j['details'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
            AuditDetail.fromJson(d),
        ],
      );
}

@immutable
class AuditPage {
  const AuditPage({required this.rows, required this.total, required this.page, required this.pages});

  final List<AuditEntry> rows;
  final int total;
  final int page;
  final int pages;
}

class AuditApi {
  AuditApi({Dio? dio}) : _dio = dio ?? _createDio();

  final Dio _dio;

  static Dio _createDio() {
    const configured = String.fromEnvironment('BACKEND_BASE_URL');
    const devConfigured = String.fromEnvironment('DEV_BACKEND_BASE_URL');
    final baseUrl = configured.isNotEmpty
        ? configured
        : devConfigured.isNotEmpty
        ? devConfigured
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

  /// One page, newest first. Filters are the server's: category, who,
  /// event, from (a date) and q (a name or event title).
  Future<AuditPage> list(
    String token, {
    int page = 1,
    int pageSize = 50,
    String? category,
    String? who,
    int? eventId,
    DateTime? from,
    String? q,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/admin/audit-log',
      queryParameters: {
        'page': page,
        'page_size': pageSize,
        'category': ?category,
        'who': ?who,
        'event_id': ?eventId,
        if (from != null)
          'from': '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}',
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final data = response.data ?? const <String, dynamic>{};
    return AuditPage(
      rows: [
        for (final r in (data['rows'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
          AuditEntry.fromJson(r),
      ],
      total: (data['total'] as num?)?.toInt() ?? 0,
      page: (data['page'] as num?)?.toInt() ?? page,
      pages: (data['pages'] as num?)?.toInt() ?? 1,
    );
  }
}

final auditApiProvider = Provider<AuditApi>((ref) => AuditApi());
