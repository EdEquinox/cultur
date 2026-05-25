class BookPublisherLink {
  const BookPublisherLink({
    required this.publisherId,
    required this.name,
  });

  factory BookPublisherLink.fromJson(Map<String, dynamic> json) {
    return BookPublisherLink(
      publisherId: json['publisherId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  final String publisherId;
  final String name;

  bool get isValid => publisherId.isNotEmpty && name.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'publisherId': publisherId,
        'name': name,
      };
}
