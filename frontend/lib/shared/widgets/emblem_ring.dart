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
        // Gold emblem on dark, navy on light.
        child: Image.asset(
          Theme.of(context).brightness == Brightness.dark
              ? 'assets/images/nitksaa-emblem-gold.png'
              : 'assets/images/nitksaa-emblem-navy.png',
        ),
      ),
    );
  }
}
