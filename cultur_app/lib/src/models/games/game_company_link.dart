class GameCompanyLink {
  const GameCompanyLink({
    required this.companyId,
    required this.name,
    this.imageUrl,
    this.role = 'publisher',
  });

  factory GameCompanyLink.fromJson(Map<String, dynamic> json) {
    return GameCompanyLink(
      companyId: json['companyId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString(),
      role: json['role']?.toString() ?? 'publisher',
    );
  }

  final String companyId;
  final String name;
  final String? imageUrl;
  final String role;

  bool get isValid => companyId.isNotEmpty && name.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'companyId': companyId,
        'name': name,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        'role': role,
      };
}
