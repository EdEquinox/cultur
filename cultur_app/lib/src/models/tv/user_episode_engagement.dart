class UserEpisodeEngagement {
  const UserEpisodeEngagement({
    this.userRating,
    this.userRatingRatedAt,
    this.userWatchlist,
    this.userWatchlistedAt,
  });

  factory UserEpisodeEngagement.fromJson(
    Map<String, dynamic> json, {
    String ratingKey = 'userRating',
    String ratingAtKey = 'userRatingRatedAt',
    String watchlistKey = 'userWatchlist',
    String watchlistedAtKey = 'userWatchlistedAt',
  }) {
    final ur = json[ratingKey];
    final uw = json[watchlistKey];
    return UserEpisodeEngagement(
      userRating: ur is num ? ur.toDouble() : double.tryParse(ur?.toString() ?? ''),
      userRatingRatedAt: json[ratingAtKey]?.toString(),
      userWatchlist: uw is bool ? uw : null,
      userWatchlistedAt: json[watchlistedAtKey]?.toString(),
    );
  }

  factory UserEpisodeEngagement.seasonFromJson(Map<String, dynamic> json) {
    return UserEpisodeEngagement.fromJson(
      json,
      ratingKey: 'userSeasonRating',
      ratingAtKey: 'userSeasonRatingRatedAt',
      watchlistKey: 'userSeasonWatchlist',
      watchlistedAtKey: 'userSeasonWatchlistedAt',
    );
  }

  final double? userRating;
  final String? userRatingRatedAt;
  final bool? userWatchlist;
  final String? userWatchlistedAt;
}
