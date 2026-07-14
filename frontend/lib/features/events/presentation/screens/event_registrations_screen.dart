import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';
import '../../../../shared/widgets/app_sidebar.dart';

class EventRegistrationsScreen extends ConsumerStatefulWidget {
  const EventRegistrationsScreen({super.key, required this.eventId});

  final int eventId;

  @override
  ConsumerState<EventRegistrationsScreen> createState() =>
      _EventRegistrationsScreenState();
}

class _EventRegistrationsScreenState
    extends ConsumerState<EventRegistrationsScreen> {
  var _attendees = <Map<String, dynamic>>[];
  var _total = 0;
  var _isLoading = true;
  String? _errorMessage;
  var _page = 1;
  final _perPage = 50;
  var _hasMore = false;
  AppEvent? _event;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_searchController.text == _searchController.text) {
        setState(() {
          _page = 1;
          _attendees = [];
        });
        _fetchAttendees();
      }
    });
  }

  Future<void> _loadData() async {
    await _fetchEvent();
    await _fetchAttendees();
  }

  Future<void> _fetchEvent() async {
    try {
      final repo = ref.read(eventsRepositoryProvider);
      final auth = ref.read(authControllerProvider);
      if (auth.session?.accessToken != null) {
        final data = await repo.getAdminEvents(
          page: 1,
          perPage: 100,
          period: 'all',
          accessToken: auth.session!.accessToken,
        );
        final rawEvents = data['events'] as List<dynamic>? ?? [];
        final events = rawEvents
            .map((json) => AppEvent.fromJson(json as Map<String, dynamic>))
            .toList();
        final found =
            events.where((e) => e.eventId == widget.eventId).firstOrNull;
        if (found != null && mounted) {
          setState(() => _event = found);
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchAttendees() async {
    setState(() {
      _isLoading = _page == 1;
      _errorMessage = null;
    });
    try {
      final auth = ref.read(authControllerProvider);
      final accessToken = auth.session?.accessToken;
      if (accessToken == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Not authenticated';
        });
        return;
      }
      final repo = ref.read(eventsRepositoryProvider);
      final response = await repo.getEventAttendees(
        eventId: widget.eventId,
        accessToken: accessToken,
        page: _page,
        perPage: _perPage,
        search:
            _searchController.text.isNotEmpty ? _searchController.text : null,
      );
      final rows = (response['attendees'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      final total = response['total'] as int? ?? 0;
      if (mounted) {
        setState(() {
          if (_page == 1) {
            _attendees = rows;
          } else {
            _attendees.addAll(rows);
          }
          _total = total;
          _hasMore = _attendees.length < total;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = error.toString();
        });
      }
    }
  }

  void _loadMore() {
    if (!_hasMore || _isLoading) return;
    setState(() => _page++);
    _fetchAttendees();
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour =
        dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour:$minute $period';
  }

  String _parseRegisteredAt(String? raw) {
    if (raw == null) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return _formatDateTime(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWebScreen = kIsWeb || MediaQuery.of(context).size.width > 900;
    final isAdmin = auth.session?.userType.toLowerCase() == 'admin';

    if (!auth.isAuthenticated || !isAdmin) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, size: 56),
                    const SizedBox(height: 16),
                    const Text(
                      'Admin access required',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Event registrations are available only for admin users.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => context.go(AppRoutes.home),
                      child: const Text('Back to Events'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (isWebScreen) const AppSidebar(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isWebScreen ? 32 : 20,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => context.go(AppRoutes.manageEvents),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.arrow_back,
                                        size: 18,
                                        color: Color(0xFFC9952A)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Back to Manage Events',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: const Color(0xFFC9952A),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _event?.title ?? 'Event Registrations',
                                style: const TextStyle(
                                  fontFamily: 'Fraunces',
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_event != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${_event!.startDatetime.day} ${_getMonth(_event!.startDatetime.month)} ${_event!.startDatetime.year}'
                                    '${_event!.locationText != null ? ' · ${_event!.locationText}' : ''}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Refresh',
                              onPressed: _isLoading ? null : _loadData,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$_total attendee${_total == 1 ? '' : 's'} registered',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildContent(theme, isDark),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWebScreen
          ? null
          : NavigationBar(
              selectedIndex: 2,
              onDestinationSelected: (index) {
                if (index == 0) context.go(AppRoutes.home);
                if (index == 1) context.go(AppRoutes.myEvents);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_month),
                  label: 'Events',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bookmark),
                  label: 'My Events',
                ),
                NavigationDestination(
                  icon: Icon(Icons.admin_panel_settings),
                  label: 'Manage',
                ),
              ],
            ),
    );
  }

  String _getMonth(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  Widget _buildContent(ThemeData theme, bool isDark) {
    if (_isLoading && _attendees.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_attendees.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _searchController.text.isNotEmpty
                  ? Icons.search_off
                  : Icons.people_outline,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No attendees match your search'
                  : 'No registrations yet',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _searchController.text.isNotEmpty
                  ? 'Try a different search term'
                  : 'Attendees will appear here once they register.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width > 700 || kIsWeb;

    if (!isWide) {
      return RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _page = 1;
            _attendees = [];
          });
          await _fetchAttendees();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (scrollInfo) {
            if (scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 100 &&
                _hasMore &&
                !_isLoading) {
              _loadMore();
            }
            return false;
          },
          child: ListView.builder(
            itemCount: _attendees.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == _attendees.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final attendee = _attendees[index];
              return _AttendeeCard(
                attendee: attendee,
                theme: theme,
                formatDateTime: _parseRegisteredAt,
              );
            },
          ),
        ),
      );
    }

    // Web/wide: table view matching mockup "13 · Attendee List (Data Table)"
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _page = 1;
          _attendees = [];
        });
        await _fetchAttendees();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          if (scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent - 100 &&
              _hasMore &&
              !_isLoading) {
            _loadMore();
          }
          return false;
        },
        child: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  isDark
                      ? const Color(0xFF111827)
                      : const Color(0xFFF8F9FD),
                ),
                columnSpacing: 24,
                columns: const [
                  DataColumn(
                    label: Text(
                      'Registration #',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Full Name',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Batch Year',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Branch',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Registered At',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                rows: _attendees.map((attendee) {
                  final regNumber =
                      attendee['registration_number'] as String? ?? '-';
                  final fullname =
                      attendee['fullname_snapshot'] as String? ?? 'Unknown';
                  final batchYear =
                      attendee['batch_year_snapshot'] as int?;
                  final branch =
                      attendee['branch_snapshot'] as String? ?? '-';
                  final registeredAt = _parseRegisteredAt(
                      attendee['registered_at'] as String?);

                  return DataRow(cells: [
                    DataCell(Text(
                      regNumber,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    )),
                    DataCell(Text(fullname)),
                    DataCell(Text(batchYear?.toString() ?? '-')),
                    DataCell(Text(branch)),
                    DataCell(Text(
                      registeredAt,
                      style: const TextStyle(fontSize: 12),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttendeeCard extends StatelessWidget {
  const _AttendeeCard({
    required this.attendee,
    required this.theme,
    required this.formatDateTime,
  });

  final Map<String, dynamic> attendee;
  final ThemeData theme;
  final String Function(String?) formatDateTime;

  @override
  Widget build(BuildContext context) {
    final regNumber = attendee['registration_number'] as String? ?? '-';
    final fullname = attendee['fullname_snapshot'] as String? ?? 'Unknown';
    final batchYear = attendee['batch_year_snapshot'] as int?;
    final branch = attendee['branch_snapshot'] as String? ?? '-';
    final registeredAt = formatDateTime(attendee['registered_at'] as String?);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  fullname,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDEEFF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    regNumber,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1B5C9B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildInfoChip(
                    Icons.school_outlined, batchYear?.toString() ?? '-'),
                const SizedBox(width: 16),
                _buildInfoChip(Icons.account_tree_outlined, branch),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  registeredAt,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFFC9952A)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}