import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/filter_controls.dart';
import '../../../shared/widgets/list_page.dart';
import '../../../shared/widgets/notice.dart';
import '../../../shared/widgets/quick_filter_pill.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/domain/admin_access.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/screens/manage_events_screen.dart' show showEventFormDialog;
import '../data/payments_api.dart';
import '../domain/registration_filters.dart';
import 'admin_audit_tab.dart' show AuditTimeline;
import 'admin_widgets.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/state_message.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/list_search_field.dart';

enum _View {
  orders('Orders'),
  refunds('Refunds'),
  pricing('Paid events');

  const _View(this.label);
  final String label;
}

const _orderStatus = {
  'created': 'Started',
  'payment_pending': 'Pending',
  // Not a stored status: started or pending for over 30 minutes.
  'stuck': 'Stuck',
  'paid': 'Paid',
  'expired': 'Expired',
  'cancelled': 'Cancelled',
};

const _refundStatus = {
  'pending': 'Pending',
  'processing': 'Processing',
  // Refused for a temporary reason (e.g. low Razorpay balance); retried
  // automatically when new payments come in, or with Retry now.
  'delayed': 'Delayed',
  'processed': 'Refunded',
  // Couldn't be sent automatically: a person must act.
  'failed': 'Needs attention',
};

String _modeLabel(String mode) => mode == 'live' ? 'Live' : 'Test';

/// Admin → Payments: who paid what, refunds, and how each event charges.
/// Read-only: prices are set in the event form, refunds start when someone
/// cancels a paid registration.
///
/// Overall admins and payment roles (e.g. Finance) see every event; event
/// admins see their own. Same frame as the other admin tabs.
class AdminPaymentsTab extends ConsumerStatefulWidget {
  const AdminPaymentsTab({super.key});

  @override
  ConsumerState<AdminPaymentsTab> createState() => _AdminPaymentsTabState();
}

class _AdminPaymentsTabState extends ConsumerState<AdminPaymentsTab> {
  final _search = TextEditingController();

  List<AdminOrder> _orders = const [];
  List<AdminRefund> _refunds = const [];

  /// Events the person administers (empty for a Finance-only person, who
  /// can't load the admin event list).
  List<AppEvent> _events = const [];

  /// Event id → its payment setup (null = none yet).
  Map<int, EventPricing?> _pricing = const {};
  bool _loading = true;
  String? _error;

  _View _view = _View.orders;
  int _event = adminAllEvents;
  Set<String> _status = const {};
  Set<String> _mode = const {};

  final Map<_View, (String, bool)> _sorts = {
    _View.orders: ('created', false),
    _View.refunds: ('requested', false),
    _View.pricing: ('event', true),
  };

  /// Refund numbers with a Retry now in flight.
  final Set<String> _retrying = {};

  String? get _token => ref.read(authControllerProvider).session?.accessToken;
  AdminAccess get _access =>
      ref.read(authControllerProvider).session?.access ?? AdminAccess.none;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    Future.microtask(_load);
    // Links from Actions, e.g. /admin/payments?view=refunds&status=failed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final query = GoRouterState.of(context).uri.queryParameters;
      final view = _View.values.where((v) => v.name == query['view']).firstOrNull;
      if (view != null) _setView(view);
      final statuses = _view == _View.refunds ? _refundStatus : _orderStatus;
      final status = statuses[query['status']];
      if (status != null) setState(() => _status = {status});
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ref.read(paymentsApiProvider);
    try {
      final results = await Future.wait<Object>([api.orders(token), api.refunds(token)]);
      var events = const <AppEvent>[];
      if (_access.isAnyAdmin) {
        try {
          events = await ref.read(eventsRepositoryProvider).getAllAdminEvents(token);
        } catch (error) {
          AppLogger.warning('Payments: event list not loaded: $error');
        }
      }
      final orders = results[0] as List<AdminOrder>;
      final refunds = results[1] as List<AdminRefund>;

      // Paid events: from the event list, or (Finance-only) from the orders.
      final paidIds = <int>{
        for (final e in events)
          if (!(e.isFree ?? true)) e.eventId,
        if (events.isEmpty) ...{for (final o in orders) o.eventId},
      };
      final pricing = <int, EventPricing?>{};
      await Future.wait(paidIds.map((id) async {
        try {
          pricing[id] = await api.pricing(token, id);
        } catch (error) {
          AppLogger.warning('Payments: pricing for event $id not loaded: $error');
          pricing[id] = null;
        }
      }));

      if (!mounted) return;
      setState(() {
        _orders = orders;
        _refunds = refunds;
        _events = events;
        _pricing = pricing;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Payments: load failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error, action: 'load payments');
      });
    }
  }

  // ── Events ───────────────────────────────────────────────────────────────

  /// Every event that appears anywhere on this tab, newest first.
  List<AdminEventOption> get _eventOptions {
    final byId = <int, AdminEventOption>{
      for (final e in _events) e.eventId: AdminEventOption.of(e),
    };
    for (final o in _orders) {
      byId.putIfAbsent(o.eventId, () => AdminEventOption(o.eventId, o.eventTitle));
    }
    for (final r in _refunds) {
      byId.putIfAbsent(r.eventId, () => AdminEventOption(r.eventId, r.eventTitle));
    }
    final options = byId.values.toList()
      ..sort((a, b) => (b.start ?? DateTime(1970)).compareTo(a.start ?? DateTime(1970)));
    return options;
  }

  String _eventTitle(int id) {
    for (final e in _events) {
      if (e.eventId == id) return e.title;
    }
    for (final o in _orders) {
      if (o.eventId == id) return o.eventTitle;
    }
    return 'Event $id';
  }

  /// "Created by you" / "Created by Name"; null when unknown (e.g. a
  /// Finance-only person, who can't load the event list).
  String? _createdBy(int id) {
    final e = _appEvent(id);
    if (e == null) return null;
    return e.createdByLabel(ref.read(authControllerProvider).session?.firebaseUid);
  }

  AppEvent? _appEvent(int id) {
    for (final e in _events) {
      if (e.eventId == id) return e;
    }
    return null;
  }

  // ── Columns ──────────────────────────────────────────────────────────────

  bool get _isAll => _event == adminAllEvents;

  List<GridColumn<AdminOrder>> get _orderColumns => [
        GridColumn(id: 'name', label: 'Name', kind: ColumnKind.text, value: (o) => o.displayName),
        if (_isAll)
          GridColumn(id: 'event', label: 'Event', kind: ColumnKind.category, value: (o) => o.eventTitle),
        GridColumn(
          id: 'amount',
          label: 'Amount',
          kind: ColumnKind.number,
          value: (o) => o.amount,
          text: (o) => formatMoney(o.amount),
        ),
        GridColumn(
          id: 'status',
          label: 'Status',
          kind: ColumnKind.category,
          value: (o) => o.stuck ? _orderStatus['stuck']! : (_orderStatus[o.status] ?? o.status),
        ),
        GridColumn(id: 'mode', label: 'Mode', kind: ColumnKind.category, value: (o) => _modeLabel(o.mode)),
        GridColumn(id: 'created', label: 'Started', kind: ColumnKind.date, value: (o) => o.createdAt),
        GridColumn(id: 'paid', label: 'Paid', kind: ColumnKind.date, value: (o) => o.paidAt),
        GridColumn(id: 'number', label: 'Order #', kind: ColumnKind.text, value: (o) => o.orderNumber),
      ];

  // Refunds: what's needed to scan and act. The references and dates are in
  // the details window (tap a row).
  List<GridColumn<AdminRefund>> get _refundColumns => [
        GridColumn(id: 'name', label: 'Name', kind: ColumnKind.text, value: (r) => r.displayName),
        if (_isAll)
          GridColumn(id: 'event', label: 'Event', kind: ColumnKind.category, value: (r) => r.eventTitle),
        GridColumn(
          id: 'amount',
          label: 'Amount',
          kind: ColumnKind.number,
          value: (r) => r.amount,
          text: (r) => formatMoney(r.amount),
        ),
        GridColumn(
          id: 'status',
          label: 'Status',
          kind: ColumnKind.category,
          value: (r) => _refundStatus[r.status] ?? r.status,
        ),
        GridColumn(
          id: 'reason',
          label: 'Reason',
          kind: ColumnKind.text,
          value: (r) => r.reasonText ?? r.failureReason,
        ),
        GridColumn(id: 'tries', label: 'Tries', kind: ColumnKind.number, value: (r) => r.attemptCount),
        // The starting sort (newest first), so the arrow shows like on Orders.
        GridColumn(
          id: 'requested',
          label: 'Requested',
          kind: ColumnKind.date,
          value: (r) => r.requestedAt,
          text: (r) => formatShortDateTime(r.requestedAt),
        ),
        GridColumn(id: 'number', label: 'Refund ID', kind: ColumnKind.text, value: (r) => r.refundNumber),
        GridColumn(
          id: 'retry',
          label: 'Action',
          kind: ColumnKind.text,
          value: (r) => _mayRetry(r) ? 'Retry now' : '',
        ),
      ];

  /// Retry now: overall admins, Finance, and the event's own admins
  /// (same rule as the backend).
  bool _mayRetry(AdminRefund r) =>
      r.canRetry &&
      (_access.isAdmin ||
          _access.platformRoles.any(const {'platform_admin', 'finance_operator'}.contains) ||
          _access.canAdminEvent(r.eventId));

  Future<void> _retry(AdminRefund r) async {
    final token = _token;
    if (token == null || _retrying.contains(r.refundNumber)) return;
    setState(() => _retrying.add(r.refundNumber));
    String message;
    var kind = NoticeKind.info;
    try {
      final result = await ref.read(paymentsApiProvider).retryRefund(token, r.refundNumber);
      kind = switch (result.status) {
        'processed' => NoticeKind.success,
        'delayed' => NoticeKind.warning,
        'failed' => NoticeKind.error,
        _ => NoticeKind.info,
      };
      message = switch (result.status) {
        'processed' => 'Refund ${r.refundNumber} sent.',
        'pending' || 'processing' => 'Refund ${r.refundNumber} accepted by Razorpay; it will finish shortly.',
        'delayed' => 'Razorpay still can\'t take refund ${r.refundNumber}. '
            '${result.reasonText ?? ''}',
        'failed' => 'Refund ${r.refundNumber} needs attention. ${result.reasonText ?? ''}',
        _ => 'Refund ${r.refundNumber}: ${result.status}.',
      };
    } catch (error, stackTrace) {
      AppLogger.error('Payments: retry refund failed', error, stackTrace);
      message = apiErrorMessage(error, action: 'retry the refund');
      kind = NoticeKind.error;
    }
    if (!mounted) return;
    setState(() => _retrying.remove(r.refundNumber));
    showNotice(context, message.trim(), kind: kind);
    await _load();
  }

  /// One order: its facts, payment tries, refunds (with Razorpay ids to
  /// copy) and its history, oldest first.
  Future<void> _showOrderDetails(AdminOrder o) async {
    final token = _token;
    if (token == null) return;
    final details = ref.read(paymentsApiProvider).orderDetails(token, o.orderNumber);
    await showDialog<void>(
      context: context,
      builder: (context) => _OrderDetailsDialog(order: o, details: details),
    );
  }

  /// Everything about one refund, with copy buttons on the references and
  /// Retry now when allowed. Opened by tapping a row.
  Future<void> _showRefundDetails(AdminRefund r) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => _RefundDetailsDialog(
        refund: r,
        statusLabel: _refundStatus[r.status] ?? r.status,
        canRetry: _mayRetry(r),
      ),
    );
    if (retry == true && mounted) await _retry(r);
  }

  Map<String, ColumnFilter> get _filters => {
        if (_status.isNotEmpty) 'status': ColumnFilter(values: _status),
        if (_mode.isNotEmpty) 'mode': ColumnFilter(values: _mode),
      };

  List<AdminOrder> get _orderRows {
    final sort = _sorts[_View.orders]!;
    // Search also matches email, registration number and Razorpay ids,
    // which aren't columns.
    final q = _search.text.trim().toLowerCase();
    return applyGrid(
      [
        for (final o in _orders)
          if ((_isAll || o.eventId == _event) && (q.isEmpty || o.searchText.contains(q))) o,
      ],
      _orderColumns,
      filters: _filters,
      sortId: sort.$1,
      ascending: sort.$2,
    );
  }

  List<AdminRefund> get _refundRows {
    final sort = _sorts[_View.refunds]!;
    // Mode isn't a column here (it's in the details window), so it's applied
    // directly rather than through the column filters.
    return applyGrid(
      [
        for (final r in _refunds)
          if ((_isAll || r.eventId == _event) &&
              (_mode.isEmpty || _mode.contains(_modeLabel(r.mode))))
            r,
      ],
      _refundColumns,
      search: _search.text,
      filters: {if (_status.isNotEmpty) 'status': ColumnFilter(values: _status)},
      sortId: sort.$1,
      ascending: sort.$2,
    );
  }

  List<int> get _pricingRows {
    final q = _search.text.trim().toLowerCase();
    final ids = _pricing.keys.where((id) {
      if (!_isAll && id != _event) return false;
      if (_mode.isNotEmpty) {
        final p = _pricing[id];
        if (p == null || !_mode.contains(_modeLabel(p.mode))) return false;
      }
      return q.isEmpty || _eventTitle(id).toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => _eventTitle(a).toLowerCase().compareTo(_eventTitle(b).toLowerCase()));
    return ids;
  }

  int _count(_View v) => switch (v) {
        _View.orders => _orderRows.length,
        _View.refunds => _refundRows.length,
        _View.pricing => _pricingRows.length,
      };

  void _sortBy(String id, ColumnKind kind) {
    setState(() {
      final current = _sorts[_view]!;
      _sorts[_view] = current.$1 == id ? (id, !current.$2) : (id, kind != ColumnKind.date);
    });
  }

  void _setView(_View v) {
    if (v == _view) return;
    setState(() {
      _view = v;
      _status = const {}; // statuses differ between orders and refunds
    });
  }

  int get _activeFilterCount =>
      [_event != adminAllEvents, _status.isNotEmpty, _mode.isNotEmpty].where((on) => on).length;

  void _clearAll() {
    setState(() {
      _event = adminAllEvents;
      _status = const {};
      _mode = const {};
      _search.clear();
    });
  }

  Future<void> _editEvent(AppEvent e) async {
    if (await showEventFormDialog(context, event: e)) await _load();
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < ListPage.panelBreakpoint;
    final options = _eventOptions;
    final (one, many) = switch (_view) {
      _View.orders => ('order', 'orders'),
      _View.refunds => ('refund', 'refunds'),
      _View.pricing => ('paid event', 'paid events'),
    };

    return ListPage(
      search: ListSearchField(
        controller: _search,
        hint: switch (_view) {
              _View.pricing => 'Search events…',
              _View.orders => 'Search name, email, number or Razorpay id…',
              _View.refunds => 'Search name, email or number…',
            },
      ),
      quickFilters: [
        SizedBox(
          width: compact ? 240 : 320,
          child: AdminEventPicker(
            options: options,
            selected: _event,
            onChanged: (id) => setState(() => _event = id),
            width: compact ? 240 : 320,
          ),
        ),
        const SizedBox(width: 6),
        for (final v in _View.values)
          QuickFilterPill(
            label: v.label,
            count: _count(v),
            active: v == _view,
            onTap: () => _setView(v),
          ),
      ],
      count: _loading && _orders.isEmpty ? null : ResultCount(count: _count(_view), one: one, many: many),
      filters: (context) => _filterRail(options),
      onOpenFilters: () => showFilterSheet(
        context,
        builder: (_) => _filterRail(options),
        onClear: _clearAll,
      ),
      activeFilterCount: _activeFilterCount,
      onClearFilters: _clearAll,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading && _orders.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _filterRail(List<AdminEventOption> options) {
    final statuses = switch (_view) {
      _View.orders => _orderStatus,
      _View.refunds => _refundStatus,
      _View.pricing => const <String, String>{},
    };
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FilterLabel('Event'),
          const SizedBox(height: 8),
          AdminEventPicker(
            options: options,
            selected: _event,
            onChanged: (id) => setState(() => _event = id),
          ),
          const SizedBox(height: 20),
          FilterChipSection(
            label: 'Show',
            options: {for (final v in _View.values) v.name: v.label},
            selected: {_view.name},
            onChanged: (picked) {
              final added = picked.difference({_view.name});
              if (added.isNotEmpty) _setView(_View.values.byName(added.first));
            },
          ),
          if (statuses.isNotEmpty)
            FilterChipSection(
              label: 'Status',
              options: {for (final label in statuses.values) label: label},
              selected: _status,
              onChanged: (v) => setState(() => _status = v),
            ),
          FilterChipSection(
            label: 'Mode',
            options: const {'Test': 'Test', 'Live': 'Live'},
            selected: _mode,
            onChanged: (v) => setState(() => _mode = v),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final p = context.palette;
    if (_loading && _orders.isEmpty && _refunds.isEmpty && _pricing.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 44, color: p.textMuted),
              const SizedBox(height: 12),
              Text(
                'Couldn\'t load payments',
                style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(_error!, style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = ListPage.contentPadding(context, constraints.maxWidth, top: 20);
        final sort = _sorts[_view]!;
        final List<Widget> children;
        switch (_view) {
          case _View.orders:
            final rows = _orderRows;
            final stuck = rows.where((o) => o.stuck).length;
            children = [
              if (stuck > 0) ...[
                _Note(
                  text: stuck == 1
                      ? 'One payment has been pending for over 30 minutes.'
                      : '$stuck payments have been pending for over 30 minutes.',
                  warning: true,
                ),
                const SizedBox(height: 12),
              ],
              if (rows.isEmpty)
                const StateMessage(body: 'No orders match.')
              else
                AdminGridTable<AdminOrder>(
                  rows: rows,
                  columns: _orderColumns,
                  onRowTap: _showOrderDetails,
                  sortId: sort.$1,
                  ascending: sort.$2,
                  onSort: _sortBy,
                  cell: (c, o) => switch (c.id) {
                    'status' => StatusBadge(
                        label: o.stuck ? 'Pending · stuck' : (_orderStatus[o.status] ?? o.status),
                        tone: o.stuck
                            ? p.warning
                            : switch (o.status) {
                                'paid' => p.success,
                                'payment_pending' || 'created' => p.warning,
                                _ => p.textMuted,
                              },
                      ),
                    'mode' => StatusBadge.paymentMode(context, o.mode),
                    _ => null,
                  },
                ),
            ];
          case _View.refunds:
            final rows = _refundRows;
            final failed = rows.where((r) => r.status == 'failed').length;
            final delayed = rows.where((r) => r.status == 'delayed').length;
            children = [
              const _Note(text: 'Refunds start automatically when someone cancels a paid registration.'),
              const SizedBox(height: 8),
              if (failed > 0) ...[
                _Note(
                  text: failed == 1
                      ? 'One refund needs attention: it couldn\'t be sent automatically and the attendee '
                          'hasn\'t been paid back.'
                      : '$failed refunds need attention: they couldn\'t be sent automatically and those '
                          'attendees haven\'t been paid back.',
                  warning: true,
                ),
                const SizedBox(height: 8),
              ],
              if (delayed > 0) ...[
                _Note(
                  text: delayed == 1
                      ? 'One refund is delayed for a temporary reason. It is retried automatically when '
                          'new payments come in, or use Retry now.'
                      : '$delayed refunds are delayed for a temporary reason. They are retried automatically '
                          'when new payments come in, or use Retry now.',
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              if (rows.isEmpty)
                const StateMessage(body: 'No refunds match.')
              else
                AdminGridTable<AdminRefund>(
                  rows: rows,
                  columns: _refundColumns,
                  onRowTap: _showRefundDetails,
                  sortId: sort.$1,
                  ascending: sort.$2,
                  onSort: _sortBy,
                  cell: (c, r) => switch (c.id) {
                    'status' => StatusBadge(
                        label: _refundStatus[r.status] ?? r.status,
                        tone: switch (r.status) {
                          'processed' => p.success,
                          'failed' => p.error,
                          _ => p.warning,
                        },
                      ),
                    'mode' => StatusBadge.paymentMode(context, r.mode),
                    // Narrower than other text, so the row fits; the full
                    // reason is in the details window.
                    'reason' => (r.reasonText ?? r.failureReason) == null
                        ? null
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 190),
                            child: Text(
                              (r.reasonText ?? r.failureReason)!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: adminCellStyle(p),
                            ),
                          ),
                    'retry' => _mayRetry(r)
                        ? TextButton(
                            onPressed: _retrying.contains(r.refundNumber) ? null : () => _retry(r),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: Text(_retrying.contains(r.refundNumber) ? 'Retrying…' : 'Retry now'),
                          )
                        : const SizedBox.shrink(),
                    _ => null,
                  },
                ),
            ];
          case _View.pricing:
            final ids = _pricingRows;
            children = [
              const _Note(
                text: 'Prices are set in each event\'s form. Checkout follows them automatically.',
              ),
              const SizedBox(height: 12),
              if (ids.isEmpty)
                const StateMessage(body: 'No paid events.')
              else
                for (final id in ids) ...[
                  _PricingCard(
                    title: _eventTitle(id),
                    createdBy: _createdBy(id),
                    pricing: _pricing[id],
                    onEdit: _appEvent(id) != null && _access.canAdminEvent(id)
                        ? () => _editEvent(_appEvent(id)!)
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
            ];
        }
        return RefreshIndicator(
          onRefresh: _load,
          color: p.primary,
          child: ListView(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            children: children,
          ),
        );
      },
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────

class _PricingCard extends StatelessWidget {
  const _PricingCard({required this.title, required this.pricing, this.createdBy, this.onEdit});

  final String title;
  final String? createdBy;
  final EventPricing? pricing;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pr = pricing;
    Widget figure(String label, String value) => Padding(
          padding: const EdgeInsets.only(right: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTextStyles.labelSmall.copyWith(
                  color: p.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary),
                ),
              ),
              if (pr != null) StatusBadge.paymentMode(context, pr.mode),
              if (onEdit != null) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit in event'),
                ),
              ],
            ],
          ),
          if (createdBy != null)
            Text(createdBy!, style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary)),
          const SizedBox(height: 10),
          if (pr == null)
            Text(
              'No payment setup yet. It\'s created when the event is published.',
              style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
            )
          else
            Wrap(
              runSpacing: 10,
              children: [
                figure('Price', formatMoney(pr.baseAmount)),
                figure(
                  'GST',
                  !pr.gstEnabled
                      ? 'None'
                      : '${pr.gstRate.toStringAsFixed(pr.gstRate % 1 == 0 ? 0 : 1)}% '
                          '${pr.gstMode == 'inclusive' ? 'included' : 'added'}',
                ),
                figure(
                  'Fee',
                  !pr.feeEnabled
                      ? 'None'
                      : pr.feeType == 'percentage'
                      ? '${pr.feeValue.toStringAsFixed(pr.feeValue % 1 == 0 ? 0 : 1)}%'
                      : formatMoney(pr.feeValue),
                ),
                figure('Attendee pays', formatMoney(pr.finalAmount)),
                figure('Gateway', pr.gateway == 'razorpay' ? 'Razorpay' : pr.gateway),
                if (pr.updatedAt != null) figure('Price last changed', formatDate(pr.updatedAt!)),
              ],
            ),
        ],
      ),
    );
  }
}

class _RefundDetailsDialog extends StatelessWidget {
  const _RefundDetailsDialog({required this.refund, required this.statusLabel, required this.canRetry});

  final AdminRefund refund;
  final String statusLabel;
  final bool canRetry;

  @override
  Widget build(BuildContext context) {
    final r = refund;
    final rows = <(String, String?, bool)>[
      ('Name', r.fullname, false),
      ('Email', r.email, true),
      ('Event', r.eventTitle, false),
      ('Amount', formatMoney(r.amount), false),
      ('Status', statusLabel, false),
      ('Reason', r.reasonText ?? r.failureReason, false),
      ('Tries', '${r.attemptCount}', false),
      ('Mode', _modeLabel(r.mode), false),
      ('Refund ID', r.refundNumber, true),
      ('Order #', r.orderNumber, true),
      ('Payment ref', r.paymentRef, true),
      ('Gateway ref', r.providerRef, true),
      ('Bank ref', r.bankReference, true),
      ('Requested', formatDateTime(r.requestedAt), false),
      ('Updated', r.updatedAt == null ? null : formatDateTime(r.updatedAt!), false),
    ];
    final p = context.palette;
    return AlertDialog(
      title: const Text('Refund details'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (label, value, copy) in rows)
                if (value != null && value.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 110,
                          child: Text(label, style: AppTextStyles.bodySmall.copyWith(color: p.textMuted)),
                        ),
                        Expanded(
                          child: Text(value, style: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary)),
                        ),
                        if (copy)
                          IconButton(
                            tooltip: 'Copy $label',
                            icon: const Icon(Icons.copy, size: 16),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 20),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: value));
                              if (context.mounted) {
                                showNotice(context, '$label copied', kind: NoticeKind.success);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        if (canRetry)
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retry now'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _OrderDetailsDialog extends StatelessWidget {
  const _OrderDetailsDialog({required this.order, required this.details});

  final AdminOrder order;
  final Future<OrderDetails> details;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final p = context.palette;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(text, style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary)),
        );
    return AlertDialog(
      title: const Text('Order details'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AdminDetailRows(rows: [
                ('Name', o.fullname, false),
                ('Email', o.email, true),
                ('Event', o.eventTitle, false),
                ('Amount', formatMoney(o.amount), false),
                ('Status', o.stuck ? 'Pending · stuck' : (_orderStatus[o.status] ?? o.status), false),
                ('Mode', _modeLabel(o.mode), false),
                ('Order #', o.orderNumber, true),
                ('Registration', o.registrationNumber, true),
              ]),
              FutureBuilder<OrderDetails>(
                future: details,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        apiErrorMessage(snap.error!, action: 'load this order\'s history'),
                        style: AppTextStyles.bodySmall.copyWith(color: p.error),
                      ),
                    );
                  }
                  final d = snap.data;
                  if (d == null) {
                    return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in d.attempts) ...[
                        heading('Payment try ${a.number}'),
                        AdminDetailRows(rows: [
                          ('Status', a.status.replaceAll('_', ' '), false),
                          ('Method', a.method == null ? null : [a.method, a.instrument].whereType<String>().join(' · '), false),
                          ('Why it failed', a.failureText, false),
                          ('Razorpay order id', a.orderRef, true),
                          ('Razorpay payment id', a.paymentRef, true),
                          ('Bank ref', a.bankReference, true),
                        ]),
                      ],
                      for (final r in d.refunds) ...[
                        heading('Refund ${r.refundNumber}'),
                        AdminDetailRows(rows: [
                          ('Status', _refundStatus[r.status] ?? r.status, false),
                          ('Amount', formatMoney(r.amount), false),
                          ('Reason', r.reasonText ?? r.failureReason, false),
                          ('Tries', '${r.attemptCount}', false),
                          ('Razorpay refund id', r.providerRef, true),
                          ('Bank ref', r.bankReference, true),
                        ]),
                      ],
                      heading('History'),
                      if (d.timeline.isEmpty)
                        Text('Nothing recorded yet.', style: AppTextStyles.bodySmall.copyWith(color: p.textMuted))
                      else
                        AuditTimeline(entries: d.timeline),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = warning ? p.warning : p.textMuted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(warning ? Icons.warning_amber_outlined : Icons.info_outline, size: 16, color: tone),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary)),
        ),
      ],
    );
  }
}
