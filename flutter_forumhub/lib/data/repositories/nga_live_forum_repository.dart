import 'package:flutter_forumhub/core/errors/unimplemented_source_exception.dart';
import 'package:flutter_forumhub/data/nga/models/nga_forum_page_payload.dart';
import 'package:flutter_forumhub/data/nga/parsers/nga_forum_list_parser.dart';
import 'package:flutter_forumhub/data/nga/parsers/nga_thread_detail_parser.dart';
import 'package:flutter_forumhub/domain/models/forum_channel.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_forumhub/domain/models/forum_thread.dart';
import 'package:flutter_forumhub/domain/models/thread_detail_payload.dart';
import 'package:flutter_forumhub/domain/repositories/forum_repository.dart';

typedef NgaPostTransport = Future<String> Function(
  Uri uri,
  Map<String, String> form,
);

class NgaLiveForumRepository implements ForumRepository {
  const NgaLiveForumRepository({NgaPostTransport? postTransport})
    : _postTransport = postTransport;

  final NgaPostTransport? _postTransport;

  @override
  Future<List<ForumChannel>> channelsForSource(ForumSource source) async {
    _assertSource(source);
    final String rawText = await _post(
      Uri.parse('https://bbs.nga.cn/app_api.php?__lib=favorforum&__act=sync'),
      const <String, String>{
        '_v': '2',
        '__output': '14',
      },
    );
    final List<ForumChannel> channels = NgaForumListParser.parseChannels(rawText);
    if (channels.isEmpty) {
      throw const FormatException('NGA channel response parsed to an empty channel list.');
    }
    return channels;
  }

  @override
  Future<ThreadDetailPayload> threadDetail(
    ForumSource source,
    String threadId, {
    required int page,
  }) async {
    _assertSource(source);
    final String rawText = await _post(
      Uri.parse('https://bbs.nga.cn/app_api.php?__lib=post&__act=list'),
      <String, String>{
        'tid': threadId,
        'page': '$page',
        '_v': '2',
        '__output': '14',
      },
    );
    final ThreadDetailPayload? payload = NgaThreadDetailParser.parse(
      rawText: rawText,
      threadId: threadId,
      page: page,
    );
    if (payload == null) {
      throw const FormatException('NGA thread detail response could not be parsed.');
    }
    return payload;
  }

  @override
  Future<List<ForumThread>> threadsForChannel(
    ForumSource source,
    String channelId,
  ) async {
    _assertSource(source);
    final String rawText = await _post(
      Uri.parse('https://bbs.nga.cn/app_api.php?__lib=subject&__act=list'),
      <String, String>{
        'fid': channelId,
        'page': '1',
        '_v': '2',
        '__output': '14',
      },
    );
    final NgaForumPagePayload? payload = NgaForumListParser.parsePage(
      rawText: rawText,
      channelId: channelId,
    );
    if (payload == null || payload.threads.isEmpty) {
      throw const FormatException('NGA feed response could not be parsed.');
    }
    return payload.threads;
  }

  void _assertSource(ForumSource source) {
    if (source != ForumSource.nga) {
      throw ArgumentError.value(source, 'source', 'NgaLiveForumRepository only supports NGA.');
    }
  }

  Future<String> _post(Uri uri, Map<String, String> form) async {
    final NgaPostTransport? transport = _postTransport;
    if (transport == null) {
      throw const UnimplementedSourceException(
        'NGA live transport is not wired yet. Parser and repository seams are ready for the cookie-backed HTTP port.',
      );
    }

    return transport(uri, form);
  }
}
