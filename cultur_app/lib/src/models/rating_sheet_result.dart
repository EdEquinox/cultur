/// Result from [MovieRatingSheet] / rating bottom sheets.
sealed class RatingSheetResult {
  const RatingSheetResult();
}

/// User dismissed without saving.
final class RatingSheetDismissed extends RatingSheetResult {
  const RatingSheetDismissed();
}

/// User cleared an existing rating (0 stars or Remove rating).
final class RatingSheetRemoved extends RatingSheetResult {
  const RatingSheetRemoved();
}

/// User saved a 1–10 rating.
final class RatingSheetSet extends RatingSheetResult {
  const RatingSheetSet(this.score);

  final double score;
}
