import 'package:flutter_forumhub/data/nga/models/nga_forum_page_payload.dart';
import 'package:flutter_forumhub/data/nga/parsers/nga_parser_support.dart';
import 'package:flutter_forumhub/domain/models/forum_channel.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';

class NgaForumListParser {
  const NgaForumListParser._();

  static List<ForumChannel> parseChannels(String rawText) {
    final Object? object = ngaDecodeObject(rawText);
    if (object == null) {
      return const <ForumChannel>[];
    }

    final List<ForumChannel> channels = collectDictionaries(object)
        .map(_makeChannel)
        .whereType<ForumChannel>()
        .toList();

    return _dedupeChannels(channels);
  }

  static NgaForumPagePayload? parsePage({
    required String rawText,
    required String channelId,
  }) {
    final Object? object = ngaDecodeObject(rawText);
    if (object == null) {
      return null;
    }

    final List<Map<String, dynamic>> dictionaries = collectDictionaries(object);
    final List<ForumThread> threads = _dedupeThreads(
      dictionaries
          .map((Map<String, dynamic> item) {
            return _makeThread(item, fallbackChannelId: channelId);
          })
          .whereType<ForumThread>()
          .take(30)
          .toList(),
    );

    if (threads.isEmpty) {
      return null;
    }

    final List<ForumChannel> channels = parseChannels(rawText);
    return NgaForumPagePayload(
      channels: channels.isEmpty
          ? <ForumChannel>[
              ForumChannel(
                id: channelId,
                source: ForumSource.nga,
                title: 'NGA 版面 $channelId',
                subtitle: '来自 NGA feed 接口',
              ),
            ]
          : channels,
      threads: threads,
    );
  }

  static ForumChannel? _makeChannel(Map<String, dynamic> dictionary) {
    final int? id = readInt(dictionary, const <String>['fid', 'forum_id', 'id']);
    final String? rawTitle = readString(
      dictionary,
      const <String>['name', 'title', 'forum_name', 'fname'],
    );
    final String title = rawTitle == null ? '' : cleanForumText(rawTitle);
    final bool looksLikeForum = dictionary.containsKey('fid') ||
        dictionary.containsKey('forum_id') ||
        dictionary.containsKey('forum_name') ||
        dictionary.containsKey('fname');

    if (id == null || title.isEmpty || !looksLikeForum) {
      return null;
    }

    return ForumChannel(
      id: '$id',
      source: ForumSource.nga,
      title: title,
      subtitle: '来自 NGA 接口',
    );
  }

  static ForumThread? _makeThread(
    Map<String, dynamic> dictionary, {
    required String fallbackChannelId,
  }) {
    final String? rawTitle = readString(
      dictionary,
      const <String>[
        'subject',
        'title',
        't',
        'topic',
        'post_subject',
        'topic_title',
        '_subject',
      ],
    );
    final String title = rawTitle == null ? '' : cleanForumText(rawTitle);
    if (title.length < 2) {
      return null;
    }

    final int? threadId = readInt(
      dictionary,
      const <String>['tid', 'id', 'topic_id', 'thread_id'],
    );
    if (threadId == null && !dictionary.containsKey('subject')) {
      return null;
    }

    final String channelId =
        '${readInt(dictionary, const <String>['fid', 'forum_id']) ?? int.tryParse(fallbackChannelId) ?? fallbackChannelId}';
    final String summary = cleanForumText(
      readString(
            dictionary,
            const <String>['content', 'intro', 'subject', 'title', 'post_subject'],
          ) ??
          title,
    );

    return ForumThread(
      id: '${threadId ?? title.hashCode.abs()}',
      source: ForumSource.nga,
      channelId: channelId,
      title: title,
      author: parseAuthorName(dictionary) ?? '未知作者',
      createdAt: readString(
            dictionary,
            const <String>['postdate', 'timestamp', 'created_at', 'post_time', 'time'],
          ) ??
          '未知时间',
      replyCount: readInt(
            dictionary,
            const <String>['replies', 'reply_count', 'postnum', 'replys'],
          ) ??
          0,
      viewCount: readInt(
            dictionary,
            const <String>['views', 'view_count', 'hits'],
          ) ??
          0,
      summary: summary,
      authorAvatarUrl: parseAvatarUrl(dictionary),
      isPinned: (readInt(dictionary, const <String>['top', 'sticky']) ?? 0) > 0,
    );
  }

  static List<ForumChannel> _dedupeChannels(List<ForumChannel> channels) {
    final Map<String, ForumChannel> byId = <String, ForumChannel>{};
    for (final ForumChannel channel in channels) {
      byId.putIfAbsent(channel.id, () => channel);
    }
    return byId.values.toList();
  }

  static List<ForumThread> _dedupeThreads(List<ForumThread> threads) {
    final Map<String, ForumThread> byId = <String, ForumThread>{};
    for (final ForumThread thread in threads) {
      byId.putIfAbsent(thread.id, () => thread);
    }
    return byId.values.toList();
  }
}
