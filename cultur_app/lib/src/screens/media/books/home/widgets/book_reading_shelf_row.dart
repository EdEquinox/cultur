import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yamtrack/src/core/api_error_ui.dart';
import 'package:yamtrack/src/models/games/game_home_shelf_item.dart';
import 'package:yamtrack/src/providers/books_home_providers.dart';
import 'package:yamtrack/src/providers/tracking_providers.dart';
import 'package:yamtrack/src/screens/widgets/book_reading_update_sheet.dart';
import 'package:yamtrack/src/utils/book_progress_utils.dart';
import 'package:yamtrack/src/utils/catalog_utils.dart';
import 'package:yamtrack/src/widgets/cards/cultur_catalog_typography.dart';
import 'package:yamtrack/src/widgets/cards/cultur_poster_image.dart';

/// Reading shelf row — progress summary + side action (like TV continue watching).
class BookReadingShelfRow extends ConsumerStatefulWidget {
  const BookReadingShelfRow({
    super.key,
    required this.item,
    required this.username,
  });

  final GameHomeShelfItem item;
  final String username;

  static const double width = 340;
  static const double height = 100;

  @override
  ConsumerState<BookReadingShelfRow> createState() => _BookReadingShelfRowState();
}

class _BookReadingShelfRowState extends ConsumerState<BookReadingShelfRow> {
  bool _busy = false;

  Future<void> _savePage(int page) async {
    final username = widget.username.trim();
    if (username.isEmpty) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(trackingMutationControllerProvider).updateReadingProgress(
            username: username,
            media: widget.item.media,
            tracking: widget.item.tracking,
            currentPage: page,
          );
      invalidateBooksHomeCaches(ref, username: username);
    } catch (error) {
      if (mounted) {
        showApiErrorSnackBar(context, error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openUpdateSheet() async {
    final tracking = widget.item.tracking;
    final current = bookCurrentPage(tracking);
    final nextPage = await BookReadingUpdateSheet.show(
      context,
      media: widget.item.media,
      initialPage: current,
    );
    if (!mounted || nextPage == null || nextPage == current) {
      return;
    }
    await _savePage(nextPage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tracking = widget.item.tracking;
    final media = widget.item.media;
    final authorsLabel = bookAuthorsLabel(media);
    final progressSummary = bookReadingProgressSummary(tracking: tracking);
    final progressValue = bookReadingProgressFraction(tracking);
    final canUpdate = widget.username.trim().isNotEmpty;

    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(4),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: BookReadingShelfRow.width,
        height: BookReadingShelfRow.height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: InkWell(
                onTap: () => context.push(catalogItemDetailPath(media)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 54,
                          height: double.infinity,
                          child: CulturPosterImage(
                            imageUrl: media.imageUrl,
                            width: 54,
                            height: 80,
                            borderRadius: BorderRadius.circular(4),
                            mediaType: 'book',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              media.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CulturCatalogTypography.listTitle(theme),
                            ),
                            if (authorsLabel != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                authorsLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CulturCatalogTypography.listMeta(theme, scheme),
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              progressSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CulturCatalogTypography.listMeta(theme, scheme),
                            ),
                            const Spacer(),
                            if (progressValue != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  minHeight: 4,
                                  value: progressValue,
                                  backgroundColor: scheme.surfaceContainerHighest,
                                  color: scheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: SizedBox(
                width: 52,
                child: _busy
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton.filledTonal(
                        tooltip: 'Update page',
                        onPressed: canUpdate ? _openUpdateSheet : null,
                        icon: const Icon(Icons.menu_book_outlined),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(22, 22),
                          padding: const EdgeInsets.all(8),
                          backgroundColor: Colors.transparent,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
