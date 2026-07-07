import 'package:flutter_forumhub/domain/models/forum_channel.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';
import 'package:flutter_forumhub/domain/models/reply.dart';
import 'package:flutter_forumhub/domain/models/thread_detail_payload.dart';
import 'package:flutter_forumhub/domain/repositories/forum_repository.dart';

class MockForumRepository implements ForumRepository {
  const MockForumRepository();

  static const int _detailPageSize = 20;

  @override
  Future<List<ForumChannel>> channelsForSource(ForumSource source) async {
    switch (source) {
      case ForumSource.nga:
        return const <ForumChannel>[
          ForumChannel(
            id: '-7',
            source: ForumSource.nga,
            title: '网事杂谈',
            subtitle: '默认订阅',
            isSubscribed: true,
            sortOrder: 0,
          ),
          ForumChannel(
            id: '706',
            source: ForumSource.nga,
            title: '大时代',
            subtitle: '默认订阅',
            isSubscribed: true,
            sortOrder: 1,
          ),
          ForumChannel(
            id: '-7955747',
            source: ForumSource.nga,
            title: '晴风村',
            subtitle: '默认订阅',
            isSubscribed: true,
            sortOrder: 2,
          ),
        ];
      case ForumSource.v2ex:
        return const <ForumChannel>[
          ForumChannel(
            id: 'creative',
            source: ForumSource.v2ex,
            title: 'creative',
            subtitle: '创意工作者',
            isSubscribed: true,
            sortOrder: 0,
          ),
          ForumChannel(
            id: 'swift',
            source: ForumSource.v2ex,
            title: 'swift',
            subtitle: 'Swift 开发',
            isSubscribed: true,
            sortOrder: 1,
          ),
        ];
      case ForumSource.linuxDo:
        return const <ForumChannel>[
          ForumChannel(
            id: 'general',
            source: ForumSource.linuxDo,
            title: 'General',
            subtitle: '综合交流',
            isSubscribed: true,
            sortOrder: 0,
          ),
          ForumChannel(
            id: 'share',
            source: ForumSource.linuxDo,
            title: 'Share',
            subtitle: '经验分享',
            isSubscribed: true,
            sortOrder: 1,
          ),
        ];
    }
  }

  @override
  Future<List<ForumThread>> threadsForChannel(
    ForumSource source,
    String channelId,
  ) async {
    switch (source) {
      case ForumSource.nga:
        if (channelId == '-7') {
          return const <ForumThread>[
            ForumThread(
              id: '90001',
              source: ForumSource.nga,
              channelId: '-7',
              title: '版规与发帖须知',
              author: '版主组',
              createdAt: '今天 09:12',
              replyCount: 128,
              viewCount: 5044,
              summary: '这里是预览数据，后续 Flutter 会接真实 NGA feed adapter。',
              isPinned: true,
            ),
            ForumThread(
              id: '991001',
              source: ForumSource.nga,
              channelId: '-7',
              title: '分页调试主题',
              author: 'CJ',
              createdAt: '2026-06-30 12:21',
              replyCount: 120,
              viewCount: 4096,
              summary: '用于后续 thread detail 和分页状态机迁移的 mock 样例。',
            ),
            ForumThread(
              id: '90003',
              source: ForumSource.nga,
              channelId: '-7',
              title: '网页登录后复用 cookie 请求接口',
              author: '架构组',
              createdAt: '今天 16:48',
              replyCount: 18,
              viewCount: 873,
              summary: '登录成功后会同步 WebView cookie 到 HTTP 客户端。',
            ),
          ];
        }

        return <ForumThread>[
          ForumThread(
            id: '${channelId}_1',
            source: ForumSource.nga,
            channelId: channelId,
            title: '$channelId 板块样例主题',
            author: 'ForumHub',
            createdAt: '今天 18:00',
            replyCount: 12,
            viewCount: 320,
            summary: '后续这里会接 NGA 真实版面列表。',
          ),
        ];
      case ForumSource.v2ex:
        return const <ForumThread>[
          ForumThread(
            id: 'v2ex_1001',
            source: ForumSource.v2ex,
            channelId: 'creative',
            title: 'Flutter rebuild 记录帖',
            author: 'v2er',
            createdAt: '1 小时前',
            replyCount: 24,
            viewCount: 980,
            summary: 'V2EX 在 Flutter 阶段优先迁只读 feed 和详情。',
          ),
          ForumThread(
            id: 'v2ex_1002',
            source: ForumSource.v2ex,
            channelId: 'creative',
            title: 'API token 登录与本地收藏',
            author: 'api-user',
            createdAt: '3 小时前',
            replyCount: 8,
            viewCount: 301,
            summary: 'V2EX 收藏先保留 local-first，再看是否扩展能力。',
          ),
        ];
      case ForumSource.linuxDo:
        return const <ForumThread>[
          ForumThread(
            id: 'ld_1001',
            source: ForumSource.linuxDo,
            channelId: 'general',
            title: 'Discourse adapter 迁移笔记',
            author: 'linuxdo',
            createdAt: '今天',
            replyCount: 32,
            viewCount: 1500,
            summary: 'LINUX DO 后续沿用 web login + cookie reuse 的迁移策略。',
          ),
          ForumThread(
            id: 'ld_1002',
            source: ForumSource.linuxDo,
            channelId: 'general',
            title: 'Flutter WebView cookie bridge',
            author: 'ops',
            createdAt: '昨天',
            replyCount: 14,
            viewCount: 712,
            summary: '需要先定义 WebView 与 HTTP cookie 的双向同步边界。',
          ),
        ];
    }
  }

  @override
  Future<ThreadDetailPayload> threadDetail(
    ForumSource source,
    String threadId, {
    required int page,
  }) async {
    final ForumThread thread = await _threadById(source, threadId);
    final int totalPages = source == ForumSource.nga ? 7 : 3;
    final int safePage = page.clamp(1, totalPages);

    return ThreadDetailPayload(
      thread: thread,
      replies: _repliesForThread(thread, safePage),
      currentPage: safePage,
      totalPages: totalPages,
    );
  }

  Future<ForumThread> _threadById(ForumSource source, String threadId) async {
    final List<ForumChannel> channels = await channelsForSource(source);
    for (final ForumChannel channel in channels) {
      final List<ForumThread> threads = await threadsForChannel(source, channel.id);
      for (final ForumThread thread in threads) {
        if (thread.id == threadId) {
          return thread;
        }
      }
    }

    return ForumThread(
      id: threadId,
      source: source,
      channelId: 'unknown',
      title: '未找到主题',
      author: 'ForumHub',
      createdAt: '刚刚',
      replyCount: 0,
      viewCount: 0,
      summary: '该主题仅用于 Flutter 骨架阶段的兜底展示。',
    );
  }

  List<Reply> _repliesForThread(ForumThread thread, int page) {
    final int startFloor = ((page - 1) * _detailPageSize) + 2;
    return List<Reply>.generate(_detailPageSize, (int index) {
      final int floor = startFloor + index;
      final bool isAuthorReply = floor % 5 == 0;
      return Reply(
        id: '${thread.id}_$floor',
        author: isAuthorReply ? thread.author : '用户$floor',
        createdAt: '2026-07-01 ${8 + (index % 10)}:${(index * 3).toString().padLeft(2, '0')}',
        floor: floor,
        body: '这是 ${thread.title} 的第 $floor 楼 mock 回复，用于 Flutter thread detail 与分页状态迁移。',
      );
    });
  }
}
