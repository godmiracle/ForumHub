# ForumHub 系统设计迁移待办

本文件只追踪 [ForumHub-System-Design.md](ForumHub-System-Design.md) 定义的阶段 0–7。旧 Code Review 编号、历史缺陷批次和旧架构拆分不再作为工作主线。

## 执行规则

- 每次只推进一个可独立验证的垂直切片；阶段表示依赖关系，不要求瀑布式全部实施。
- `[x]` 仅表示验收标准已经满足并完成必要验证；只完成代码修改时仍保持 `[ ]`，标记“已修改，等待验证”。
- 条件触发项在触发条件成立前不得实施，不为完成架构图而创建抽象或移动目录。
- 涉及真机差异时优先在已连接 iOS 真机验证；无法验证时明确记录原因。
- 完成迁移后同步受影响的 ADR、模块文档和 Changelog，不重复维护旧 Review 状态。

## 当前执行顺序

1. 其余事项仅在前置条件满足后启动。

---

## 阶段 0：补齐剩余护栏（进行中）

- [x] **SD-0.1 固定所有默认 UI Test 的 Mock 场景**
  - 具体问题：部分 UI Test 场景治理尚未完全收口，仍可能受真实登录恢复、网络或服务端数据影响。
  - 涉及文件或模块：`ForumHub/Features/ForumFeed/UITestScenario.swift`、`ForumHub/ContentView.swift`、`ForumHubUITests`、`docs/testing.md`
  - 优先级：P1
  - 状态：已完成；搜索、数据源切换、分页、连续回顶、启动性能和启动截图均显式使用固定 Mock 场景。启动性能与 8 组界面配置启动截图共 9 次真机 UI Test 已通过。
  - 验收标准：
    - 所有默认 UI Test 显式声明固定场景；
    - 场景启动不恢复真实登录，不请求真实信息流；
    - Mock 数据覆盖 NGA、V2EX、LINUX DO；
    - 相关 UI Test 在真机可重复通过。

- [x] **SD-0.2 补齐 NGA API/Web 合并、分页与内容 Fixture**
  - 具体问题：真实响应形状和降级路径仍有未覆盖边界，可能重新引入正文截断、主楼重复或图片丢失。
  - 涉及文件或模块：`ForumHub/Data/NGA`、`ForumHubTests/Fixtures`、`ForumHubTests`
  - 优先级：P0
  - 状态：已完成；API 完整/不完整、Web 补全成功/失败、权限错误、真实图片形状、分页去重、第二页 GIF 与转义 URL、引用图片原文保留、末页不足一页和摘要不得回填正文均已有覆盖。Fixture 来源类型和脱敏规则已记录，相关 69 个测试已在真机通过。
  - 验收标准：
    - 覆盖 API 完整、API 不完整、Web 补全失败和权限错误；
    - 覆盖重复主楼、重复回复、第二页图片及末页不足一页；
    - 覆盖 BBCode、HTML 图片、GIF、引用图片和 URL 转义；
    - Fixture 脱敏并记录来源形状；
    - 相关测试在真机通过。

- [x] **SD-0.3 建立迁移验证记录模板**
  - 具体问题：性能、真机回归和回滚依据分散在旧待办描述中，不利于垂直切片验收。
  - 涉及文件或模块：`docs/testing.md`、`docs/sessions/`、迁移相关文档
  - 优先级：P2
  - 状态：已完成；`docs/sessions/README.md` 定义设备、系统、命令、结果、限制和回滚点模板，`SD-3.1` 已在 `docs/sessions/2026-07-13.md` 实际使用，且未复制完整自动化日志。
  - 验收标准：
    - 模板包含设备、系统、测试命令、结果、已知限制和回滚点；
    - 不重复记录自动化测试日志中的可获取信息；
    - 至少由一个迁移切片实际使用。

---

## 阶段 1：身份值类型可行性验证（条件触发）

- [ ] **SD-1.1 审计显式 `source + id` 身份键**
  - 具体问题：当前依靠调用点显式组合身份，需要先证明是否仍存在遗漏或显著维护成本。
  - 涉及文件或模块：Domain、导航、收藏、历史、搜索追加、分页去重、持久化
  - 优先级：P2
  - 状态：条件未触发；当前收藏、历史和主要去重路径已有来源维度。
  - 验收标准：
    - 列出所有身份判断调用点及当前键；
    - 用测试证明实际冲突或明确记录无冲突；
    - 未发现问题时关闭评估，不引入新 ID 类型。

- [ ] **SD-1.2 以单一 Store 试点组合 ID 值类型**
  - 具体问题：只有 `SD-1.1` 证明编译期身份类型有明确收益时，才验证迁移方案。
  - 涉及文件或模块：优先选择收藏或历史、`ForumThreadID`、Codable migration
  - 优先级：P3
  - 状态：等待 `SD-1.1` 触发。
  - 验收标准：
    - 旧持久化数据无损迁移；
    - 同 native ID 的不同来源不冲突；
    - 不同时迁移多个 Store；
    - 试点收益和成本形成 ADR，再决定是否扩展。

---

## 阶段 2：收敛正文兼容投影（进行中）

- [x] **SD-2.1 完成 `summary`、`body`、`contentDocument` 读取链路审计**
  - 具体问题：兼容字段仍可能被误当作权威正文，分享、截图、引用或降级流程可能产生不一致。
  - 涉及文件或模块：`ForumHub/Domain/ForumModels.swift`、帖子详情、长图、回复引用、收藏、历史、各数据源 Mapper
  - 优先级：P0
  - 状态：已完成；详情空正文不再回填列表摘要，收藏恢复不再伪造正文，长图、回复引用、分页重复主楼识别和 NGA 正文完整度判断已直接消费 `ForumPostDocument`。脱敏真实形状 Fixture 已覆盖 API 不完整、Web 补全成功和 Web 补全失败，相关 68 个测试已在真机通过，正常页面已人工确认无回归。
  - 验收标准：
    - 信息流摘要不会在详情加载前或详情正文缺失时显示为主楼；
    - 渲染、长图、分享和回复引用均从 `ForumPostDocument` 或明确派生值读取；
    - 收藏与历史恢复只携带轻量元数据；
    - 正常详情、空正文、加载失败和缓存恢复均有回归覆盖；
    - 使用脱敏真实响应 Fixture 或可控 Stub 覆盖 API 不完整、Web 补全成功和 Web 补全失败；不要求在线等待异常。

- [x] **SD-2.2 评估删除 `body` 存储字段**
  - 具体问题：`body` 与 `ForumPostDocument.normalizedText` 双存可能漂移，但删除会影响大量构造器和测试。
  - 涉及文件或模块：Domain、所有 Repository/Parser、持久化、详情、测试 Fixture
  - 优先级：P2
  - 状态：已完成；`ForumThread.body` 和 `Reply.body` 已改为 `contentDocument.normalizedText` 的只读计算投影，不再独立存储。初始化器保留 `body` 参数以兼容现有构造点，并仅在未提供文档时创建纯文本文档。收藏和历史只持久化轻量元数据，无存储迁移；完整 `ForumHubTests` 已在真机通过。
  - 验收标准：
    - 完成所有读写点清单和兼容迁移方案；
    - 证明删除收益高于迁移成本；
    - `body` 改为只读计算投影或决定保留并记录原因；
    - 全量相关测试与真机关键路径通过。

- [ ] **SD-2.3 独立评估 `ThreadSummary` 与 `ThreadDetail` 分离**
  - 具体问题：`ForumThread` 同时承载摘要和详情形态，但拆分可能扩大导航、收藏、历史和 Fixture 迁移面。
  - 涉及文件或模块：Domain、Repository、Navigation、Feed、Search、ThreadDetail、Persistence
  - 优先级：P2
  - 状态：待评估，不与 `SD-2.2` 同时实施。
  - 验收标准：
    - 用已发生缺陷或新增缓存需求证明拆分价值；
    - 明确分页结果、聚合详情和持久化快照的边界；
    - 形成 ADR 和最小试点方案；
    - 无充分收益时明确否决，不创建新模型。

---

## 阶段 3：帖子详情剩余状态治理（进行中）

- [x] **SD-3.1 收敛滚动状态所有权**
  - 具体问题：滚动偏移、可见页、返回顶部和阅读位置仍跨 View 与状态对象协作，需要确认是否存在多写入者。
  - 涉及文件或模块：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`、`ThreadDetailPaginationState`、滚动监听链路
  - 优先级：P1
  - 状态：已完成；远端分页进度由 `ThreadDetailPaginationState`/ViewModel 唯一写入，滚动派生状态由 `ThreadDetailScrollState`/View 唯一写入。完整 `ForumHubTests` 与多页自动加载、连续回顶两个 UI Test 已在真机通过；既有只看楼主、倒序和图片高度变化路径继续复用同一滚动监听链路。
  - 验收标准：
    - 为每个滚动派生状态标出唯一写入者；
    - 不创建与 `ThreadDetailPaginationState` 重复的 Coordinator；
    - 多页、只看楼主、倒序、图片高度变化和连续回顶不回归；
    - 只有测试收益明确时才新增 `ThreadDetailScrollState`。

- [ ] **SD-3.2 缩小媒体状态传播范围**
  - 具体问题：活动 GIF 集合变化可能触发正文和回复区域大范围重绘。
  - 涉及文件或模块：`InlineGIFPlaybackCoordinator`、`ThreadDetailRichContent`、Header/Reply 组件
  - 优先级：P1
  - 状态：待处理，需与阶段 6 性能基线联动。
  - 验收标准：
    - GIF 节点身份稳定；
    - 媒体节点只接收自身播放许可或从单一协调器查询；
    - 活动集合变化不重复解析整帖；
    - 真机指标相对 `SD-6.1` 基线改善且功能不回归。

---

## 阶段 4：按真实内容缺口扩展节点

- [ ] **SD-4.1 建立未支持内容格式清单**
  - 具体问题：表格、代码块、链接和未知标签的真实缺口尚未由 Fixture 系统证明。
  - 涉及文件或模块：`ForumContentBlock`、NGA BBCode Parser、HTML Parser、Fixtures
  - 优先级：P2
  - 状态：待处理。
  - 验收标准：
    - 每种缺失格式至少有一个脱敏真实 Fixture；
    - 记录当前原生投影和网页保真结果；
    - 按用户影响排序，不凭假设扩展节点。

- [ ] **SD-4.2 逐类扩展内容节点与降级渲染**
  - 具体问题：由 `SD-4.1` 证明的格式需要在不替换整棵内容模型的前提下支持。
  - 涉及文件或模块：`ForumContentBlock`、Parser、`ThreadDetailRichContent`、长图渲染
  - 优先级：P2
  - 状态：等待 `SD-4.1`。
  - 验收标准：
    - 每次只增加一种节点；
    - Parser、原生渲染、长图和文本降级均有测试；
    - 未识别标记仍保留在 `rawMarkup`；
    - NGA、V2EX、LINUX DO 既有内容不回归。

---

## 阶段 5：网络与会话共享接缝（条件触发）

- [x] **SD-5.1 验证现有会话与请求隔离边界**
  - 具体问题：需要先确认 Cookie、Token、图片 Header 和 WebKit challenge 是否存在跨来源泄漏或重复实现。
  - 涉及文件或模块：`ForumHub/Session`、NGA/V2EX/LINUX DO Repository、图片请求、`AuthSessionDescriptor`
  - 优先级：P1
  - 状态：已完成；NGA 图片 Header/Cookie 仅限可信域名，V2EX 公开请求不携带 Authorization/Cookie，Token 请求强制限制为 HTTPS 官方 `/api/v2/`，LINUX DO 只有403进入 WebKit fallback。共享会话描述仅暴露安全身份摘要，不携带 CID、Cookie 名称或 Token；完整 `ForumHubTests` 已在真机通过。
  - 验收标准：
    - 非 NGA 请求不携带 NGA Header/Cookie；
    - Token、Cookie 和密码不进入共享描述或日志；
    - Token 过期、Cookie 部分同步和浏览器 challenge 有明确恢复路径；
    - 401/403 不做无条件自动重试。

- [ ] **SD-5.2 评估通用 `HTTPClient` 与 `RetryPolicy`**
  - 具体问题：只有两个以上数据源出现相同请求生命周期或重试逻辑时才值得抽取共享接缝。
  - 涉及文件或模块：Data、Session、未来 Infrastructure/Networking
  - 优先级：P3
  - 状态：条件未触发。
  - 验收标准：
    - 列出至少两个真实重复消费者；
    - 保留来源特有认证和 WebKit fallback；
    - 重试策略覆盖取消、超时、5xx、401/403 边界；
    - 无充分复用时不实施。

---

## 阶段 6：图片与 GIF（高优先级性能切片）

- [ ] **SD-6.1 建立 GIF 密集帖真机性能基线**
  - 具体问题：当前已观察到图片/GIF 密集帖高 CPU、约 743 MB 内存和 High 能耗，但缺少固定可重复基线。
  - 涉及文件或模块：图片管线、GIF 播放、帖子详情、性能记录
  - 优先级：P1
  - 状态：按用户要求暂缓，不在当前主线继续推进。测量协议和样本 A（NGA `tid=47139977`）保留，未来只有在用户重新启用该优化并提供可供 Instruments 识别的 USB 真机时恢复；依赖本基线的 `SD-6.2`、`SD-6.3` 同步暂停。
  - 验收标准：
    - 固定真机、帖子、网络条件和操作路径；
    - 记录 CPU、峰值内存、帧率、能耗和首次可读时间；
    - 区分静态图、GIF 下载、解码和播放成本；
    - 结果可用于比较后续方案。

- [ ] **SD-6.2 完善 GIF 生命周期与资源释放**
  - 具体问题：活动数量、离屏暂停、后台停止、内存警告和超大 GIF 降级需要统一策略。
  - 涉及文件或模块：`InlineGIFPlaybackCoordinator`、媒体视图、App 生命周期、图片缓存
  - 优先级：P1
  - 状态：等待 `SD-6.1` 基线。
  - 验收标准：
    - 同时活动 GIF 不超过配置上限；
    - 离屏、高速滚动、后台和低电量状态正确暂停；
    - 内存警告释放帧缓存；
    - 超大 GIF 支持首帧或点击播放降级；
    - 相同 URL 不重复下载，指标优于基线。

- [ ] **SD-6.3 评估替换 GIF 播放实现**
  - 具体问题：只有现有管线在生命周期治理后仍不达标，才考虑 SDWebImage 等替代方案。
  - 涉及文件或模块：项目依赖、GIF 播放与缓存链路
  - 优先级：P2
  - 状态：条件未触发。
  - 验收标准：
    - 与 `SD-6.1` 基线进行同设备对比；
    - 静态图、GIF/APNG、Cookie/Header 和预览流程不回归；
    - 仅在性能和稳定性明确更优时保留依赖；
    - 可独立回退。

---

## 阶段 7：其他 Feature 按缺陷迁移

- [ ] **SD-7.1 为持久化增加版本、损坏降级和迁移测试**
  - 具体问题：本地 Store 尚未统一表达 schema version、损坏降级和未来迁移规则。
  - 涉及文件或模块：Favorites、History、BlockedUsers、ChannelSubscription、Settings、Session 边界
  - 优先级：P2
  - 状态：待处理；iCloud 继续禁用。
  - 验收标准：
    - 用户内容 Store 具有明确版本和损坏降级；
    - 旧数据迁移测试通过；
    - 身份始终包含来源维度；
    - 认证状态不与普通用户内容合并迁移；
    - 不启用云同步。

- [ ] **SD-7.2 按已确认缺陷迁移 Feed、Search、Account 等 Feature**
  - 具体问题：其他 Feature 不应按预设顺序重构，只在真实缺陷或共享需求出现时处理。
  - 涉及文件或模块：Feed、Search、Account、Community、History、Settings
  - 优先级：P3
  - 状态：常驻入口，不代表已批准具体改动。
  - 验收标准：
    - 每个子项先记录已确认问题、证据和独立验收标准；
    - 每次只迁移一个 Feature 的一个垂直切片；
    - 不顺手创建全局 Use Case、依赖容器或重排目录；
    - 相关测试和用户文档同步。

---

## 已完成基线（不再重复迁移）

以下能力是后续迁移必须保持的回归基线，不再作为未完成任务重复出现：

- 帖子详情加载、分页、回复和收藏状态已迁移到 `ThreadDetailViewModel`。
- Feed、Search、Detail 已具备请求取消和 generation 防过期回写。
- 详情分页和图片上传入口已由 `ForumCapabilities` 表达。
- `ForumPostDocument` 已保留原始标记和原生阅读投影。
- `ForumThread` 内容相等与 `source + id` 身份判断已分离。
- NGA 连续分页、重复主楼移除、页码追踪和连续回顶已有真机回归。
- NGA 图片 Header 域名隔离、登录恢复、LINUX DO 解析已有单元测试。
- 正式测试策略文档已建立，iCloud 同步保持禁用。

---

## 旧待办迁移说明

旧 `R-*`、`T-*` 和按页面分类的待办已停止作为工作队列使用：

| 旧事项类别 | 新主线归属 |
| --- | --- |
| NGA 富文本、API/Web 合并、分页 Fixture | `SD-0.2`、`SD-2.1`、`SD-4.1` |
| Mock UI Test 与请求代次 | `SD-0.1`；已完成部分进入基线 |
| 组合身份、收藏、历史与同步 | `SD-1.1`、`SD-1.2`、`SD-7.1` |
| 详情滚动、分页、回顶和媒体状态 | `SD-3.1`、`SD-3.2`；已完成部分进入基线 |
| GIF 性能、播放数量和资源释放 | `SD-6.1`–`SD-6.3` |
| 搜索、Feed、账户、社区和体验优化 | `SD-7.2`，仅由已确认缺陷触发 |
| 已完成缺陷修复 | “已完成基线”或 Git 历史，不再重复列项 |

旧清单中纯产品偏好、没有证据的体验设想和已被当前实现取代的方案不自动迁移。若后续出现真实需求，应按 `SD-7.2` 新建可验证的垂直切片，而不是恢复旧编号。
