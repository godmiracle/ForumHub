# ForumHub 测试策略

本文件定义 ForumHub 的自动化测试分层、场景边界与执行方式。目标是让大多数回归在不启动 App、不访问网络的前提下完成，同时保留少量只读的真实会话检查。

## 分层策略

### 1. 单元测试

单元测试位于 `ForumHubTests`，不启动 App、不访问网络。优先覆盖：

- 数据源解析、领域映射、分页合并与持久化；
- GIF 可视区候选排序与同时播放数量限制；
- Search、Feed 与帖子详情的请求代次、取消和陈旧结果隔离；
- NGA 图片请求的可信域名、Referer、User-Agent 与 Cookie 隔离；
- NGA、V2EX、LINUX DO 的登录状态、过期状态和响应解析。

测试应通过固定 Data、Mock Repository 或纯策略对象构造输入，不得请求真实社区接口。

### 2. Mock UI Test

UI 测试位于 `ForumHubUITests`，安装测试 App 并使用固定场景。它是日常界面回归的主要入口。

当前固定场景：

- `UITEST_DEFAULT_FEED`：固定 NGA 信息流，用于搜索和基础导航；
- `UITEST_SOURCE_SWITCH`：固定 NGA、V2EX、LINUX DO Repository，用于数据源切换；
- `UITEST_PAGED_THREAD`：多页帖子详情，用于验证连续分页、页码与返回顶部；

所有日常 UI Test 必须显式传入上述场景之一。场景模式跳过登录恢复和真实信息流请求，不得依赖网络、Cookie 或本地历史数据。

新增 UI Test 必须使用稳定的 `accessibilityIdentifier`，不得依赖真实账号、网络返回顺序或本地历史数据。

### 3. Real Session UI Test

真实会话检查同样运行测试 App，但仅允许读取真实登录状态和只读接口。它不应成为日常 CI 的依赖。

建议保留的只读检查：

- NGA 首页、帖子详情、图片和 GIF 是否可加载；
- NGA 已有会话是否可恢复；
- V2EX 首页是否可加载；
- LINUX DO 已有网页登录会话能否读取当前账号。

禁止自动执行回复、收藏/取消收藏、删除、登出、上传附件或任何其他写操作。

## 当前重点回归清单

1. 帖子详情连续两次“下滑 → 回顶”均回到主楼；
2. GIF 仅选择视口附近、最接近中心且不超过上限的媒体；
3. Search、Feed、Detail 的旧请求被取消或晚到时不得覆盖新结果；
4. NGA 专属图片 Header 绝不泄漏给非 NGA 域名；
5. 过期会话展示为未登录，恢复有效 Cookie 后重新展示为已连接；
6. LINUX DO `current_user` 响应可解析，缺失账号时明确识别为未登录。

## 执行方式

优先使用已连接真机：

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -project ForumHub.xcodeproj \
  -scheme ForumHub \
  -configuration Debug \
  -destination 'platform=iOS,id=<CONNECTED_DEVICE_ID>' \
  test
```

没有真机时，允许只编译测试产物，确认生产代码、测试代码与测试目标可链接：

```sh
xcodebuild \
  -project ForumHub.xcodeproj \
  -scheme ForumHub \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build-for-testing
```

`build-for-testing` 不等同于真机执行；必须在测试记录中明确标注实际运行环境。

## 迁移验证记录

完成 `ForumHub-System-Design.md` 的迁移切片时，使用 [sessions/README.md](sessions/README.md) 中的模板，并按日期写入 `docs/sessions/YYYY-MM-DD.md`。记录只补充自动化日志无法表达的环境、范围、限制和回滚依据，不复制完整构建输出。

## Fixture 规则

- 可复用远端样本放入 `ForumHubTests/Fixtures`；
- Fixture 文件名描述来源与场景，例如 `linuxdo-session-authenticated.json`；
- 解析回归应同时覆盖正常响应、缺字段、未登录和错误状态；
- 新增数据源行为时，先补 Fixture 与单元测试，再接入 UI。

## 测试维护规则

- 生产逻辑替换后，迁移旧测试到新的公开接缝，不恢复已删除的实现只为通过编译；
- 每个已修复的用户可见回归至少保留一条自动化测试；
- UI Test 只验证确定的 Mock 场景，真实会话问题通过单独只读检查记录；
- 任何无法在当前环境运行的测试，必须标记为“等待真机验证”，不得声称已通过。
