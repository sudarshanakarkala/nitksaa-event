import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/services/auth_controller.dart';
import '../../data/events_repository.dart';

/// IDs of the events the signed-in person created, for the "mine" tint on
/// public pages (the public API doesn't say who created an event).
///
/// Only people with admin rights can create events, and only they can read
/// the admin events list, which does carry the creator. Everyone else gets
/// an empty set without a request. Failures also give an empty set: the
/// tint is a nicety, never worth an error.
final createdEventIdsProvider = FutureProvider<Set<int>>((ref) async {
  final auth = ref.watch(authControllerProvider);
  final session = auth.session;
  if (!auth.isAuthenticated || session == null || !session.access.isAnyAdmin) {
    return const <int>{};
  }
  try {
    final data = await ref.read(eventsRepositoryProvider).getAdminEvents(
          page: 1,
          perPage: 100,
          period: 'all',
          accessToken: session.accessToken,
        );
    final ids = <int>{};
    for (final raw in data['events'] as List<dynamic>? ?? const []) {
      if (raw is Map &&
          raw['created_by_firebase_uid'] == session.firebaseUid &&
          raw['event_id'] is int) {
        ids.add(raw['event_id'] as int);
      }
    }
    return ids;
  } catch (_) {
    return const <int>{};
  }
});
