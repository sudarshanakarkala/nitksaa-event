import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

class ManageEventsScreen extends ConsumerStatefulWidget {
  const ManageEventsScreen({super.key});

  @override
  ConsumerState<ManageEventsScreen> createState() => _ManageEventsScreenState();
}

class _ManageEventsScreenState extends ConsumerState<ManageEventsScreen> {
  var _events = <AppEvent>[];
  var _isLoading = false;
  String? _errorMessage;

  bool get _isAdmin {
    final userType = ref.read(authControllerProvider).session?.userType;
    return userType?.toLowerCase() == 'admin';
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_fetchEvents);
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final data = await ref.read(eventsRepositoryProvider).getPublicEvents(
            page: 1,
            perPage: 100,
            period: 'upcoming',
          );
      final rawEvents = data['events'] as List<dynamic>? ?? [];
      setState(() {
        _events = rawEvents
            .map((json) => AppEvent.fromJson(json as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
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
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manage Events is available only for admin users.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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
            if (isWebScreen) _Sidebar(isDark: isDark, auth: auth),
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
                        const Text(
                          'Manage Events',
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Refresh',
                              onPressed: _isLoading ? null : _fetchEvents,
                              icon: const Icon(Icons.refresh),
                            ),
                            FilledButton.icon(
                              onPressed: () => _showEventForm(),
                              icon: const Icon(Icons.add),
                              label: const Text('Create Event'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_events.length} upcoming events',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _errorMessage != null
                              ? _ErrorState(
                                  message: _errorMessage!,
                                  onRetry: _fetchEvents,
                                )
                              : _events.isEmpty
                                  ? const _EmptyState()
                                  : RefreshIndicator(
                                      onRefresh: _fetchEvents,
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final columns =
                                              constraints.maxWidth > 980 ? 2 : 1;
                                          return GridView.builder(
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: columns,
                                              crossAxisSpacing: 20,
                                              mainAxisSpacing: 20,
                                              mainAxisExtent: 250,
                                            ),
                                            itemCount: _events.length,
                                            itemBuilder: (context, index) {
                                              final event = _events[index];
                                              return _ManageEventCard(
                                                event: event,
                                                isDark: isDark,
                                                onView: () => context.push(
                                                  '/events/${event.eventId}',
                                                ),
                                                onEdit: () => _showEventForm(event: event),
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
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

  Future<void> _showEventForm({AppEvent? event}) async {
    if (!_isAdmin) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EventFormDialog(event: event),
    );
    if (saved == true) {
      await _fetchEvents();
    }
  }
}

class _EventFormDialog extends ConsumerStatefulWidget {
  const _EventFormDialog({this.event});

  final AppEvent? event;

  @override
  ConsumerState<_EventFormDialog> createState() => _EventFormDialogState();
}

class _EventFormDialogState extends ConsumerState<_EventFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _capacity;
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _title = TextEditingController(text: event?.title ?? '');
    _description = TextEditingController(text: event?.description ?? '');
    _location = TextEditingController(text: event?.locationText ?? '');
    _start = TextEditingController(text: _formatInput(event?.startDatetime));
    _end = TextEditingController(text: _formatInput(event?.endDatetime));
    _capacity = TextEditingController(text: event?.capacity?.toString() ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _start.dispose();
    _end.dispose();
    _capacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.event != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Event' : 'Create Event'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_title, 'Title', required: true),
                _field(_description, 'Description', maxLines: 3),
                _field(_location, 'Location', required: true),
                _field(_start, 'Start date/time', hint: '2026-07-15 18:00', required: true),
                _field(_end, 'End date/time', hint: '2026-07-15 20:00', required: true),
                _field(_capacity, 'Capacity', keyboardType: TextInputType.number),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: Text(_isSaving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint),
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: required
            ? (value) => value == null || value.trim().isEmpty ? 'Required' : null
            : null,
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final start = _parseInput(_start.text);
    final end = _parseInput(_end.text);
    if (start == null || end == null || !end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid start and end time.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final auth = ref.read(authControllerProvider);
      final data = <String, dynamic>{
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'start_datetime': start.toUtc().toIso8601String(),
        'end_datetime': end.toUtc().toIso8601String(),
        'timezone': 'Asia/Kolkata',
        'location_text': _location.text.trim(),
        'is_virtual': false,
        if (_capacity.text.trim().isNotEmpty)
          'capacity': int.tryParse(_capacity.text.trim()),
      };
      final repo = ref.read(eventsRepositoryProvider);
      if (widget.event == null) {
        await repo.createAdminEvent(data, auth.session!.accessToken);
      } else {
        await repo.updateAdminEvent(widget.event!.eventId, data, auth.session!.accessToken);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save event: $error')),
      );
    }
  }

  static String _formatInput(DateTime? value) {
    if (value == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  static DateTime? _parseInput(String value) {
    final normalized = value.trim().replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }
}

class _ManageEventCard extends StatelessWidget {
  const _ManageEventCard({
    required this.event,
    required this.isDark,
    required this.onView,
    required this.onEdit,
  });

  final AppEvent event;
  final bool isDark;
  final VoidCallback onView;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                _StatusPill(label: event.registrationStatus),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              event.description ?? 'No description provided.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            _MetaRow(icon: Icons.event, label: _formatDateTime(event.startDatetime)),
            const SizedBox(height: 6),
            _MetaRow(
              icon: event.isVirtual ? Icons.videocam_outlined : Icons.place_outlined,
              label: event.locationText ?? (event.isVirtual ? 'Virtual event' : 'Location pending'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('View'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = value.hour == 0 ? 12 : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day} ${months[value.month - 1]} ${value.year}, $hour:$minute $period';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFD9F4E8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: const TextStyle(
          color: Color(0xFF1B5C3A),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFC9952A)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.isDark, required this.auth});

  final bool isDark;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 240,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E1726) : const Color(0xFFF8F9FD),
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calendar_today_outlined, color: Color(0xFFC9952A)),
              SizedBox(width: 8),
              Text(
                'NITKSAA',
                style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFC9952A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _SidebarItem(
            icon: Icons.calendar_month,
            label: 'Events',
            active: false,
            onTap: () => context.go(AppRoutes.home),
          ),
          _SidebarItem(
            icon: Icons.bookmark,
            label: 'My Events',
            active: false,
            onTap: () => context.go(AppRoutes.myEvents),
          ),
          const _SidebarItem(
            icon: Icons.admin_panel_settings,
            label: 'Manage Events',
            active: true,
          ),
          const Spacer(),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFC9952A),
                child: Text(
                  (auth.session?.fullname ?? 'U').substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  auth.session?.fullname ?? 'Admin User',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBg = isDark ? const Color(0xFF1C2A40) : const Color(0xFFEEF3FA);
    final activeText = isDark ? Colors.white : const Color(0xFF0D1B3E);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: active ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        visualDensity: VisualDensity.compact,
        leading: Icon(
          icon,
          size: 20,
          color: active ? activeText : const Color(0xFF5A6A8A),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: active ? activeText : const Color(0xFF5A6A8A),
            fontSize: 13,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy, size: 48),
          SizedBox(height: 12),
          Text('No upcoming events to manage.'),
        ],
      ),
    );
  }
}
