import 'package:flutter/material.dart';
import 'package:yamtrack/src/app/theme.dart';

/// Compact multi-select filter sheet (genres, format, show status, etc.).
Future<void> showLibraryMultiSelectFilterSheet(
  BuildContext context, {
  required String title,
  required Map<String, String> keyLabels,
  required Set<String> selected,
  required void Function(Set<String> next) onApply,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: scheme.surfaceContainerLow,
    builder: (sheetContext) => _LibraryMultiSelectFilterSheet(
      title: title,
      keyLabels: keyLabels,
      selected: selected,
      onApply: onApply,
      theme: theme,
      scheme: scheme,
      tokens: sheetContext.culturTokens,
    ),
  );
}

class _LibraryMultiSelectFilterSheet extends StatefulWidget {
  const _LibraryMultiSelectFilterSheet({
    required this.title,
    required this.keyLabels,
    required this.selected,
    required this.onApply,
    required this.theme,
    required this.scheme,
    required this.tokens,
  });

  final String title;
  final Map<String, String> keyLabels;
  final Set<String> selected;
  final void Function(Set<String> next) onApply;
  final ThemeData theme;
  final ColorScheme scheme;
  final CulturTokens tokens;

  @override
  State<_LibraryMultiSelectFilterSheet> createState() => _LibraryMultiSelectFilterSheetState();
}

class _LibraryMultiSelectFilterSheetState extends State<_LibraryMultiSelectFilterSheet> {
  late final Set<String> _working;
  late final List<MapEntry<String, String>> _sortedEntries;
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _working = {...widget.selected};
    _sortedEntries = widget.keyLabels.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyNow() => widget.onApply(Set<String>.from(_working));

  void _toggleKey(String key, {required bool checked}) {
    setState(() {
      if (checked) {
        _working.remove(key);
      } else {
        _working.add(key);
      }
    });
    _applyNow();
  }

  List<MapEntry<String, String>> get _visibleEntries {
    if (_query.isEmpty) {
      return _sortedEntries;
    }
    return _sortedEntries.where((e) => e.value.toLowerCase().contains(_query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;
    final sheetHeight = maxHeight.clamp(280.0, maxHeight);
    final entries = _visibleEntries;
    final theme = widget.theme;
    final scheme = widget.scheme;
    final tokens = widget.tokens;

    return Padding(
      padding: EdgeInsets.only(bottom: viewPadding.bottom),
      child: SizedBox(
        height: sheetHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _working.clear());
                      _applyNow();
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.2),
                onChanged: (value) {
                  setState(() => _query = value.trim().toLowerCase());
                },
                decoration: InputDecoration(
                  hintText: 'Search ${widget.title}…',
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(Icons.clear, size: 18, color: scheme.onSurfaceVariant),
                        ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: scheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  entries.isEmpty
                      ? 'No matches'
                      : '${entries.length} match${entries.length == 1 ? '' : 'es'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _query.isEmpty ? 'Nothing to show' : 'No results for "$_query"',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final checked = _working.contains(entry.key);
                        return Material(
                          color: checked
                              ? scheme.primaryContainer.withValues(alpha: 0.45)
                              : scheme.surfaceContainerHigh,
                          borderRadius: tokens.borderRadiusTight,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _toggleKey(entry.key, checked: checked),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontSize: 13,
                                        height: 1.2,
                                        fontWeight: checked ? FontWeight.w600 : FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: Checkbox(
                                      value: checked,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        _toggleKey(entry.key, checked: !value);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
