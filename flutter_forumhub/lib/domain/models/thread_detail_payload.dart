import 'package:flutter_forumhub/domain/models/forum_thread.dart';
import 'package:flutter_forumhub/domain/models/reply.dart';

class ThreadDetailPayload {
  const ThreadDetailPayload({
    required this.thread,
    required this.replies,
    required this.currentPage,
    required this.totalPages,
  });

  final ForumThread thread;
  final List<Reply> replies;
  final int currentPage;
  final int totalPages;
}
