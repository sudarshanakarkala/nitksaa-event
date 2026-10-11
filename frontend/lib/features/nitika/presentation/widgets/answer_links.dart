import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/app_shell.dart';
import '../../../../theme/app_palette.dart';
import '../../domain/nitika_models.dart';

/// App routes NITiKa may link to (plan §5). Anything else is dropped, even
/// though the service already sends only these.
final _allowedRoutes = [
  RegExp(r'^/home$'),
  RegExp(r'^/my-events$'),
  RegExp(r'^/refund$'),
  RegExp(r'^/feedback$'),
  RegExp(r'^/events/\d+$'),
  RegExp(r'^/admin/events/\d+/registrations$'),
];

bool isAllowedNitikaPath(String path) =>
    _allowedRoutes.any((r) => r.hasMatch(path));

/// Link chips under an answer. Tapping one opens the screen; below the rail
/// width the panel is a dialog or sheet, so it closes first.
class AnswerLinks extends StatelessWidget {
  const AnswerLinks(this.links, {super.key});

  final List<NitikaLink> links;

  @override
  Widget build(BuildContext context) {
    final allowed = [
      for (final l in links)
        if (isAllowedNitikaPath(l.path)) l,
    ];
    if (allowed.isEmpty) return const SizedBox.shrink();
    final p = context.palette;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final link in allowed)
          ActionChip(
            avatar: Icon(Icons.arrow_forward, size: 14, color: p.primary),
            label: Text(link.label),
            tooltip: 'Open ${link.label}',
            backgroundColor: p.surface,
            side: BorderSide(color: p.border),
            labelStyle: TextStyle(color: p.textPrimary, fontSize: 13),
            visualDensity: VisualDensity.compact,
            onPressed: () => openNitikaPath(context, link.path),
          ),
      ],
    );
  }
}

/// Opens an allowed app route, closing the panel first when it is a dialog
/// or sheet.
void openNitikaPath(BuildContext context, String path) {
  if (!isAllowedNitikaPath(path)) return;
  final router = GoRouter.of(context);
  if (MediaQuery.sizeOf(context).width < AppShell.assistantRailFrom) {
    Navigator.of(context).maybePop();
  }
  router.go(path);
}
