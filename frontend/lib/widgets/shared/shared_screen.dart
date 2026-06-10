import 'package:flutter/material.dart';
import '../material/app_scaffold.dart';

/// A simple wrapper that provides a consistent scaffold using
/// [AppScaffold] while allowing an optional [appBar] and required [body].
class SharedScreen extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;

  const SharedScreen({
    Key? key,
    this.appBar,
    required this.body,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => AppScaffold(
        appBar: appBar,
        body: body,
      );
}
