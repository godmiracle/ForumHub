import Foundation
import Testing
@testable import ForumHub

@MainActor
struct LinuxDoDiscourseParserTests {
    @Test func parserMapsTopicDetailAndNormalizesInlineImages() throws {
        let data = Data("""
        {
          "id": 77,
          "title": "LINUX DO 测试主题",
          "posts_count": 2,
          "views": 99,
          "category_id": 5,
          "category_name": "开发",
          "post_stream": {
            "posts": [
              {
                "id": 100,
                "username": "owner",
                "created_at": "2026-07-11T10:00:00Z",
                "cooked": "主楼<img src=\\"https://linux.do/uploads/main.png\\">"
              },
              {
                "id": 101,
                "username": "reply-user",
                "created_at": "2026-07-11T10:01:00Z",
                "cooked": "回复内容"
              }
            ]
          }
        }
        """.utf8)

        let thread = try LinuxDoDiscourseParser.threadDetail(from: data)

        #expect(thread.source == .linuxDo)
        #expect(thread.id == 77)
        #expect(thread.author == "owner")
        #expect(thread.channelTitle == "开发")
        #expect(thread.body.contains("[图片] https://linux.do/uploads/main.png"))
        #expect(thread.replies.map(\.sourcePostID) == [101])
    }
}
