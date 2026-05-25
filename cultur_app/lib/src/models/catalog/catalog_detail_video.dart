/// Trailer or clip linked from catalog detail (mainly TMDB).
class CatalogDetailVideo {
  const CatalogDetailVideo({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.url,
  });

  factory CatalogDetailVideo.fromJson(Map<String, dynamic> json) {
    return CatalogDetailVideo(
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      url: json['url']?.toString(),
    );
  }

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? url;
}
