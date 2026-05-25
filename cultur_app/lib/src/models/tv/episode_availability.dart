/// Whether an episode's air date is on or before today (unknown dates count as aired).
bool tvEpisodeAiredForWatch(String? airDate) {
  final t = airDate?.trim() ?? '';
  if (t.isEmpty) {
    return true;
  }
  final ymd = t.length >= 10 ? t.substring(0, 10) : t;
  final parsed = DateTime.tryParse(ymd);
  if (parsed == null) {
    return true;
  }
  final today = DateTime.now();
  final epDay = DateTime(parsed.year, parsed.month, parsed.day);
  final nowDay = DateTime(today.year, today.month, today.day);
  return !epDay.isAfter(nowDay);
}
