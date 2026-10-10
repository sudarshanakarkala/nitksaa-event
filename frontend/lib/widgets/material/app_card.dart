import 'package:flutter/material.dart';
import 'package:event_app/theme/app_palette.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  const AppCard({Key? key, required this.child, this.padding, this.margin}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: margin ?? const EdgeInsets.all(8.0),
      padding: padding ?? const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: p.border),
      ),
      child: child,
    );
  }
}
