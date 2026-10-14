import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';
import '../../domain/event.dart';

/// The events the signed-in person administers (all of them for an overall
/// admin), any status, fetched once and shared: the "mine" tint below and
/// the Events page's drafts count both come from it.
///
/// Only people with admin rights can read the admin events list. Everyone
/// else gets an empty list without a request. Failures also give an empty
/// list: the tint and the count are niceties, never worth an error.
final myAdminEventsProvider = FutureProvider<List<AppEvent>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  final session = auth.session;
  if (!auth.isAuthenticated || session == null || !session.access.isAnyAdmin) {
    return const <AppEvent>[];
  }
  try {
    return await ref
        .read(eventsRepositoryProvider)
        .getAllAdminEvents(session.accessToken);
  } catch (_) {
    return const <AppEvent>[];
  }
});

/// IDs of the events the signed-in person created, for the "mine" tint on
/// public pages (the public API doesn't say who created an event).
final createdEventIdsProvider = FutureProvider<Set<int>>((ref) async {
  final uid = ref.watch(authControllerProvider).session?.firebaseUid;
  final events = await ref.watch(myAdminEventsProvider.future);
  if (uid == null) return const <int>{};
  return {
    for (final e in events)
      if (e.createdByUid == uid) e.eventId,
  };
});
