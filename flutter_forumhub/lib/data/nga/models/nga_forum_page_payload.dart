import 'package:flutter_forumhub/domain/models/forum_channel.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';

class NgaForumPagePayload {
  const NgaForumPagePayload({
    required this.channels,
    required this.threads,
  });

  final List<ForumChannel> channels;
  final List<ForumThread> threads;
}
