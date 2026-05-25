class GameTimeToBeat {
  const GameTimeToBeat({
    this.main,
    this.extras,
    this.completion,
  });

  factory GameTimeToBeat.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const GameTimeToBeat();
    }
    return GameTimeToBeat(
      main: json['main']?.toString(),
      extras: json['extras']?.toString(),
      completion: json['completion']?.toString(),
    );
  }

  final String? main;
  final String? extras;
  final String? completion;

  bool get hasAny =>
      (main?.trim().isNotEmpty ?? false) ||
      (extras?.trim().isNotEmpty ?? false) ||
      (completion?.trim().isNotEmpty ?? false);
}
