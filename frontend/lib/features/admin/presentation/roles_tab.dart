import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../shared/widgets/site_toggle.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../data/admin_api.dart';
import '../../../shared/widgets/list_page.dart';
import '../../../shared/widgets/notice.dart';
import '../../../shared/widgets/state_message.dart';
import '../../../shared/widgets/list_search_field.dart';

/// Roles tab (overall admins only): search people and switch their
/// "Overall admin", "Can create events" and "Finance" roles. Per-event
/// admins are managed on the event itself (Events tab, step 5). Finance is
/// the backend's finance_operator payment role: sees every event's payments
/// and refunds without being an admin.
class RolesTab extends ConsumerStatefulWidget {
  const RolesTab({super.key});

  @override
  ConsumerState<RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends ConsumerState<RolesTab> {
  final _search = TextEditingController();
  Timer? _debounce;

  AdminUserPage? _result;
  bool _loading = false;
  String? _error;

  /// uids with a change in flight; their switches are disabled meanwhile.
  final Set<String> _saving = {};

  /// event_id → title, for the "Admin of N events" list.
  Map<int, String> _eventTitles = const {};

  /// uid → their active Finance grant.
  Map<String, PaymentRoleGrant> _finance = const {};

  String? get _token => ref.read(authControllerProvider).session?.accessToken;
  String? get _myUid => ref.read(authControllerProvider).session?.firebaseUid;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _load();
      _loadEventTitles();
      _loadFinance();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    final token = _token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(adminApiProvider).searchUsers(
            accessToken: token,
            query: _search.text,
            page: page,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error('Roles: user search failed', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(error, action: 'load people');
      });
    }
  }

  /// Best effort: without titles the list shows "Event #id".
  Future<void> _loadEventTitles() async {
    final token = _token;
    if (token == null) return;
    try {
      final data = await ref.read(eventsRepositoryProvider).getAdminEvents(
            page: 1,
            perPage: 100,
            period: 'all',
            accessToken: token,
          );
      final titles = <int, String>{};
      for (final raw in data['events'] as List<dynamic>? ?? const []) {
        if (raw is Map) {
          final id = raw['event_id'];
          if (id is int) titles[id] = raw['title']?.toString() ?? 'Event #$id';
        }
      }
      if (mounted) setState(() => _eventTitles = titles);
    } catch (error) {
      AppLogger.warning('Roles: event titles not loaded: $error');
    }
  }

  Future<void> _loadFinance() async {
    final token = _token;
    if (token == null) return;
    try {
      final grants = await ref.read(adminApiProvider).listPaymentRoles(accessToken: token);
      if (!mounted) return;
      setState(() => _finance = {
            for (final g in grants)
              if (g.role == 'finance_operator') g.firebaseUid: g,
          });
    } catch (error) {
      AppLogger.warning('Roles: payment roles not loaded: $error');
    }
  }

  Future<void> _changeFinance(AdminUser user, bool on) async {
    final name = user.fullname.isNotEmpty ? user.fullname : user.email;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(on ? 'Give $name the Finance role?' : 'Remove Finance from $name?'),
        content: Text(
          on
              ? 'They will see every event\'s payments and refunds in the Payments tab. '
                  'They can\'t edit events or roles.'
              : 'They will no longer see payments, unless they admin an event.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = _token;
    if (token == null) return;
    setState(() => _saving.add(user.firebaseUid));
    try {
      final api = ref.read(adminApiProvider);
      if (on) {
        final grant = await api.grantPaymentRole(
          accessToken: token,
          firebaseUid: user.firebaseUid,
          role: 'finance_operator',
        );
        if (mounted) setState(() => _finance = {..._finance, user.firebaseUid: grant});
      } else {
        final grant = _finance[user.firebaseUid];
        if (grant != null) {
          await api.revokePaymentRole(accessToken: token, grantId: grant.id);
        }
        if (mounted) setState(() => _finance = {..._finance}..remove(user.firebaseUid));
      }
      _snack('Roles updated for $name.');
    } catch (error, stackTrace) {
      AppLogger.error('Roles: finance change failed', error, stackTrace);
      if (mounted) _snack(apiErrorMessage(error, action: 'update roles'), isError: true);
    } finally {
      if (mounted) setState(() => _saving.remove(user.firebaseUid));
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load());
  }

  Future<void> _change(
    AdminUser user, {
    bool? isAdmin,
    bool? isEventCreator,
  }) async {
    final name = user.fullname.isNotEmpty ? user.fullname : user.email;
    final (title, body) = switch ((isAdmin, isEventCreator)) {
      (true, _) => (
          'Make $name an overall admin?',
          'They will see and manage every event, registration, payment and '
              'role, including this tab.',
        ),
      (false, _) => (
          'Remove overall admin from $name?',
          'They keep admin of any events they run and can still create events '
              'if that is switched on.',
        ),
      (_, true) => (
          'Let $name create events?',
          'They will get the Admin badge and become admin of each event they '
              'create.',
        ),
      _ => (
          'Stop $name creating events?',
          'Events they already run stay theirs.',
        ),
    };

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final token = _token;
    if (token == null) return;
    setState(() => _saving.add(user.firebaseUid));
    try {
      final updated = await ref.read(adminApiProvider).updateUserRoles(
            accessToken: token,
            firebaseUid: user.firebaseUid,
            isAdmin: isAdmin,
            isEventCreator: isEventCreator,
          );
      if (!mounted) return;
      setState(() {
        final current = _result;
        if (current != null) {
          _result = AdminUserPage(
            users: [
              for (final u in current.users)
                u.firebaseUid == updated.firebaseUid ? updated : u,
            ],
            total: current.total,
            page: current.page,
            perPage: current.perPage,
          );
        }
      });
      _snack('Roles updated for $name.');
      if (user.firebaseUid == _myUid) {
        await ref.read(authControllerProvider.notifier).refreshSession();
      }
    } catch (error, stackTrace) {
      AppLogger.error('Roles: update failed', error, stackTrace);
      if (mounted) {
        _snack(apiErrorMessage(error, action: 'update roles'), isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving.remove(user.firebaseUid));
    }
  }

  void _snack(String message, {bool isError = false}) {
    showNotice(context, message, kind: isError ? NoticeKind.error : NoticeKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final result = _result;

    // Same frame as the other admin tabs (search on top, list below).
    return ListPage(
      search: ListSearchField(
        controller: _search,
        hint: 'Search people by name or email',
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _load(),
      ),
      body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null && result == null
              ? StateMessage(
                  body: _error!,
                  action: TextButton(onPressed: _load, child: const Text('Try again')),
                )
              : result == null
              ? const SizedBox.shrink()
              : result.users.isEmpty
              ? const StateMessage(body: 'No one matches that search.')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    return ListView.separated(
                      padding: ListPage.contentPadding(
                        context,
                        constraints.maxWidth,
                        top: 16,
                      ),
                      itemCount: result.users.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i == result.users.length) {
                          return _Pager(
                            result: result,
                            onPage: _loading ? null : (page) => _load(page: page),
                          );
                        }
                        final user = result.users[i];
                        return _UserCard(
                          user: user,
                          wide: wide,
                          isMe: user.firebaseUid == _myUid,
                          saving: _saving.contains(user.firebaseUid),
                          eventTitles: _eventTitles,
                          finance: _finance.containsKey(user.firebaseUid),
                          onAdmin: (v) => _change(user, isAdmin: v),
                          onCreator: (v) => _change(user, isEventCreator: v),
                          onFinance: (v) => _changeFinance(user, v),
                        );
                      },
                    );
                  },
                ),
        ),
        if (_error != null && result != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_error!, style: TextStyle(color: p.error)),
          ),
      ],
      ),
    );
  }
}

class _UserCard extends StatefulWidget {
  const _UserCard({
    required this.user,
    required this.wide,
    required this.isMe,
    required this.saving,
    required this.eventTitles,
    required this.finance,
    required this.onAdmin,
    required this.onCreator,
    required this.onFinance,
  });

  final AdminUser user;
  final bool wide;
  final bool isMe;
  final bool saving;
  final Map<int, String> eventTitles;
  final bool finance;
  final ValueChanged<bool> onAdmin;
  final ValueChanged<bool> onCreator;
  final ValueChanged<bool> onFinance;

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  bool _showEvents = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final user = widget.user;
    final overall = user.isAdmin || user.isEmergencyAdmin;

    // Your own Overall admin switch is locked (no self-demotion); the
    // emergency list is a server setting.
    final adminLocked = widget.saving || widget.isMe || user.isEmergencyAdmin;
    final adminNote = user.isEmergencyAdmin
        ? 'Set in server settings'
        : widget.isMe
        ? "You can't remove your own"
        : null;
    // Overall admins can always create events.
    final creatorLocked = widget.saving || overall;
    final creatorNote = overall ? 'Included with overall admin' : null;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                user.fullname.isNotEmpty ? user.fullname : user.email,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary),
              ),
            ),
            const SizedBox(width: 8),
            _TypeChip(type: user.userType),
            if (widget.isMe) ...[
              const SizedBox(width: 6),
              const _TypeChip(type: 'you'),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          user.email,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
        ),
      ],
    );

    final adminSwitch = _LabelledSwitch(
      label: 'Overall admin',
      value: overall,
      note: adminNote,
      onChanged: adminLocked ? null : widget.onAdmin,
    );
    final creatorSwitch = _LabelledSwitch(
      label: 'Can create events',
      value: user.isEventCreator || overall,
      note: creatorNote,
      onChanged: creatorLocked ? null : widget.onCreator,
    );
    final financeSwitch = _LabelledSwitch(
      label: 'Finance',
      value: widget.finance || overall,
      note: overall ? 'Included with overall admin' : 'Sees all payments',
      onChanged: widget.saving || overall ? null : widget.onFinance,
    );
    final events = _EventsLink(
      count: user.adminEventIds.length,
      open: _showEvents,
      onTap: user.adminEventIds.isEmpty
          ? null
          : () => setState(() => _showEvents = !_showEvents),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.wide)
            Row(
              children: [
                Expanded(flex: 4, child: identity),
                Expanded(flex: 3, child: adminSwitch),
                Expanded(flex: 3, child: creatorSwitch),
                Expanded(flex: 3, child: financeSwitch),
                Expanded(flex: 2, child: events),
              ],
            )
          else ...[
            identity,
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [adminSwitch, creatorSwitch, financeSwitch, events],
            ),
          ],
          if (_showEvents && user.adminEventIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: p.border),
            const SizedBox(height: 8),
            for (final id in user.adminEventIds)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  widget.eventTitles[id] ?? 'Event #$id',
                  style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LabelledSwitch extends StatelessWidget {
  const _LabelledSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
    this.note,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SiteToggle(value: value, onChanged: onChanged),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 13.5,
                  color: p.textSecondary,
                ),
              ),
              if (note != null)
                Text(
                  note!,
                  style: AppTextStyles.labelSmall.copyWith(color: p.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventsLink extends StatelessWidget {
  const _EventsLink({required this.count, required this.open, this.onTap});

  final int count;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = count == 0
        ? 'Admin of no events'
        : 'Admin of $count event${count == 1 ? '' : 's'}';
    if (onTap == null) {
      return Text(text, style: AppTextStyles.bodySmall.copyWith(color: p.textMuted));
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: AppTextStyles.bodySmall.copyWith(color: p.primary)),
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: p.primary),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = switch (type.toLowerCase()) {
      'alumni' => 'Alumni',
      'admin' => 'Admin account',
      'you' => 'You',
      _ => 'Guest',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: p.surfaceSubtle,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(color: p.textSecondary),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.result, required this.onPage});

  final AdminUserPage result;
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final page = result.page;
    final pages = result.pages;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text(
            '${result.total} ${result.total == 1 ? 'person' : 'people'}'
            '${pages > 1 ? ' · page $page of $pages' : ''}',
            style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
          ),
          const Spacer(),
          if (pages > 1) ...[
            TextButton(
              onPressed: page > 1 && onPage != null ? () => onPage!(page - 1) : null,
              child: const Text('Previous'),
            ),
            TextButton(
              onPressed: page < pages && onPage != null ? () => onPage!(page + 1) : null,
              child: const Text('Next'),
            ),
          ],
        ],
      ),
    );
  }
}
