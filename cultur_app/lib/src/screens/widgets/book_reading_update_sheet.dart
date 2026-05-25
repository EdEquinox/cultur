import 'package:flutter/material.dart';
import 'package:yamtrack/src/models/catalog/catalog_item.dart';
import 'package:yamtrack/src/utils/book_progress_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';

/// Bottom sheet to adjust the current page while reading a book.
class BookReadingUpdateSheet extends StatefulWidget {
  const BookReadingUpdateSheet({
    super.key,
    required this.media,
    required this.initialPage,
  });

  final CatalogItem media;
  final int initialPage;

  static Future<int?> show(
    BuildContext context, {
    required CatalogItem media,
    required int initialPage,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return BookReadingUpdateSheet(
          media: media,
          initialPage: initialPage,
        );
      },
    );
  }

  @override
  State<BookReadingUpdateSheet> createState() => _BookReadingUpdateSheetState();
}

class _BookReadingUpdateSheetState extends State<BookReadingUpdateSheet> {
  late int _page;

  int? get _totalPages => bookPageCount(widget.media);

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
  }

  void _setPage(int value) {
    final total = _totalPages;
    var next = value < 0 ? 0 : value;
    if (total != null && next > total) {
      next = total;
    }
    setState(() => _page = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _totalPages;
    final summary = total != null && total > 0
        ? '${bookReadingPercent(current: _page, total: total)}%'
        : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Update reading', style: CulturCatalogTypography.sectionHeading(theme)),
          const SizedBox(height: 4),
          Text(
            widget.media.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: CulturCatalogTypography.listMeta(theme, scheme),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: _page <= 0 ? null : () => _setPage(_page - 1),
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  Text(
                    total != null ? 'Page $_page / $total' : 'Page $_page',
                    style: CulturCatalogTypography.listTitle(theme),
                  ),
                  if (summary != null) ...[
                    const SizedBox(height: 4),
                    Text(summary, style: CulturCatalogTypography.listMeta(theme, scheme)),
                  ],
                ],
              ),
              const SizedBox(width: 16),
              IconButton.filledTonal(
                onPressed: () => _setPage(_page + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_page),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
