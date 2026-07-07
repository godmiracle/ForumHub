import 'package:flutter_forumhub/domain/models/forum_channel.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';
import 'package:flutter_forumhub/domain/models/thread_detail_payload.dart';
import 'package:flutter_forumhub/domain/repositories/forum_repository.dart';

class CompositeForumRepository implements ForumRepository {
  const CompositeForumRepository({
    required Map<ForumSource, ForumRepository> repositories,
  }) : _repositories = repositories;

  final Map<ForumSource, ForumRepository> _repositories;

  ForumRepository _repositoryFor(ForumSource source) {
    final ForumRepository? repository = _repositories[source];
    if (repository == null) {
      throw StateError('No repository registered for ${source.name}');
    }
    return repository;
  }

  @override
  Future<List<ForumChannel>> channelsForSource(ForumSource source) {
    return _repositoryFor(source).channelsForSource(source);
  }

  @override
  Future<ThreadDetailPayload> threadDetail(
    ForumSource source,
    String threadId, {
    required int page,
  }) {
    return _repositoryFor(source).threadDetail(source, threadId, page: page);
  }

  @override
  Future<List<ForumThread>> threadsForChannel(
    ForumSource source,
    String channelId,
  ) {
    return _repositoryFor(source).threadsForChannel(source, channelId);
  }
}
