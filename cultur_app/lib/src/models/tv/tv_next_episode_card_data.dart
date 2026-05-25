class TvNextEpisodeCardData {
  const TvNextEpisodeCardData({
    required this.seasonNumber,
    required this.episodeNumber,
    this.name,
    this.airDate,
    this.stillUrl,
    this.runtimeMinutes,
  });

  factory TvNextEpisodeCardData.fromJson(Map<String, dynamic> json) {
    final sn = json['seasonNumber'];
    final en = json['episodeNumber'];
    final rt = json['runtimeMinutes'];
    return TvNextEpisodeCardData(
      seasonNumber: sn is int ? sn : int.tryParse(sn?.toString() ?? '') ?? 0,
      episodeNumber: en is int ? en : int.tryParse(en?.toString() ?? '') ?? 0,
      name: json['name']?.toString(),
      airDate: json['airDate']?.toString(),
      stillUrl: json['stillUrl']?.toString(),
      runtimeMinutes: rt is int ? rt : int.tryParse(rt?.toString() ?? ''),
    );
  }

  final int seasonNumber;
  final int episodeNumber;
  final String? name;
  final String? airDate;
  final String? stillUrl;
  final int? runtimeMinutes;
}
