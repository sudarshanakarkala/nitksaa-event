import 'package:flutter/material.dart';

import '../../theme/app_palette.dart';

/// Association emblem inside a thin gold ring.
class EmblemRing extends StatelessWidget {
  const EmblemRing({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.14),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.primary.withValues(alpha: 0.08),
          border: Border.all(color: p.primary.withValues(alpha: 0.6), width: 1.5),
        ),
        // Drawn white in dark mode, like the header logo.
        child: Theme.of(context).brightness == Brightness.dark
            ? ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.white.withValues(alpha: 0.9),
                  BlendMode.srcIn,
                ),
                child: Image.asset('assets/images/nitksaa-emblem.png'),
              )
            : Image.asset('assets/images/nitksaa-emblem.png'),
      ),
    );
  }
}
