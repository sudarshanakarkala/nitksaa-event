import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/filter_controls.dart';
import '../../../shared/widgets/list_page.dart';
import '../../../shared/widgets/quick_filter_pill.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/services/auth_controller.dart';
import '../data/dashboard_api.dart';
import '../../events/data/events_repository.dart';
import 'admin_tab_frame.dart';
import 'admin_widgets.dart';
import '../../../shared/format.dart';

/// Admin → Dashboard: how the events you administer are doing. The
/// period's numbers, upcoming events and their progress, the weekly trend
/// and who is registering. Past-event detail lives in Events, money in
/// Payments.
///
/// Same frame as the other admin tabs: the period pills are quick filters,
/// and the rail has the same choice.
class AdminDashboardTab extends ConsumerStatefulWidget {
  const AdminDashboardTab({super.key});

  @override
  ConsumerState<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends ConsumerState<AdminDashboardTab> {
  DashboardPeriod _period = DashboardPeriod.days30;

  /// One event ("how is it going?"), or [adminAllEvents] for the overview.
  int _event = adminAllEvents;
  List<AdminEventOption> _events = const [];
  DashboardData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _load();
      _loadEvents();
    });
  }

  /// For the picker; best effort (the overview works without it).
  Future<void> _loadEvents() async {
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    try {
      final all = await ref.read(eventsRepositoryProvider).getAllAdminEvents(token);
      all.sort((a, b) => b.startDatetime.compareTo(a.startDatetime));
      if (mounted) setState(() => _events = [for (final e in all) AdminEventOption.of(e)]);
    } catch (error) {
      AppLogger.warning('Admin dashboard: events not loaded: $error');
    }
  }

  void _setEvent(int id) {
    if (id == _event) return;
    setState(() => _event = id);
    _load();
  }

  Future<void> _load() async {
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    final period = _period;
    final event = _event;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(dashboardApiProvider).load(
            accessToken: token,
            period: period,
            eventId: event == adminAllEvents ? null : event,
          );
      if (!mounted || period != _period || event != _event) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Admin dashboard: load failed', error, stackTrace);
      if (!mounted || period != _period || event != _event) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error, action: 'load the dashboard');
      });
    }
  }

  void _setPeriod(DashboardPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  /// [pills]: the page's pill look (the rail on computers, like every
  /// list page's first filter).
  Widget _periodChips({bool pills = false}) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in DashboardPeriod.values)
            if (pills)
              QuickFilterPill(label: p.label, active: p == _period, onTap: () => _setPeriod(p))
            else
              FilterChipToggle(
                label: p.label,
                selected: p == _period,
                onChanged: (_) => _setPeriod(p),
              ),
        ],
      );

  /// [wide] (computers and tablets): the event picker is on the page, so
  /// the rail holds the period.
  Widget _rail({bool wide = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!wide) ...[
            const FilterLabel('Event'),
            const SizedBox(height: 8),
            AdminEventPicker(options: _events, selected: _event, onChanged: _setEvent),
            const SizedBox(height: 20),
          ],
          const FilterLabel('Period'),
          const SizedBox(height: 8),
          _periodChips(pills: wide),
        ],
      );

  @override
  Widget build(BuildContext context) {
    // No search or count line: an overview. The Filters icon sits at the
    // end of the period pills.
    return AdminTabFrame(
      picker: AdminEventPicker(
        options: _events,
        selected: _event,
        onChanged: _setEvent,
        width: AdminTabFrame.pickerWidth(context),
      ),
      pills: [
        for (final p in DashboardPeriod.values)
          QuickFilterPill(
            label: p.label,
            active: p == _period,
            onTap: () => _setPeriod(p),
          ),
      ],
      filters: (context) => _rail(wide: true),
      onOpenFilters: () => showFilterSheet(context, builder: (_) => _rail()),
      activeFilterCount: [_period != DashboardPeriod.days30, _event != adminAllEvents].where((on) => on).length,
      onClearFilters: () {
        setState(() {
          _period = DashboardPeriod.days30;
          _event = adminAllEvents;
        });
        _load();
      },
      loading: _loading && _data != null,
      body: _body(),
    );
  }

  Widget _body() {
    final p = context.palette;
    final data = _data;
    if (data == null) {
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 44, color: p.textMuted),
              const SizedBox(height: 12),
              Text(
                'Couldn\'t load the dashboard',
                style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(_error!, style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = ListPage.contentPadding(context, constraints.maxWidth);
        final inner = constraints.maxWidth - padding.horizontal;
        final wide = inner >= 900;
        final period = _period.label.toLowerCase();
        final charts = [
          _Card(
            title: 'Registrations per week',
            subtitle: 'Last 12 weeks',
            child: _WeeklyChart(weeks: data.weekly),
          ),
          _Card(
            title: 'Who\'s registering',
            subtitle: 'By graduation decade · $period',
            child: _DecadeChart(byDecade: data.byDecade),
          ),
        ];
        return RefreshIndicator(
          onRefresh: _load,
          color: p.primary,
          child: ListView(
            padding: padding,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _Tiles(
                width: inner,
                tiles: [
                  if (_event == adminAllEvents)
                    _TileData('Upcoming events', '${data.upcomingEvents}', 'Not yet ended · see Events',
                      onTap: () => context.go('/admin/events')),
                  _TileData('Registrations', '${data.registrations}', _period.label),
                  _TileData('Cancellations', '${data.cancellations}', _period.label),
                  _TileData('Money collected', formatMoney(data.money, wholeRupees: true), '${_period.label} · live payments'),
                ],
              ),
              const SizedBox(height: 20),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: charts[0]),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: charts[1]),
                  ],
                )
              else ...[
                charts[0],
                const SizedBox(height: 20),
                charts[1],
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Pieces ───────────────────────────────────────────────────────────────

class _TileData {
  const _TileData(this.label, this.value, this.sub, {this.onTap});

  final String label;
  final String value;
  final String sub;

  /// Opens the list behind the number (Upcoming events → Events).
  final VoidCallback? onTap;
}

/// Website stat cards: four in a row, two on phones.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.width, required this.tiles});

  final double width;
  final List<_TileData> tiles;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final perRow = width >= 760 ? tiles.length.clamp(1, 4) : 2;
    const gap = 16.0;
    final tileWidth = (width - gap * (perRow - 1)) / perRow;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final t in tiles)
          Material(
            color: p.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: p.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: t.onTap,
              hoverColor: p.surfaceHover,
              child: Container(
            width: tileWidth,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.value,
                  style: AppTextStyles.titleLarge.copyWith(fontSize: 28, color: p.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  t.label,
                  style: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
                ),
                Text(
                  t.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
                ),
              ],
            ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.titleMedium.copyWith(color: p.textPrimary)),
          if (subtitle != null)
            Text(subtitle!, style: AppTextStyles.bodySmall.copyWith(color: p.textMuted)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(color: context.palette.textMuted),
        ),
      );
}

/// Legend entry: a short line in the series colour, then its name.
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: context.palette.textSecondary),
          ),
        ],
      );
}

TextStyle _axisStyle(AppPalette p) =>
    AppTextStyles.labelSmall.copyWith(fontSize: 10.5, color: p.textMuted, letterSpacing: 0);

/// A round, readable top for the y axis.
double _niceMax(int max) {
  if (max <= 4) return 4;
  final magnitude = math.pow(10, (math.log(max) / math.ln10).floor()).toDouble();
  final step = magnitude / 2;
  return ((max / step).ceil() * step).toDouble();
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.weeks});

  final List<DashboardWeek> weeks;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final registrationsColor = p.primary;
    final cancellationsColor = p.info;
    final top = _niceMax(
      weeks.fold<int>(0, (m, w) => math.max(m, math.max(w.registrations, w.cancellations))),
    );
    List<FlSpot> spots(int Function(DashboardWeek) value) => [
          for (var i = 0; i < weeks.length; i++) FlSpot(i.toDouble(), value(weeks[i]).toDouble()),
        ];
    LineChartBarData line(List<FlSpot> data, Color color) => LineChartBarData(
          spots: data,
          color: color,
          barWidth: 2,
          isCurved: false,
          dotData: const FlDotData(show: false),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          children: [
            _LegendItem(color: registrationsColor, label: 'Registrations'),
            _LegendItem(color: cancellationsColor, label: 'Cancellations'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: weeks.isEmpty
              ? const _Empty('No data yet.')
              : LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: (weeks.length - 1).toDouble(),
                    minY: 0,
                    maxY: top,
                    lineBarsData: [
                      line(spots((w) => w.registrations), registrationsColor),
                      line(spots((w) => w.cancellations), cancellationsColor),
                    ],
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: top / 4,
                      getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 0.6),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          interval: top / 4,
                          getTitlesWidget: (value, meta) =>
                              Text(value.round().toString(), style: _axisStyle(p)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.round();
                            // Every other week, so labels never collide.
                            if (i < 0 || i >= weeks.length || i.isOdd) return const SizedBox.shrink();
                            final d = weeks[i].week;
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                formatDate(d).replaceFirst(' ${d.year}', ''),
                                style: _axisStyle(p),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DecadeChart extends StatelessWidget {
  const _DecadeChart({required this.byDecade});

  final Map<int, int> byDecade;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (byDecade.isEmpty) {
      return const SizedBox(height: 230, child: _Empty('No batch years in this period.'));
    }
    final decades = byDecade.keys.toList()..sort();
    final top = _niceMax(byDecade.values.fold<int>(0, math.max));
    return SizedBox(
      height: 230,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: top,
          barGroups: [
            for (var i = 0; i < decades.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: byDecade[decades[i]]!.toDouble(),
                    color: p.primary,
                    width: 18,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: top / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 0.6),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: top / 4,
                getTitlesWidget: (value, meta) =>
                    Text(value.round().toString(), style: _axisStyle(p)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= decades.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${decades[i]}s', style: _axisStyle(p)),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
