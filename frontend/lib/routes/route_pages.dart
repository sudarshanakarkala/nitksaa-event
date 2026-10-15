import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/widgets/state_message.dart';
import 'app_routes.dart';

/// An address the app has no page for (the router's error page).
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StateMessage(
        icon: Icons.explore_off_outlined,
        title: 'Page not found',
        body: 'There\'s no page at this address. The link may be old or '
            'mistyped.',
        action: FilledButton(
          onPressed: () => context.go(AppRoutes.home),
          child: const Text('Go to Events'),
        ),
      ),
    );
  }
}

/// `/admin…` for someone signed in without an admin role.
class NotAdminPage extends StatelessWidget {
  const NotAdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StateMessage(
      icon: Icons.lock_outline,
      title: 'Not an admin',
      body: 'This account doesn\'t have access to Admin. If you should have '
          'it, ask an NITKSAA admin to add you.',
      action: FilledButton(
        onPressed: () => context.go(AppRoutes.home),
        child: const Text('Go to Events'),
      ),
    );
  }
}
