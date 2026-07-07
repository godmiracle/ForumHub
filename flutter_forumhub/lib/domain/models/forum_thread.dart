import 'package:flutter_forumhub/domain/models/forum_source.dart';

class ForumThread {
  const ForumThread({
    required this.id,
    required this.source,
    required this.channelId,
    required this.title,
    required this.author,
    required this.createdAt,
    required this.replyCount,
    required this.viewCount,
    this.summary = '',
    this.authorAvatarUrl,
    this.isPinned = false,
  });

  final String id;
  final ForumSource source;
  final String channelId;
  final String title;
  final String author;
  final String createdAt;
  final int replyCount;
  final int viewCount;
  final String summary;
  final String? authorAvatarUrl;
  final bool isPinned;
}
