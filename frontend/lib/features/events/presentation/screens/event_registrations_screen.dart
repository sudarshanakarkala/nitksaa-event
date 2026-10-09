import 'dart:convert' show utf8;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

class EventRegistrationsScreen extends ConsumerStatefulWidget {
  const EventRegistrationsScreen({super.key, required this.eventId});

  final int eventId;

  @override
  ConsumerState<EventRegistrationsScreen> createState() =>
      _EventRegistrationsScreenState();
}

enum SortColumn { registrationNumber, fullName, batchYear, branch, registeredAt }

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

  // Sort state
  SortColumn _sortColumn = SortColumn.registeredAt;
  var _sortAscending = false;

  // Filter state
  int? _filterBatchYear;
  String? _filterBranch;

  // Available filter values (extracted from loaded data)
  final Set<int> _availableBatchYears = {};
  final Set<String> _availableBranches = {};

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
        batchYear: _filterBatchYear,
        branch: _filterBranch,
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
          // Collect available filter values
          for (final row in rows) {
            final by = row['batch_year_snapshot'] as int?;
            if (by != null) _availableBatchYears.add(by);
            final br = row['branch_snapshot'] as String?;
            if (br != null && br.isNotEmpty) _availableBranches.add(br);
          }
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

  // Getters for sorted attendees (client-side sorting)
  int _sortValue(Map<String, dynamic> a, Map<String, dynamic> b) {
    switch (_sortColumn) {
      case SortColumn.registrationNumber:
        final av = a['registration_number'] as String? ?? '';
        final bv = b['registration_number'] as String? ?? '';
        return av.compareTo(bv);
      case SortColumn.fullName:
        final av = a['fullname_snapshot'] as String? ?? '';
        final bv = b['fullname_snapshot'] as String? ?? '';
        return av.compareTo(bv);
      case SortColumn.batchYear:
        final av = a['batch_year_snapshot'] as int? ?? 0;
        final bv = b['batch_year_snapshot'] as int? ?? 0;
        return av.compareTo(bv);
      case SortColumn.branch:
        final av = a['branch_snapshot'] as String? ?? '';
        final bv = b['branch_snapshot'] as String? ?? '';
        return av.compareTo(bv);
      case SortColumn.registeredAt:
        final av = a['registered_at'] as String? ?? '';
        final bv = b['registered_at'] as String? ?? '';
        return av.compareTo(bv);
    }
  }

  List<Map<String, dynamic>> get _sortedAttendees {
    final sorted = List<Map<String, dynamic>>.from(_attendees);
    sorted.sort((a, b) {
      final result = _sortValue(a, b);
      return _sortAscending ? result : -result;
    });
    return sorted;
  }

  void _toggleSort(SortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  IconData _sortIcon(SortColumn column) {
    if (_sortColumn != column) return Icons.swap_vert;
    return _sortAscending ? Icons.arrow_upward : Icons.arrow_downward;
  }

  void _applyBatchYearFilter(int? year) {
    setState(() {
      _filterBatchYear = year;
      _page = 1;
      _attendees = [];
    });
    _fetchAttendees();
  }

  void _applyBranchFilter(String? branch) {
    setState(() {
      _filterBranch = branch;
      _page = 1;
      _attendees = [];
    });
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

  String _generateCsv() {
    final buffer = StringBuffer();
    // Header row
    buffer.writeln('Registration Number,Full Name,Batch Year,Branch,Registered At');
    // Data rows
    for (final attendee in _sortedAttendees) {
      final regNumber = (attendee['registration_number'] as String? ?? '-').replaceAll(',', '');
      final fullname = (attendee['fullname_snapshot'] as String? ?? 'Unknown').replaceAll(',', '');
      final batchYear = (attendee['batch_year_snapshot'] as int?)?.toString() ?? '-';
      final branch = (attendee['branch_snapshot'] as String? ?? '-').replaceAll(',', '');
      final registeredAt = _parseRegisteredAt(attendee['registered_at'] as String?).replaceAll(',', '');
      buffer.writeln('$regNumber,$fullname,$batchYear,$branch,$registeredAt');
    }
    return buffer.toString();
  }

  Future<void> _exportToCsv() async {
    if (_sortedAttendees.isEmpty) return;
    final csv = _generateCsv();
    final filename = 'event_${widget.eventId}_registrations.csv';

    // Convert to UTF-8 bytes for proper encoding
    final bytes = utf8.encode(csv);

    // Cross-platform file save (works on web, Android, iOS, desktop)
    await FileSaver.instance.saveFile(
      name: filename.replaceAll('.csv', ''),
      bytes: bytes,
      ext: 'csv',
      mimeType: MimeType.csv,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isWebScreen = MediaQuery.of(context).size.width >= 900;
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
                            if (_filterBatchYear != null || _filterBranch != null)
                              Chip(
                                label: Text(
                                  '${_filterBatchYear != null ? 'Year:$_filterBatchYear' : ''}${_filterBatchYear != null && _filterBranch != null ? ' ' : ''}${_filterBranch != null ? 'Branch:$_filterBranch' : ''}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () {
                                  setState(() {
                                    _filterBatchYear = null;
                                    _filterBranch = null;
                                    _page = 1;
                                    _attendees = [];
                                  });
                                  _fetchAttendees();
                                },
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            IconButton.filledTonal(
                              tooltip: 'Export to CSV',
                              onPressed: _sortedAttendees.isEmpty ? null : _exportToCsv,
                              icon: const Icon(Icons.download),
                            ),
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
    );
  }

  String _getMonth(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }

  Widget _buildSortableHeader(String label, SortColumn column,
      {Widget? trailing}) {
    final isActive = _sortColumn == column;
    return GestureDetector(
      onTap: () => _toggleSort(column),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
              color: isActive ? const Color(0xFFC9952A) : null,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            _sortIcon(column),
            size: 14,
            color: isActive ? const Color(0xFFC9952A) : Colors.grey,
          ),
          if (trailing != null) ...[const SizedBox(width: 2), trailing],
        ],
      ),
    );
  }

  Widget _buildBatchYearFilterDropdown() {
    final sortedYears = _availableBatchYears.toList()..sort((a, b) => b.compareTo(a));
    return PopupMenuButton<int?>(
      padding: EdgeInsets.zero,
      onSelected: (value) {
        _applyBatchYearFilter(value);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: null,
          child: Text('All Years', style: TextStyle(fontSize: 13)),
        ),
        ...sortedYears.map((year) => PopupMenuItem(
              value: year,
              child: Text(
                year.toString(),
                style: TextStyle(
                  fontSize: 13,
                  color: _filterBatchYear == year
                      ? const Color(0xFFC9952A)
                      : null,
                ),
              ),
            )),
      ],
      child: Icon(
        Icons.filter_list,
        size: 16,
        color: _filterBatchYear != null
            ? const Color(0xFFC9952A)
            : Colors.grey,
      ),
    );
  }

  Widget _buildBranchFilterDropdown() {
    final sortedBranches = _availableBranches.toList()..sort();
    return PopupMenuButton<String?>(
      padding: EdgeInsets.zero,
      onSelected: (value) {
        _applyBranchFilter(value);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: null,
          child: Text('All Branches', style: TextStyle(fontSize: 13)),
        ),
        ...sortedBranches.map((branch) => PopupMenuItem(
              value: branch,
              child: Text(
                branch,
                style: TextStyle(
                  fontSize: 13,
                  color: _filterBranch == branch
                      ? const Color(0xFFC9952A)
                      : null,
                ),
              ),
            )),
      ],
      child: Icon(
        Icons.filter_list,
        size: 16,
        color: _filterBranch != null
            ? const Color(0xFFC9952A)
            : Colors.grey,
      ),
    );
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

    final isWide = MediaQuery.of(context).size.width >= 700;
    final displayedAttendees = _sortedAttendees;

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
            itemCount: displayedAttendees.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == displayedAttendees.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final attendee = displayedAttendees[index];
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

    // Web/wide: table view with sortable headers and filter icons
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
          scrollDirection: Axis.horizontal,
          child: Container(
            constraints: BoxConstraints(
              minWidth:
                  MediaQuery.of(context).size.width - (MediaQuery.of(context).size.width >= 900 ? 340 : 80),
            ),
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
                columns: [
                  DataColumn(
                    label: _buildSortableHeader(
                        'Registration #', SortColumn.registrationNumber),
                  ),
                  DataColumn(
                    label: _buildSortableHeader(
                        'Full Name', SortColumn.fullName),
                  ),
                  DataColumn(
                    label: _buildSortableHeader('Batch Year', SortColumn.batchYear,
                        trailing: _buildBatchYearFilterDropdown()),
                  ),
                  DataColumn(
                    label: _buildSortableHeader('Branch', SortColumn.branch,
                        trailing: _buildBranchFilterDropdown()),
                  ),
                  DataColumn(
                    label: _buildSortableHeader(
                        'Registered At', SortColumn.registeredAt),
                  ),
                ],
                rows: displayedAttendees.map((attendee) {
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