import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../theme/app_palette.dart';
import '../../../theme/app_text_styles.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/domain/event.dart';
import '../data/admin_api.dart';

/// Lists an event's admins, adds one by email, removes one. Open to overall
/// admins and to the event's own admins (co-organisers).
Future<void> showEventAdminsDialog(BuildContext context, {required AppEvent event}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EventAdminsDialog(event: event),
  );
}

class _EventAdminsDialog extends ConsumerStatefulWidget {
  const _EventAdminsDialog({required this.event});

  final AppEvent event;

  @override
  ConsumerState<_EventAdminsDialog> createState() => _EventAdminsDialogState();
}

class _EventAdminsDialogState extends ConsumerState<_EventAdminsDialog> {
  final _email = TextEditingController();
  List<EventAdmin>? _admins;
  String? _error;
  bool _adding = false;
  final Set<String> _removing = {};

  String? get _token => ref.read(authControllerProvider).session?.accessToken;
  String? get _myUid => ref.read(authControllerProvider).session?.firebaseUid;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) return;
    try {
      final admins = await ref
          .read(adminApiProvider)
          .listEventAdmins(accessToken: token, eventId: widget.event.eventId);
      if (mounted) setState(() => _admins = admins);
    } catch (error, stackTrace) {
      AppLogger.error('Event admins: load failed', error, stackTrace);
      if (mounted) setState(() => _error = apiErrorMessage(error, action: 'load the admins'));
    }
  }

  Future<void> _add() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter the email address they sign in with.');
      return;
    }
    final token = _token;
    if (token == null) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await ref.read(adminApiProvider).grantEventAdmin(
            accessToken: token,
            eventId: widget.event.eventId,
            email: email,
          );
      _email.clear();
      await _load();
    } on DioException catch (error) {
      final detail = error.response?.data is Map ? (error.response!.data as Map)['detail'] : null;
      setState(() => _error = switch (detail) {
            'user_not_found' =>
              'No one with that email has signed in to the events app yet. '
                  'Ask them to sign in once, then add them.',
            'already_event_admin' => 'They\'re already an admin of this event.',
            _ => apiErrorMessage(error, action: 'add the admin'),
          });
    } catch (error) {
      setState(() => _error = apiErrorMessage(error, action: 'add the admin'));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(EventAdmin admin) async {
    final isMe = admin.firebaseUid == _myUid;
    final name = admin.fullname ?? admin.email ?? 'this person';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isMe ? 'Remove yourself?' : 'Remove $name?'),
        content: Text(
          isMe
              ? 'You\'ll no longer manage this event (unless you\'re an overall admin).'
              : '$name will no longer manage this event.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    final token = _token;
    if (token == null) return;
    setState(() => _removing.add(admin.firebaseUid));
    try {
      await ref.read(adminApiProvider).revokeEventAdmin(
            accessToken: token,
            eventId: widget.event.eventId,
            firebaseUid: admin.firebaseUid,
          );
      if (isMe && mounted) {
        Navigator.pop(context);
        return;
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error, action: 'remove the admin'));
    } finally {
      if (mounted) setState(() => _removing.remove(admin.firebaseUid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final admins = _admins;
    return AlertDialog(
      title: Text('Admins of "${widget.event.title}"'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Admins can edit the event, see its registrations and payments, '
              'and add or remove other admins.',
              style: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 12),
            if (admins == null && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (admins != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: admins.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No event admins. Overall admins can still manage it.',
                          style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: admins.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
                        itemBuilder: (context, i) {
                          final a = admins[i];
                          final isMe = a.firebaseUid == _myUid;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              [a.fullname ?? a.email ?? a.firebaseUid, if (isMe) '(you)'].join(' '),
                              style: AppTextStyles.titleSmall.copyWith(color: p.textPrimary),
                            ),
                            subtitle: Text(
                              [if (a.email != null) a.email!, if (a.isCreator) 'Created the event']
                                  .join(' · '),
                              style: AppTextStyles.bodySmall.copyWith(color: p.textMuted),
                            ),
                            trailing: _removing.contains(a.firebaseUid)
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : IconButton(
                                    tooltip: 'Remove',
                                    icon: Icon(Icons.person_remove_outlined, color: p.error),
                                    onPressed: () => _remove(a),
                                  ),
                          );
                        },
                      ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      labelText: 'Add an admin by email',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _adding ? null : _add,
                  child: Text(_adding ? 'Adding…' : 'Add'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTextStyles.bodySmall.copyWith(color: p.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
