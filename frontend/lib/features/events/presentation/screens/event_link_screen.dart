import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../routes/app_routes.dart';
import '../../../../shared/widgets/state_message.dart';
import '../../data/events_repository.dart';

/// `/e/<slug>`: finds the published event and opens its page (replacing
/// this address, so Back doesn't come here again). Unknown, draft or
/// mistyped links say so.
class EventLinkScreen extends ConsumerStatefulWidget {
  const EventLinkScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<EventLinkScreen> createState() => _EventLinkScreenState();
}

class _EventLinkScreenState extends ConsumerState<EventLinkScreen> {
  bool _notFound = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _find();
  }

  void _retry() {
    setState(() => _failed = false);
    _find();
  }

  Future<void> _find() async {
    try {
      final id = await ref
          .read(eventsRepositoryProvider)
          .findPublicEventIdBySlug(widget.slug.toLowerCase());
      if (!mounted) return;
      if (id == null) {
        setState(() => _notFound = true);
      } else {
        context.go('/events/$id');
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_notFound) {
      return StateMessage(
        icon: Icons.event_busy_outlined,
        title: 'This event isn\'t available',
        body: 'The link may be mistyped, or the event isn\'t open to the '
            'public yet.',
        action: FilledButton(
          onPressed: () => context.go(AppRoutes.home),
          child: const Text('Go to Events'),
        ),
      );
    }
    if (_failed) {
      return StateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Couldn\'t open this event',
        body: 'Check your connection and try again.',
        action: FilledButton(onPressed: _retry, child: const Text('Try again')),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}
