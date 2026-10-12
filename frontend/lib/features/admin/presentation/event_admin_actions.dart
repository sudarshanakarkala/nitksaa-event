import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/api_error_message.dart';
import '../../../core/logger/app_logger.dart';
import '../../../theme/app_palette.dart';
import '../../auth/services/auth_controller.dart';
import '../../events/data/events_repository.dart';
import '../../events/domain/event.dart';
import '../../events/presentation/providers/created_events_provider.dart';
import '../../events/presentation/providers/events_provider.dart';
import '../../events/presentation/screens/manage_events_screen.dart' show showEventFormDialog;
import '../../events/presentation/widgets/event_card.dart' show EventCardAction;
import 'event_admins_dialog.dart';

/// Refreshes after any admin change to events: the public Events list,
/// "created by me", and the admin events list behind the drafts link.
void refreshEventLists(WidgetRef ref) {
  ref.read(eventsProvider.notifier).fetchEvents(isRefresh: true);
  ref.invalidate(createdEventIdsProvider);
  ref.invalidate(myDraftCountProvider);
}

/// How many drafts the signed-in person can work on (their events; all of
/// them for an overall admin), for the "N drafts" link on the Events page.
final myDraftCountProvider = FutureProvider<int>((ref) async {
  final session = ref.watch(authControllerProvider).session;
  if (session == null || !session.access.isAnyAdmin) return 0;
  try {
    final events = await ref.read(eventsRepositoryProvider).getAllAdminEvents(session.accessToken);
    return events.where((e) => e.status == 'draft').length;
  } catch (_) {
    return 0;
  }
});

/// The actions an event's admins can take on it, wherever the event is
/// shown: Admin → Events and, in place, the Events page (website pattern:
/// admins act where they are). One copy, so confirmations and messages are
/// the same in both places.
class EventAdminActions {
  EventAdminActions({
    required this.context,
    required this.ref,
    required this.onChanged,
    required this.isBusy,
    required this.setBusy,
  });

  final BuildContext context;
  final WidgetRef ref;

  /// Called after a change, to reload whatever the caller shows.
  final Future<void> Function() onChanged;
  final bool Function(int eventId) isBusy;
  final void Function(int eventId, bool busy) setBusy;

  String? get _token => ref.read(authControllerProvider).session?.accessToken;

  static bool ended(AppEvent e) =>
      (e.endDatetime ?? e.startDatetime).isBefore(DateTime.now());

  Future<void> _afterChange() async {
    await onChanged();
    if (!context.mounted) return;
    refreshEventLists(ref);
  }

  Future<void> create() async {
    if (await showEventFormDialog(context)) await _afterChange();
  }

  /// Opens the form on the full event. Lists and the public page carry the
  /// public version, which leaves out fields such as the meeting link;
  /// editing that would save them as empty.
  Future<void> edit(AppEvent e) async {
    final token = _token;
    if (token == null) return;
    final AppEvent full;
    try {
      full = await ref.read(eventsRepositoryProvider).getAdminEvent(e.eventId, token);
    } catch (error, stackTrace) {
      AppLogger.error('Event admin: open for editing failed', error, stackTrace);
      _snack(_friendly(error, 'open the event'), isError: true);
      return;
    }
    if (!context.mounted) return;
    if (await showEventFormDialog(context, event: full)) await _afterChange();
  }

  Future<bool> _confirm(
    String title,
    String body, {
    String confirm = 'Confirm',
    bool destructive = false,
  }) async {
    final p = context.palette;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: p.error, foregroundColor: p.onPrimary)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Runs [action] for [e] with the event marked busy, then refreshes.
  Future<void> _run(
    AppEvent e,
    String what,
    Future<void> Function(String token) action, {
    required String done,
  }) async {
    final token = _token;
    if (token == null) return;
    setBusy(e.eventId, true);
    try {
      await action(token);
      _snack(done);
      await _afterChange();
    } catch (error, stackTrace) {
      AppLogger.error('Event admin: $what failed', error, stackTrace);
      _snack(_friendly(error, what), isError: true);
    } finally {
      if (context.mounted) setBusy(e.eventId, false);
    }
  }

  /// Plain messages for the refusals people will actually meet.
  String _friendly(Object error, String what) {
    if (error is DioException) {
      final detail = error.response?.data is Map ? (error.response!.data as Map)['detail'] : null;
      switch (detail) {
        case 'event_not_draft':
          return 'Only drafts can be deleted. Cancel the event instead.';
        case 'event_has_registrations':
          return 'This event has registrations, so it can\'t be deleted. Cancel it instead.';
        case 'event_admin_required':
          return 'You\'re not an admin of this event.';
      }
    }
    return apiErrorMessage(error, action: what);
  }

  void _snack(String message, {bool isError = false}) {
    if (!context.mounted) return;
    final p = context.palette;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: p.textPrimary)),
          backgroundColor: p.tinted(isError ? p.error : p.success),
          duration: Duration(seconds: isError ? 7 : 3),
        ),
      );
  }

  Future<void> publish(AppEvent e) => _run(
        e,
        'publish the event',
        (t) => ref.read(eventsRepositoryProvider).updateEventStatus(e.eventId, 'published', t),
        done: '"${e.title}" is published.',
      );

  Future<void> unpublish(AppEvent e) async {
    final hasRegs = e.registeredCount > 0;
    if (!await _confirm(
      'Unpublish "${e.title}"?',
      hasRegs
          ? 'It goes back to draft and disappears from the Events page. '
              'Its ${e.registeredCount} registrations are kept.'
          : 'It goes back to draft and disappears from the Events page.',
      confirm: 'Unpublish',
    )) {
      return;
    }
    await _run(
      e,
      'unpublish the event',
      (t) => ref.read(eventsRepositoryProvider).updateEventStatus(e.eventId, 'draft', t),
      done: '"${e.title}" is back in draft.',
    );
  }

  /// Sets the closing time to now. Reversible: Reopen clears it.
  Future<void> closeRegistration(AppEvent e) async {
    if (!await _confirm(
      'Close registration for "${e.title}"?',
      'No one else can register. You can reopen registration later.',
      confirm: 'Close registration',
    )) {
      return;
    }
    await _run(
      e,
      'close registration',
      (t) => ref.read(eventsRepositoryProvider).updateAdminEvent(
            e.eventId,
            {'registration_closes_at': DateTime.now().toUtc().toIso8601String()},
            t,
          ),
      done: 'Registration is closed for "${e.title}".',
    );
  }

  Future<void> reopenRegistration(AppEvent e) => _run(
        e,
        'reopen registration',
        (t) => ref.read(eventsRepositoryProvider).updateAdminEvent(
              e.eventId,
              {'registration_closes_at': null},
              t,
            ),
        done: 'Registration is open again for "${e.title}".',
      );

  Future<void> cancel(AppEvent e) async {
    if (!await _confirm(
      'Cancel "${e.title}"?',
      'The event is marked cancelled for everyone and can\'t be reopened. '
          '${e.registeredCount > 0 ? 'Its ${e.registeredCount} registrations are kept; refunds aren\'t sent automatically. ' : ''}'
          'To remove a draft entirely, delete it instead.',
      confirm: 'Cancel event',
      destructive: true,
    )) {
      return;
    }
    await _run(
      e,
      'cancel the event',
      (t) => ref.read(eventsRepositoryProvider).updateEventStatus(e.eventId, 'cancelled', t),
      done: '"${e.title}" is cancelled.',
    );
  }

  Future<void> delete(AppEvent e) async {
    if (!await _confirm(
      'Delete "${e.title}"?',
      'The draft and everything in it (sessions, sponsors, partners) are '
          'removed for good.',
      confirm: 'Delete',
      destructive: true,
    )) {
      return;
    }
    await _run(
      e,
      'delete the event',
      (t) => ref.read(eventsRepositoryProvider).deleteAdminEvent(e.eventId, t),
      done: '"${e.title}" is deleted.',
    );
  }

  Future<void> admins(AppEvent e) async {
    await showEventAdminsDialog(context, event: e);
    // Your own rights may have changed (e.g. you removed yourself).
    await ref.read(authControllerProvider.notifier).refreshSession();
    if (context.mounted) await _afterChange();
  }

  /// What can be done to [e], by status (design step 5). Empty while an
  /// action on it is running.
  List<EventCardAction> actionsFor(AppEvent e) {
    if (isBusy(e.eventId)) return const [];
    final draft = e.status == 'draft';
    final published = e.status == 'published';
    final live = draft || published;
    final isOver = ended(e);
    return [
      if (live)
        EventCardAction(label: 'Edit', icon: Icons.edit_outlined, onSelected: () => edit(e)),
      if (!draft || e.registeredCount > 0)
        EventCardAction(
          label: 'Registrations',
          icon: Icons.people_outline,
          onSelected: () => context.go('/admin/registrations?event=${e.eventId}'),
        ),
      if (draft)
        EventCardAction(label: 'Publish', icon: Icons.publish_outlined, onSelected: () => publish(e)),
      if (published && !isOver && e.registrationStatus != 'closed')
        EventCardAction(
          label: 'Close registration',
          icon: Icons.lock_outline,
          onSelected: () => closeRegistration(e),
        ),
      if (published && !isOver && e.registrationStatus == 'closed')
        EventCardAction(
          label: 'Reopen registration',
          icon: Icons.lock_open_outlined,
          onSelected: () => reopenRegistration(e),
        ),
      if (published)
        EventCardAction(
          label: 'Unpublish',
          icon: Icons.unpublished_outlined,
          onSelected: () => unpublish(e),
        ),
      EventCardAction(
        label: 'Admins',
        icon: Icons.admin_panel_settings_outlined,
        onSelected: () => admins(e),
      ),
      if (live)
        EventCardAction(
          label: 'Cancel event',
          icon: Icons.event_busy_outlined,
          destructive: true,
          onSelected: () => cancel(e),
        ),
      if (draft)
        EventCardAction(
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
          onSelected: () => delete(e),
        ),
    ];
  }
}
