/// Standard poster dimensions used across list rows and thumbnails.
enum CulturPosterSizePreset {
  /// Watched history rows, dense TV rows (32×50).
  xs,

  /// Action sheets, small previews (42×60).
  sm,

  /// Compact list rows (48×72).
  md,

  /// Detailed list rows (72×108).
  lg,
}

extension CulturPosterSizePresetDimensions on CulturPosterSizePreset {
  double get width => switch (this) {
        CulturPosterSizePreset.xs => 32,
        CulturPosterSizePreset.sm => 42,
        CulturPosterSizePreset.md => 48,
        CulturPosterSizePreset.lg => 72,
      };

  double get height => switch (this) {
        CulturPosterSizePreset.xs => 50,
        CulturPosterSizePreset.sm => 60,
        CulturPosterSizePreset.md => 72,
        CulturPosterSizePreset.lg => 108,
      };
}
