import 'package:flutter/material.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/utils/collection_filters.dart';

List<LibraryFilterOption> buildCrewDepartmentFilterOptions({
  required List<String> departments,
  required String? selectedDepartment,
  required ValueChanged<String?> onDepartmentChanged,
}) {
  if (departments.isEmpty) {
    return const [];
  }

  final labels = {for (final d in departments) d: d};

  return [
    LibraryFilterOption(
      id: 'department',
      label: selectedDepartment ?? 'Department',
      isActive: selectedDepartment != null,
      onPick: (ctx) => showMultiSelectKeySheet(
        ctx,
        title: 'Department',
        keyLabels: labels,
        selected: selectedDepartment == null ? <String>{} : {selectedDepartment},
        onApply: (next) {
          onDepartmentChanged(next.isEmpty ? null : next.first);
        },
      ),
    ),
  ];
}
