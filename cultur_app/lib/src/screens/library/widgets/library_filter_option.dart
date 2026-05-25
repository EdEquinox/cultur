import 'package:flutter/material.dart';

/// One filter the user can open from the library filter picker sheet.
class LibraryFilterOption {
  const LibraryFilterOption({
    required this.id,
    required this.label,
    required this.isActive,
    required this.onPick,
  });

  final String id;
  final String label;
  final bool isActive;
  final Future<void> Function(BuildContext context) onPick;
}

int libraryActiveFilterCount(Iterable<LibraryFilterOption> options) {
  return options.where((o) => o.isActive).length;
}
