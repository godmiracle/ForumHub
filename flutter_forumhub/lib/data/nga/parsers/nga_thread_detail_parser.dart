import 'package:flutter_forumhub/data/nga/parsers/nga_parser_support.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';
import 'package:flutter_forumhub/domain/models/reply.dart';
import 'package:flutter_forumhub/domain/models/thread_detail_payload.dart';

class NgaThreadDetailParser {
  const NgaThreadDetailParser._();

  static ThreadDetailPayload? parse({
    required String rawText,
    required String threadId,
    required int page,
  }) {
    final Object? object = ngaDecodeObject(rawText);
    if (object == null) {
      return null;
    }

    final List<Map<String, dynamic>> resultDictionaries = _postDictionaries(object, page: page);
    final List<Reply> posts = resultDictionaries
        .asMap()
        .entries
        .map((MapEntry<int, Map<String, dynamic>> entry) {
          return _makeReply(
            entry.value,
            fallbackId: '${threadId}_${page}_${entry.key}',
          );
        })
        .whereType<Reply>()
        .toList();

    if (posts.isEmpty) {
      return null;
    }

    final Map<String, dynamic> firstDictionary =
        resultDictionaries.isEmpty ? const <String, dynamic>{} : resultDictionaries.first;
    final int currentPage =
        _readPageValue(object, const <String>['page', 'current_page']) ?? page;
    final int totalPages =
        _readPageValue(object, const <String>['totalpage', 'total_page', 'page_count']) ??
            currentPage;
    final String channelId =
        '${readInt(firstDictionary, const <String>['fid', 'forum_id']) ?? 0}';
    final String title = cleanForumText(
      readString(
            firstDictionary,
            const <String>['subject', 'title', 'post_subject', 'topic_title'],
          ) ??
          '帖子 $threadId',
    );
    final int viewCount =
        readInt(firstDictionary, const <String>['views', 'view_count', 'hits']) ?? 0;

    if (page > 1) {
      return ThreadDetailPayload(
        thread: ForumThread(
          id: threadId,
          source: ForumSource.nga,
          channelId: channelId,
          title: title,
          author: parseAuthorName(firstDictionary) ?? '未知作者',
          createdAt: readString(
                firstDictionary,
                const <String>['postdate', 'timestamp', 'created_at', 'time'],
              ) ??
              '未知时间',
          replyCount: posts.length,
          viewCount: viewCount,
          summary: '',
          authorAvatarUrl: parseAvatarUrl(firstDictionary),
        ),
        replies: posts,
        currentPage: currentPage,
        totalPages: totalPages,
      );
    }

    final Reply firstPost = posts.first;
    final List<Reply> replies = posts.skip(1).toList();

    return ThreadDetailPayload(
      thread: ForumThread(
        id: threadId,
        source: ForumSource.nga,
        channelId: channelId,
        title: title,
        author: firstPost.author,
        createdAt: firstPost.createdAt,
        replyCount: readInt(
              firstDictionary,
              const <String>['replies', 'reply_count', 'postnum'],
            ) ??
            replies.length,
        viewCount: viewCount,
        summary: firstPost.body,
        authorAvatarUrl: firstPost.avatarUrl,
      ),
      replies: replies,
      currentPage: currentPage,
      totalPages: totalPages,
    );
  }

  static List<Map<String, dynamic>> _postDictionaries(Object object, {required int page}) {
    final Object? normalized = normalizeNestedObject(object);
    if (normalized is! Map<String, dynamic>) {
      return collectDictionaries(normalized);
    }

    final Object? result = normalizeNestedObject(normalized['result']);
    if (result is List<dynamic>) {
      return _normalizeResultList(
        result.whereType<Map<String, dynamic>>().toList(),
        page: page,
      );
    }

    if (result is Map<String, dynamic>) {
      final List<MapEntry<int, Map<String, dynamic>>> keyedPosts = result.entries
          .map((MapEntry<String, dynamic> entry) {
            final Object? nested = normalizeNestedObject(entry.value);
            if (nested is! Map<String, dynamic>) {
              return null;
            }
            final int sortKey = int.tryParse(entry.key) ??
                readInt(
                      nested,
                      const <String>['lou', 'floor', 'position', 'pid', 'id', 'post_id'],
                    ) ??
                1 << 30;
            return MapEntry<int, Map<String, dynamic>>(sortKey, nested);
          })
          .whereType<MapEntry<int, Map<String, dynamic>>>()
          .toList()
        ..sort((MapEntry<int, Map<String, dynamic>> left, MapEntry<int, Map<String, dynamic>> right) {
          if (left.key != right.key) {
            return left.key.compareTo(right.key);
          }
          final int leftId =
              readInt(left.value, const <String>['pid', 'id', 'post_id']) ?? 1 << 30;
          final int rightId =
              readInt(right.value, const <String>['pid', 'id', 'post_id']) ?? 1 << 30;
          return leftId.compareTo(rightId);
        });

      return _normalizeResultList(
        keyedPosts.map((MapEntry<int, Map<String, dynamic>> entry) => entry.value).toList(),
        page: page,
      );
    }

    return _normalizeResultList(collectDictionaries(object), page: page);
  }

  static List<Map<String, dynamic>> _normalizeResultList(
    List<Map<String, dynamic>> dictionaries, {
    required int page,
  }) {
    if (page <= 1) {
      return dictionaries;
    }

    final List<Map<String, dynamic>> filtered = dictionaries.where((Map<String, dynamic> item) {
      final int? pid = readInt(item, const <String>['pid', 'post_id']);
      if (pid == 0) {
        return false;
      }

      final int? floor = readInt(item, const <String>['lou', 'floor', 'position']);
      if (floor != null && floor <= 1) {
        return false;
      }

      return true;
    }).toList();

    return filtered.isEmpty ? dictionaries : filtered;
  }

  static Reply? _makeReply(
    Map<String, dynamic> dictionary, {
    required String fallbackId,
  }) {
    final String? rawBody = readString(
      dictionary,
      const <String>['content', 'postcontent', 'body', 'comment'],
    );
    final String body = rawBody == null ? '' : cleanForumText(rawBody);
    if (body.isEmpty) {
      return null;
    }

    return Reply(
      id: '${readInt(dictionary, const <String>['pid', 'id', 'post_id']) ?? fallbackId}',
      author: parseAuthorName(dictionary) ?? '未知作者',
      body: body,
      createdAt: readString(
            dictionary,
            const <String>['postdate', 'timestamp', 'created_at', 'lastpost', 'time'],
          ) ??
          '未知时间',
      floor: readInt(dictionary, const <String>['lou', 'floor', 'position']),
      avatarUrl: parseAvatarUrl(dictionary),
    );
  }

  static int? _readPageValue(Object object, List<String> keys) {
    final List<Map<String, dynamic>> dictionaries = collectDictionaries(object);
    for (final Map<String, dynamic> dictionary in dictionaries) {
      final int? candidate = readInt(dictionary, keys);
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }
}
