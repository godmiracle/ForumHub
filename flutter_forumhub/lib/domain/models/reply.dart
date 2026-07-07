class Reply {
  const Reply({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.floor,
    this.avatarUrl,
  });

  final String id;
  final String author;
  final String body;
  final String createdAt;
  final int? floor;
  final String? avatarUrl;
}
