# ForumHub 待办清单

本文件用于记录可执行、可验证、可追踪的开发事项。AI Agent 在开始任务前必须读取本文件，并且只更新与当前任务直接相关的事项。

## 待办状态规则

- `[ ]`：待处理或尚未完成验证；
- `[x]`：代码已修改、验收标准已满足，并完成必要验证；
- 代码已修改但当前环境无法验证时，保持 `[ ]`，并标记“状态：已修改，等待验证”或“状态：等待人工验证”；
- 验证失败时保持 `[ ]`，记录失败原因；
- 不得为了提高完成率删除、合并或隐藏未完成事项。

Review 新增事项应使用 `R-XXX` 唯一编号，并至少记录优先级、涉及文件、状态和验收标准。详细格式见 [review.md](review.md)。


## 帖子详情

### ForumHub 代码审查清单

- [x] 将 `ThreadDetailView` 的展示逻辑拆分为职责明确的 UI 组件。
- [x] 为刷新、跳页和连续加载增加可取消任务与请求代次控制。
- [x] 缓存展示回复和分页入口数据，减少滚动期间的重复计算。
- [x] 建立 `ForumError`，并优先用于帖子详情的用户可见错误展示。
- [x] 引入共享 `ForumGlass` 组件，并迁移帖子详情悬浮控件及信息流刷新提示。
- [x] 将 README 中依赖本机路径的链接替换为仓库相对链接。
- [ ] 使用明确的 Repository 分页能力替代帖子详情中的 `.nga` 分页判断。
- [ ] 将帖子详情的加载、分页、回复和收藏状态迁移到独立的 `ThreadDetailViewModel`。
- [ ] 恢复测试 Target 后，运行 NGA 分页合并回归测试，覆盖重复回复、主楼移除和多页跳转。
- [ ] 将 `ForumError` 的展示能力扩展到信息流、搜索、账户和媒体流程。
- [ ] 修复测试 Target 签名，并恢复缺失的 `ThreadDetailDirectPaginationAutoAdvancePolicy` 测试依赖，使完整测试可在真机运行。
- [ ] 在真机测量超长帖子非懒加载渲染及内存占用。

### 根据既有决策暂缓

- Xcode 项目格式兼容：当前明确暂不处理。项目继续使用 Xcode 27 Beta 格式，待安装稳定版工具链后再单独决策迁移。

- [ ] 使用更多真实帖子验证 NGA 详情连续分页，重点覆盖主楼与后续分页混合的边界情况。
- [ ] 使用真实长帖验证 NGA 接近末尾自动分页和页面锚点可见页追踪，确保持续向下加载平滑可靠。
- [ ] 在真机验证 NGA 连续阅读视觉无断层：中间不显示“加载下一页”卡片，仅在全部回复加载完后显示帖子结束状态。
- [ ] 在真实帖子和真机上验证 NGA 按楼层回复，确认当前 `action=quote + pid + prefilled content` 流程兼容更多引用格式。
- [ ] 当 V2EX 和 LINUX DO 详情接口具备稳定分页合约后，评估是否需要数据源原生回复分页控件。
- [ ] 决定页面选择器是否应在同一 App 会话中记住每个帖子的最后手动选择页。
- [ ] 决定只看楼主或倒序导致部分页面锚点隐藏时，悬浮页码控件的行为。

## 社区与数据源

- [ ] 继续优化数据源切换和频道管理体验。
- [ ] 评估社区管理是否需要更清晰地区分已订阅频道和数据源默认频道。

## 信息流

- [x] 增加可取消的信息流加载任务与请求代次，避免过期的首页或热榜响应覆盖当前标签页。
- [ ] 若真机首次加载仍显突兀，评估信息流初始加载应继续使用居中转圈，还是改为轻量骨架屏。

## 图片与媒体

- [ ] 测量基于视口的行内 GIF 限流与预览降采样是否足够，评估剩余活动 GIF 是否仍需比 `WKWebView` 更轻量的播放方案。

## 同步与持久化

- [ ] 在可靠的跨设备同步方案可行前，继续保持屏蔽用户和收藏本地优先。
- [ ] 重新启用任何云同步路径前，先定义数据迁移规则。

## 账户与会话

- [ ] 验证共享 `AuthSessionDescriptor` 和认证注册表能够覆盖 Token 过期、Cookie 部分同步、需要重新连接等未来会话状态，且不重新引入数据源专属 View 分支。
- [ ] 决定顶部 NGA 账户卡片是否迁移到共享会话描述路径，或明确保留为数据源原生详情卡片。

## 第二轮 Code Review 待修复与优化清单

以下事项依据 [ForumHub-Code-Review-Round-2.md](ForumHub-Code-Review-Round-2.md) 整理；按修复顺序排列，首页和热门 Tab 重选回顶按要求置于最后。

- [ ] R-201 放宽 NGA 富文本图片解析并统一图片 URL 解析
  - 优先级：高
  - 涉及文件或模块：`ForumHub/Domain/ForumContent.swift`、NGA 富文本解析链路
  - 状态：已修改，已依据真实主贴的 `./mon_…` 图片标记补充回归用例；等待真机验证
  - 验收标准：支持正文内 `[图片]`、`[img]...[/img]`、协议相对 URL、相对附件路径、一行多图和含 `&amp;` 的 URL；可信 NGA HTTP 图片升级为 HTTPS；文本与图片顺序保持正确。

- [ ] R-202 在 NGA API 解析内容不完整时以网页结果补全而非整体覆盖
  - 优先级：高
  - 涉及文件或模块：`ForumHub/Data/NGA/NGAForumRepository.swift`、`ForumHub/Data/NGA/Parsers/ThreadDetailParser.swift`、`ForumHub/Data/NGA/Parsers/WebForumParser.swift`
  - 状态：已修改，主贴正文现兼容字符串与分段数组内容；等待真实 NGA 帖子验证
  - 验收标准：可根据正文、回复数和图片完整度判断是否补全；网页结果仅补充 API 缺失内容；网页请求失败时保留 API 结果；合并后主楼、回帖和图片均不重复。

- [ ] R-203 为可信 NGA 图片请求补齐站点所需 Header 与 Cookie 策略
  - 优先级：中
  - 涉及文件或模块：NGA 图片加载与缓存链路
  - 状态：已修改，等待真机图片加载验证
  - 验收标准：仅对受信任 NGA 图片域名添加 `Referer`、`User-Agent` 和 Cookie 处理；非 NGA 图片请求不携带站点专属 Header；图片加载失败时仍可打开原图地址。

- [ ] R-204 为 NGA 富文本、图片 URL 和 API/Web 合并补充可回归的 Fixture 与测试
  - 优先级：中
  - 涉及文件或模块：`ForumHubTests`、NGA Fixtures
  - 状态：已部分修改，已补图片 URL 单元测试；完整 Fixture 与 API/Web 合并测试待处理
  - 验收标准：覆盖 BBCode、HTML 图片、GIF、引用图片、表格/代码块、第二页图片、协议相对/相对路径及 URL 转义；覆盖 API 不完整时的补全和去重；相关测试可运行并通过。

- [ ] R-205 将搜索草稿与焦点状态下沉，并让首页和热门共用顶部搜索栏
  - 优先级：中
  - 涉及文件或模块：`ForumHub/ContentView.swift`、`ForumHub/Features/ForumFeed/ForumFeedViews.swift`
  - 状态：已修改，等待真机交互验证
  - 验收标准：输入草稿不再使根 `ContentView`、首页和热门列表进行不必要重算；父层只接收已提交关键词；首页和热门始终只渲染一份顶部搜索栏。

- [ ] R-206 缓存信息流排序结果，避免搜索输入或普通 View 刷新重复排序和列表 Diff
  - 优先级：中
  - 涉及文件或模块：`ForumHub/ContentView.swift`、`ForumHub/Features/ForumFeed/ForumViewModel.swift`
  - 状态：已修改，等待真机滚动与排序切换验证
  - 验收标准：排序只在帖子数据或排序方式变化时重建；输入搜索草稿不触发信息流重新排序；首页和热门展示顺序与现有规则一致。

- [x] R-207 完善搜索键盘的提交、清空、滚动和切换 Tab 收起行为
  - 优先级：中
  - 涉及文件或模块：`ForumHub/Features/ForumFeed/ForumFeedViews.swift`、`ForumHub/Features/Search/SearchThreadsView.swift`
  - 状态：已完成，真机交互验证通过；已实现提交、清空、滚动、“完成”和切换 Tab 收起键盘
  - 验收标准：搜索框使用 `FocusState`；键盘工具栏提供“完成”；提交、清空和切换 Tab 后收起键盘；首页/热门滚动可交互收起键盘，搜索结果滚动立即收起键盘。

- [ ] R-208 将搜索请求状态迁移至具备 Task 所有权和 generation 的 `SearchThreadsViewModel`
  - 优先级：中
  - 涉及文件或模块：`ForumHub/Features/Search/SearchThreadsView.swift`、新增或现有 `SearchThreadsViewModel`
  - 状态：已修改，等待搜索交互回归验证
  - 验收标准：新搜索取消旧搜索及旧的加载更多任务；过期响应不能覆盖新关键词结果；同关键词且已有结果不重复请求；离开页面时可取消任务。

- [ ] R-209 统一搜索失败的 `ForumError` 展示
  - 优先级：中
  - 涉及文件或模块：`ForumHub/Features/Search/SearchThreadsView.swift`、`ForumError`
  - 状态：已修改，等待失败场景验证
  - 验收标准：网络、解析和取消以外的失败映射为用户可理解的错误状态；重试可恢复正常搜索；不泄露底层数据源错误细节。

- [x] R-210 完成帖子详情业务状态和异步任务的 ViewModel 化
  - 优先级：中
  - 涉及文件或模块：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`、`ForumHub/Features/ThreadDetail/*`
  - 状态：已完成，真机回归验证通过；展示、加载任务、分页、回复与收藏状态及其网络操作均已迁移至 `ThreadDetailViewModel`，View 仅保留滚动定位和 UI 事件转发
  - 验收标准：加载、分页、回复、收藏及错误状态移出 `ThreadDetailView`；View 保持展示和事件转发职责；现有取消、请求代次、去重、只看楼主和倒序行为不回归。

- [x] R-211 用数据源 `ForumCapabilities` 描述详情分页与图片能力，删除 View 中 NGA 专属判断
  - 优先级：中
  - 涉及文件或模块：`ForumHub/Domain/ForumModels.swift`、各数据源 Repository、帖子详情模块
  - 状态：已完成，真机回归验证通过；详情分页类型与页大小已迁移，回复编辑器图片入口已改由 `supportsImageUpload` 控制
  - 验收标准：分页类型和页大小通过 capability 提供；详情 View 不再依赖 `repository.source == .nga` 或硬编码页大小；NGA、V2EX、LINUX DO 的既有详情行为保持兼容。

- [ ] R-212 在真机评估长帖结构化内容渲染和 Lazy 性能
  - 优先级：低
  - 涉及文件或模块：帖子详情富文本和图片渲染链路
  - 状态：等待人工验证
  - 验收标准：使用含多页回复、图片和 GIF 的真实长帖测量滚动帧率与内存；记录可复现的性能基线；如存在明显卡顿，再提出最小化优化方案。

- [x] R-213 修复首页、热门再次点击当前 Tab 不回到顶部
  - 优先级：高
  - 涉及文件或模块：`ForumHub/ContentView.swift`、Tab 重选监听与 `ForumFeedContent` 回顶链路
  - 状态：已完成，已由真机验证
  - 验收标准：首页或热门滚动至少 20 条后，重复点击当前 Tab 能立即回顶；两个 Tab 的滚动位置互不影响；点击其他 Tab 不误触发回顶；快速重复点击不创建多个刷新请求；已在顶部时再次点击才刷新且刷新后仍停在顶部。
