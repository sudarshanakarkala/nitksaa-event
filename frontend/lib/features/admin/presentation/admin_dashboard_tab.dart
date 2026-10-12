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
import '../domain/registration_filters.dart' show formatDate;

/// Admin → Dashboard: how the events you administer are doing. Upcoming
/// events and their progress first, then the period's numbers, the weekly
/// trend, how recent events went, and who is registering.
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
  DashboardData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final token = ref.read(authControllerProvider).session?.accessToken;
    if (token == null) return;
    final period = _period;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(dashboardApiProvider).load(accessToken: token, period: period);
      if (!mounted || period != _period) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Admin dashboard: load failed', error, stackTrace);
      if (!mounted || period != _period) return;
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

  Widget _periodChips() => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in DashboardPeriod.values)
            FilterChipToggle(
              label: p.label,
              selected: p == _period,
              onChanged: (_) => _setPeriod(p),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ListPage(
      quickFilters: [
        for (final p in DashboardPeriod.values)
          QuickFilterPill(
            label: p.label,
            active: p == _period,
            onTap: () => _setPeriod(p),
          ),
      ],
      filters: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FilterLabel('Period'),
          const SizedBox(height: 8),
          _periodChips(),
        ],
      ),
      onOpenFilters: () => showFilterSheet(
        context,
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FilterLabel('Period'),
            const SizedBox(height: 8),
            _periodChips(),
          ],
        ),
      ),
      activeFilterCount: _period == DashboardPeriod.days30 ? 0 : 1,
      onClearFilters: () => _setPeriod(DashboardPeriod.days30),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading && _data != null) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body()),
        ],
      ),
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
                  _TileData('Upcoming events', '${data.upcomingEvents}', 'Not yet ended'),
                  _TileData('Registrations', '${data.registrations}', _period.label),
                  _TileData('Cancellations', '${data.cancellations}', _period.label),
                  _TileData('Money collected', _money(data.money), '${_period.label} · live payments'),
                ],
              ),
              const SizedBox(height: 20),
              _Card(
                title: 'Upcoming events',
                subtitle: 'Soonest first · tap one to see its registrations',
                child: data.upcoming.isEmpty
                    ? const _Empty('No upcoming events.')
                    : Column(
                        children: [
                          for (var i = 0; i < data.upcoming.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: p.border),
                            _UpcomingRow(
                              event: data.upcoming[i],
                              onTap: () => context.go(
                                '/admin/registrations?event=${data.upcoming[i].eventId}',
                              ),
                            ),
                          ],
                        ],
                      ),
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
              const SizedBox(height: 20),
              _Card(
                title: 'Recent events',
                subtitle: 'How the last few went',
                child: data.recent.isEmpty
                    ? const _Empty('No past events yet.')
                    : Column(
                        children: [
                          for (var i = 0; i < data.recent.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: p.border),
                            _RecentRow(
                              event: data.recent[i],
                              onTap: () => context.go(
                                '/admin/registrations?event=${data.recent[i].eventId}',
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ₹ with Indian digit grouping, whole rupees.
String _money(double amount) {
  final digits = amount.round().toString();
  if (digits.length <= 3) return '₹$digits';
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (rest.length > 2) {
    groups.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) groups.insert(0, rest);
  return '₹${groups.join(',')},$last3';
}

String _daysToGo(DashboardUpcoming e) {
  if (e.isToday) return 'Today';
  final today = DateUtils.dateOnly(DateTime.now());
  final days = DateUtils.dateOnly(e.start).difference(today).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}

// ── Pieces ───────────────────────────────────────────────────────────────

class _TileData {
  const _TileData(this.label, this.value, this.sub);

  final String label;
  final String value;
  final String sub;
}

/// Website stat cards: four in a row, two on phones.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.width, required this.tiles});

  final double width;
  final List<_TileData> tiles;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final perRow = width >= 760 ? 4 : 2;
    const gap = 16.0;
    final tileWidth = (width - gap * (perRow - 1)) / perRow;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final t in tiles)
          Container(
            width: tileWidth,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.card,
              border: Border.all(color: p.border),
              borderRadius: BorderRadius.circular(12),
            ),
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

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.event, required this.onTap});

  final DashboardUpcoming event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final cap = e.capacity;
    final fraction = cap != null && cap > 0 ? (e.registered / cap).clamp(0.0, 1.0).toDouble() : null;
    final tone = fraction == null
        ? p.primary
        : fraction >= 1
        ? p.error
        : fraction >= 0.9
        ? p.warning
        : p.primary;
    final (statusLabel, statusTone) = switch (e.registrationStatus) {
      _ when e.status == 'draft' => ('Draft', p.warning),
      'open' => ('Registration open', p.success),
      'full' => ('Full', p.error),
      'closed' => ('Registration closed', p.textMuted),
      'not_open_yet' => ('Opens later', p.textMuted),
      _ => ('', p.textMuted),
    };
    final secondary = AppTextStyles.bodySmall.copyWith(color: p.textSecondary);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary),
                  ),
                ),
                if (statusLabel.isNotEmpty) _Badge(label: statusLabel, tone: statusTone),
              ],
            ),
            const SizedBox(height: 2),
            Text('${formatDate(e.start)} · ${_daysToGo(e)}', style: secondary),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: fraction ?? 0,
                      minHeight: 6,
                      backgroundColor: p.surfaceHover,
                      valueColor: AlwaysStoppedAnimation<Color>(tone),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  cap == null ? '${e.registered} registered' : '${e.registered} / $cap',
                  style: AppTextStyles.labelMedium.copyWith(color: p.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              e.isToday
                  ? 'Checked in ${e.checkedIn} of ${e.registered}'
                  : e.newThisWeek > 0
                  ? '+${e.newThisWeek} this week'
                  : 'No new registrations this week',
              style: secondary.copyWith(
                color: e.isToday || e.newThisWeek > 0 ? p.textSecondary : p.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.event, required this.onTap});

  final DashboardRecent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final attendance = e.registered > 0 ? '${(e.checkedIn * 100 / e.registered).round()}%' : '—';
    Widget figure(String label, String value) => Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary)),
              Text(label, style: AppTextStyles.bodySmall.copyWith(color: p.textMuted)),
            ],
          ),
        );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              e.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary),
            ),
            Text(
              formatDate(e.start),
              style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              runSpacing: 8,
              children: [
                figure('Registered', '${e.registered}'),
                figure('Attended', '${e.checkedIn} · $attendance'),
                figure('No-shows', '${e.noShows}'),
                figure('Money', _money(e.money)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          border: Border.all(color: tone.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: tone,
          ),
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
