import 'package:flutter_forumhub/data/repositories/nga_live_forum_repository.dart';
import 'package:flutter_forumhub/domain/models/forum_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NgaLiveForumRepository', () {
    test('parses channels from favorforum response', () async {
      final NgaLiveForumRepository repository = NgaLiveForumRepository(
        postTransport: (Uri uri, Map<String, String> form) async {
          expect(uri.toString(), contains('__lib=favorforum'));
          return _channelsResponse;
        },
      );

      final channels = await repository.channelsForSource(ForumSource.nga);

      expect(channels, hasLength(2));
      expect(channels.first.id, '-7');
      expect(channels.first.title, '网事杂谈');
    });

    test('parses feed threads from subject list response', () async {
      final NgaLiveForumRepository repository = NgaLiveForumRepository(
        postTransport: (Uri uri, Map<String, String> form) async {
          expect(uri.toString(), contains('__lib=subject'));
          expect(form['fid'], '-7');
          return _feedResponse;
        },
      );

      final threads = await repository.threadsForChannel(ForumSource.nga, '-7');

      expect(threads, hasLength(2));
      expect(threads.first.id, '12345');
      expect(threads.first.title, 'Flutter 重构进度');
      expect(threads.first.author, 'CJ');
    });

    test('parses first-page detail and strips main post from replies', () async {
      final NgaLiveForumRepository repository = NgaLiveForumRepository(
        postTransport: (Uri uri, Map<String, String> form) async {
          expect(uri.toString(), contains('__lib=post'));
          expect(form['tid'], '12345');
          expect(form['page'], '1');
          return _detailPageOneResponse;
        },
      );

      final payload = await repository.threadDetail(
        ForumSource.nga,
        '12345',
        page: 1,
      );

      expect(payload.currentPage, 1);
      expect(payload.totalPages, 3);
      expect(payload.thread.title, 'Flutter 重构进度');
      expect(payload.thread.summary, '主楼内容');
      expect(payload.replies, hasLength(2));
      expect(payload.replies.first.floor, 2);
    });

    test('parses continuation page without keeping duplicated main post', () async {
      final NgaLiveForumRepository repository = NgaLiveForumRepository(
        postTransport: (Uri uri, Map<String, String> form) async {
          expect(form['page'], '2');
          return _detailPageTwoResponse;
        },
      );

      final payload = await repository.threadDetail(
        ForumSource.nga,
        '12345',
        page: 2,
      );

      expect(payload.currentPage, 2);
      expect(payload.replies, hasLength(2));
      expect(payload.replies.first.floor, 21);
      expect(payload.replies.first.body, '第二页第一条回复');
    });
  });
}

const String _channelsResponse = '''
{
  "data": {
    "0": {"fid": -7, "name": "网事杂谈"},
    "1": {"fid": 706, "name": "大时代"},
    "2": {"fid": -7, "name": "网事杂谈"}
  }
}
''';

const String _feedResponse = '''
{
  "result": {
    "0": {
      "tid": 12345,
      "fid": -7,
      "subject": "Flutter 重构进度",
      "author": "CJ",
      "postdate": "2026-07-01 10:00",
      "replies": 22,
      "views": 345,
      "content": "<b>先把 parser 跑通</b>"
    },
    "1": {
      "tid": 12346,
      "fid": -7,
      "subject": "分页状态机讨论",
      "author": "产品同学",
      "postdate": "2026-07-01 10:30",
      "replies": 8,
      "views": 120,
      "content": "继续拆解 thread detail"
    }
  },
  "forum": {
    "fid": -7,
    "name": "网事杂谈"
  }
}
''';

const String _detailPageOneResponse = '''
{
  "page": 1,
  "totalpage": 3,
  "result": {
    "0": {
      "pid": 0,
      "fid": -7,
      "lou": 1,
      "subject": "Flutter 重构进度",
      "author": {"username": "CJ", "avatar": "https://img.example.com/cj.png"},
      "postdate": "2026-07-01 10:00",
      "content": "主楼内容",
      "replies": 45,
      "views": 345
    },
    "1": {
      "pid": 2001,
      "fid": -7,
      "lou": 2,
      "author": "回复者A",
      "postdate": "2026-07-01 10:05",
      "content": "第二楼回复"
    },
    "2": {
      "pid": 2002,
      "fid": -7,
      "lou": 3,
      "author": "回复者B",
      "postdate": "2026-07-01 10:06",
      "content": "第三楼回复"
    }
  }
}
''';

const String _detailPageTwoResponse = '''
{
  "page": 2,
  "totalpage": 3,
  "result": {
    "0": {
      "pid": 0,
      "fid": -7,
      "lou": 1,
      "subject": "Flutter 重构进度",
      "author": "CJ",
      "postdate": "2026-07-01 10:00",
      "content": "主楼内容"
    },
    "1": {
      "pid": 2101,
      "fid": -7,
      "lou": 21,
      "author": "回复者C",
      "postdate": "2026-07-01 11:00",
      "content": "第二页第一条回复"
    },
    "2": {
      "pid": 2102,
      "fid": -7,
      "lou": 22,
      "author": "回复者D",
      "postdate": "2026-07-01 11:03",
      "content": "第二页第二条回复"
    }
  }
}
''';
