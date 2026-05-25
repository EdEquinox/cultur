/// Shared grid metrics for catalog posters (search, collected, personal lists).
abstract final class CulturCatalogGridMetrics {
  static const double posterAspectRatio = 2 / 3;

  static const double crossAxisSpacing = 8;
  static const double mainAxisSpacing = 6;

  /// Gap + title + subtitle + buffer under the poster in [CulturCatalogGridCard].
  static const double textBlockHeight = 36;

  /// Full card height at a given width (poster 2:3 + text block).
  static double totalHeightForWidth(double width) =>
      width / posterAspectRatio + textBlockHeight;

  /// Grid [childAspectRatio] for a cell of [cellWidth] (width / height).
  static double aspectRatioForCellWidth(double cellWidth) =>
      cellWidth / totalHeightForWidth(cellWidth);

  /// Conservative default for 2–4 column grids (~100–130px cells).
  static const double gridChildAspectRatio = 0.50;

  /// Music/album search: square art + title/subtitle needs a taller cell.
  static const double musicGridChildAspectRatio = 0.62;
}
