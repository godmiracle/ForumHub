import 'package:flutter_forumhub/core/network/forum_http_client.dart';
import 'package:flutter_forumhub/core/session/forum_cookie_bridge.dart';
import 'package:flutter_forumhub/data/repositories/composite_forum_repository.dart';
import 'package:flutter_forumhub/data/repositories/mock_forum_repository.dart';
import 'package:flutter_forumhub/data/repositories/nga_live_forum_repository.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/repositories/forum_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final StateProvider<bool> usesMockForumDataProvider = StateProvider<bool>((ref) {
  return false;
});

final Provider<ForumCookieBridge> forumCookieBridgeProvider = Provider<ForumCookieBridge>((ref) {
  return const ForumCookieBridge();
});

final Provider<ForumHttpClient> forumHttpClientProvider = Provider<ForumHttpClient>((ref) {
  return ForumHttpClient(
    cookieBridge: ref.watch(forumCookieBridgeProvider),
  );
});

final Provider<ForumRepository> forumRepositoryProvider = Provider<ForumRepository>((ref) {
  final bool usesMock = ref.watch(usesMockForumDataProvider);

  if (usesMock) {
    return const MockForumRepository();
  }

  return CompositeForumRepository(
    repositories: <ForumSource, ForumRepository>{
      ForumSource.nga: NgaLiveForumRepository(
        postTransport: ref.watch(forumHttpClientProvider).postForm,
      ),
      ForumSource.v2ex: const MockForumRepository(),
      ForumSource.linuxDo: const MockForumRepository(),
    },
  );
});
