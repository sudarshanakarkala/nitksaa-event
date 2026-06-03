import 'package:flutter/material.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.centerBody = false,
    this.scrollable = false,
    this.padding = const EdgeInsets.all(24),
    this.maxContentWidth,
    this.safeArea = true,
    this.automaticallyImplyLeading = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final bool centerBody;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final double? maxContentWidth;
  final bool safeArea;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(
      padding: padding,
      child: maxContentWidth == null
          ? body
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth!),
                child: body,
              ),
            ),
    );

    if (scrollable) {
      content = SingleChildScrollView(child: content);
    }

    if (centerBody) {
      content = Center(child: content);
    }

    if (safeArea) {
      content = SafeArea(child: content);
    }

    return Scaffold(
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              automaticallyImplyLeading: automaticallyImplyLeading,
              actions: actions,
            ),
      body: content,
    );
  }
}
