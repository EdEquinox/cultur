import 'package:flutter/material.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_menu.dart';
import 'package:yamtrack/src/screens/library/widgets/library_filter_option.dart';
import 'package:yamtrack/src/screens/library/widgets/library_item_search_field.dart';

/// Search field with a filter button that opens a dropdown to pick a filter.
class LibrarySearchFilterHeader extends StatefulWidget {
  const LibrarySearchFilterHeader({
    required this.searchController,
    required this.onSearchChanged,
    required this.filterOptions,
    super.key,
    this.searchHint = 'Search titles…',
    this.padding = const EdgeInsets.only(top: 8, bottom: 4),
    this.onClearAll,
    this.trailingAfterFilters,
    this.registerSearchForPageFab = true,
    this.onSearchSubmitted,
    this.searchTrailing,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String searchHint;
  final List<LibraryFilterOption> filterOptions;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onClearAll;
  final Widget? trailingAfterFilters;
  final bool registerSearchForPageFab;
  final ValueChanged<String>? onSearchSubmitted;
  final Widget? searchTrailing;

  @override
  State<LibrarySearchFilterHeader> createState() => _LibrarySearchFilterHeaderState();
}

class _LibrarySearchFilterHeaderState extends State<LibrarySearchFilterHeader> {
  final GlobalKey _filterButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final activeCount = libraryActiveFilterCount(widget.filterOptions);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: widget.padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: LibraryItemSearchField(
              controller: widget.searchController,
              hintText: widget.searchHint,
              onChanged: widget.onSearchChanged,
              onSubmitted: widget.onSearchSubmitted,
              trailing: widget.searchTrailing,
              registerForPageSearchFab: widget.registerSearchForPageFab,
            ),
          ),
          if (widget.filterOptions.isNotEmpty) ...[
            const SizedBox(width: 6),
            IconButton(
              key: _filterButtonKey,
              tooltip: activeCount > 0 ? 'Filters ($activeCount active)' : 'Filters',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              style: IconButton.styleFrom(
                backgroundColor: activeCount > 0
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHigh,
                foregroundColor: activeCount > 0
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              onPressed: () => showLibraryFilterMenu(
                context,
                anchorKey: _filterButtonKey,
                options: widget.filterOptions,
                onClearAll: widget.onClearAll,
              ),
              icon: Badge(
                isLabelVisible: activeCount > 0,
                label: Text(
                  '$activeCount',
                  style: const TextStyle(fontSize: 10),
                ),
                child: const Icon(Icons.tune, size: 20),
              ),
            ),
          ],
          if (widget.trailingAfterFilters != null) ...[
            const SizedBox(width: 6),
            widget.trailingAfterFilters!,
          ],
        ],
      ),
    );
  }
}
