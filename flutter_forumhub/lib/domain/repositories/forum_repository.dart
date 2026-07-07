import 'package:flutter_forumhub/domain/models/forum_channel.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';
import 'package:flutter_forumhub/domain/models/thread_detail_payload.dart';

abstract class ForumRepository {
  Future<List<ForumChannel>> channelsForSource(ForumSource source);

  Future<List<ForumThread>> threadsForChannel(
    ForumSource source,
    String channelId,
  );

  Future<ThreadDetailPayload> threadDetail(
    ForumSource source,
    String threadId, {
    required int page,
  });
}
