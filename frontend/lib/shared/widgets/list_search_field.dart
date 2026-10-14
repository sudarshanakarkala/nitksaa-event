import 'package:flutter/material.dart';

/// The search box at the top of a list page (`ListPage.search`): 44px high,
/// search icon, the theme's input look.
class ListSearchField extends StatelessWidget {
  const ListSearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  /// Set when Enter runs the search (the search key on phones).
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: onSubmitted == null ? null : TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
