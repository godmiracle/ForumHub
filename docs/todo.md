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
- [ ] 修复测试 Target 签名，并将已移除的 `ThreadDetailDirectPaginationAutoAdvancePolicy` 测试迁移至当前连续分页实现，使完整测试可在真机运行。
  - 状态：测试源码编译错误已修复；`ForumHubTests` 已于真机完整通过，`ForumHubUITests.testThreadDetailScrollToTopReturnsToFirstPage` 已于真机通过。
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
  - 状态：已修改，已依据真实主贴的 `./mon_…` 图片标记补充回归用例，并修正主贴 Header 未随正文更新重建的问题；该主贴已在真机验证正文与图片正常展示，其他图片格式边界待回归验证
  - 验收标准：支持正文内 `[图片]`、`[img]...[/img]`、协议相对 URL、相对附件路径、一行多图和含 `&amp;` 的 URL；可信 NGA HTTP 图片升级为 HTTPS；文本与图片顺序保持正确。

- [ ] R-202 在 NGA API 解析内容不完整时以网页结果补全而非整体覆盖
  - 优先级：高
  - 涉及文件或模块：`ForumHub/Data/NGA/NGAForumRepository.swift`、`ForumHub/Data/NGA/Parsers/ThreadDetailParser.swift`、`ForumHub/Data/NGA/Parsers/WebForumParser.swift`
  - 状态：已修改，主贴正文现兼容字符串与分段数组内容；API/Web 合并改为保留 API 内容并仅追加网页缺失单元，网页缺少楼层元数据时按正文兜底去重；等待真实 NGA 帖子验证
  - 验收标准：可根据正文、回复数和图片完整度判断是否补全；网页结果仅补充 API 缺失内容；网页请求失败时保留 API 结果；合并后主楼、回帖和图片均不重复。

- [ ] R-203 为可信 NGA 图片请求补齐站点所需 Header 与 Cookie 策略
  - 优先级：中
  - 涉及文件或模块：NGA 图片加载与缓存链路
  - 状态：已修改，真实 NGA 主贴图片已在真机加载成功；非 NGA 请求隔离与失败后打开原图待回归验证
  - 验收标准：仅对受信任 NGA 图片域名添加 `Referer`、`User-Agent` 和 Cookie 处理；非 NGA 图片请求不携带站点专属 Header；图片加载失败时仍可打开原图地址。

- [ ] R-204 为 NGA 富文本、图片 URL 和 API/Web 合并补充可回归的 Fixture 与测试
  - 优先级：中
  - 涉及文件或模块：`ForumHubTests`、NGA Fixtures
  - 状态：已部分修改，已补图片 URL 单元测试及 API 不完整/网页补全 Fixture；受测试 Target 签名配置阻断，新增测试等待实际运行验证
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
  - 状态：已回退到原 `WKWebView` GIF 播放实现；已记录图片/GIF 密集帖刷新时 CPU 约 86%、内存约 743 MB、能耗 High，等待重新设计稳定的 GIF 渲染方案
  - 验收标准：使用含多页回复、图片和 GIF 的真实长帖测量滚动帧率与内存；记录可复现的性能基线；如存在明显卡顿，再提出最小化优化方案。

- [x] R-213 修复首页、热门再次点击当前 Tab 不回到顶部
  - 优先级：高
  - 涉及文件或模块：`ForumHub/ContentView.swift`、Tab 重选监听与 `ForumFeedContent` 回顶链路
  - 状态：已完成，已由真机验证
  - 验收标准：首页或热门滚动至少 20 条后，重复点击当前 Tab 能立即回顶；两个 Tab 的滚动位置互不影响；点击其他 Tab 不误触发回顶；快速重复点击不创建多个刷新请求；已在顶部时再次点击才刷新且刷新后仍停在顶部。

### P0：核心交互修复

- [x] R-301 修复帖子详情返回顶部按钮失效
  - 优先级：高
  - 涉及文件或模块：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`、浮动控件与滚动监听链路
  - 状态：已完成；真机 UI Test 覆盖连续两次“下滑至第 2 页 → 回顶”，均通过。
  - 验收标准：返回顶部操作不在滚动前提前改写分页状态；加载多页、只看楼主、倒序和 GIF 播放中均能稳定回到主楼；快速连续点击不造成页码错乱；补充 UI Test 和稳定的无障碍标识。

- [x] R-302 稳定帖子详情顶部锚点与滚动目标
  - 优先级：中
  - 涉及文件或模块：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
  - 状态：已完成；独立顶部锚点与请求代次协调已通过真机连续回顶验证。
  - 验收标准：使用稳定且不随正文或分页重建的锚点 ID；刷新、分页插入和图片高度变化后仍可定位；不存在重复 ID。

- [x] R-314 修复 NGA `postnum` 导致的详情页虚假末页
  - 优先级：高
  - 涉及文件或模块：`ForumHub/Data/NGA/Parsers/ForumListParsers.swift`、`ForumHub/Data/NGA/Parsers/ThreadDetailParser.swift`、`ForumHubTests/ForumHubTests.swift`
  - 状态：已完成；`postnum` 按总楼层数处理并扣除主楼，真机完整 `ForumHubTests` 已通过。
  - 验收标准：`postnum = 60` 归一化为 59 条回帖，20 条/页时总页数为 3；列表与详情计数一致；不再展示不可加载的第 4 页。

- [x] R-315 核实 NGA 信息流主题作者头像数据能力并停止无效请求
  - 优先级：高
  - 涉及文件或模块：`ForumHub/Data/NGA/Parsers/ForumListParsers.swift`、`ForumHubTests/ForumHubTests.swift`
  - 状态：已完成；真机 `subject/list` 脱敏响应确认仅含 `author`、`authorid`，不含头像字段或 `__U` 用户字典；NGA 网页列表同样仅提供字母/等级标识。列表不再请求已确认 404 的 UID 拼接地址，缺少头像时保留本地首字母占位。
  - 验收标准：不为主题列表的 `authorid` 生成无效头像 URL；直接头像字段若将来由接口提供仍可解析；无字段时显示本地占位；不为每个主题额外请求详情页。

- [x] R-303 删除正文字符串作为帖子 Header View ID 的实现
  - 优先级：高
  - 涉及文件或模块：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
  - 状态：已完成；移除正文 View ID 后，真机自动翻页与连续回顶 UI Test 均通过。
  - 验收标准：删除 `.id(detailThread.body)` 或改为稳定帖子 ID；正文补全仍可刷新；Header 不因正文变化整体重建；图片和 GIF 不重复请求或丢失播放状态。

### P1：GIF 性能与图片链路

- [ ] R-304 建立 GIF 密集帖性能基线并评估接入 SDWebImage 动画模块
  - 优先级：高
  - 涉及文件或模块：帖子详情富文本、图片加载与缓存链路、项目依赖配置
  - 状态：待处理
  - 验收标准：使用固定真实帖子记录现有 CPU、内存、帧率和能耗；完成静态图片与 GIF/APNG 分流；对比接入前后指标；仅在指标和稳定性更优时保留新方案。

- [ ] R-305 完善 GIF 下载、解码、播放和释放生命周期
  - 优先级：高
  - 涉及文件或模块：GIF 播放组件、可视区域检测、App 生命周期
  - 状态：待处理
  - 验收标准：同时活动 GIF 不超过配置值；离屏和高速滚动时暂停；进入后台停止；内存警告时释放动画帧；相同 URL 不重复下载；超大 GIF 支持首帧占位和点击播放。

- [ ] R-306 保持 NGA 图片请求 Header、Cookie 与非 NGA 请求隔离
  - 优先级：高
  - 涉及文件或模块：NGA 图片请求、缓存和 SDWebImage Loader/Context 配置
  - 状态：待处理
  - 验收标准：可信 NGA 图片继续携带必要 Referer、User-Agent 和 Cookie；非 NGA 请求不携带站点专属信息；登录图、静态图、GIF 和打开原图均无回归。

### P2：详情页状态与重绘范围

- [ ] R-307 抽离详情页滚动状态与 GIF 播放协调器
  - 优先级：中
  - 涉及文件或模块：`ThreadDetailView`、新增 `ThreadDetailScrollState`、`InlineGIFPlaybackCoordinator`
  - 状态：待处理
  - 验收标准：滚动状态和媒体播放策略具有单一所有者；View 只负责展示和事件转发；现有分页、筛选、倒序与回复行为不回归。

- [ ] R-308 缩小活动 GIF 状态传播和 SwiftUI 重绘范围
  - 优先级：中
  - 涉及文件或模块：`ThreadDetailHeaderSection`、`ThreadDetailReplySection`、媒体节点
  - 状态：待处理
  - 验收标准：媒体节点只接收自己的播放许可或通过协调器查询；同一媒体 ID 稳定；活动 GIF 切换时不触发正文和回复区域大范围重复解析；滚动指标较基线改善。

### P3：真机功能与体验整改

- [ ] R-309 精简详情页底部常驻操作并整理更多菜单
  - 优先级：中
  - 涉及文件或模块：`ThreadDetailActionBar`、详情页菜单
  - 状态：待处理
  - 验收标准：底部常驻操作聚焦回复、收藏和更多；只看楼主、正倒序、刷新、长图等进入更多菜单；关键操作不增加明显点击成本。

- [ ] R-310 增加 GIF 自动播放与同时播放数量设置
  - 优先级：中
  - 涉及文件或模块：阅读设置、GIF 播放协调器、持久化
  - 状态：待处理
  - 验收标准：支持始终播放、仅 Wi-Fi、点击播放和从不播放；可配置同时播放数量；设置持久化并即时生效；低电量模式可自动降低播放数量。

- [ ] R-311 完善详情、登录和媒体失败的就地恢复入口
  - 优先级：中
  - 涉及文件或模块：详情错误卡片、认证流程、图片/GIF 失败占位
  - 状态：待处理
  - 验收标准：详情加载失败可重新加载；登录失效可重新登录；图片/GIF 失败可重试和打开原图；恢复后正常内容不重复。

- [ ] R-312 稳定图片占位尺寸并保存帖子阅读会话状态
  - 优先级：中
  - 涉及文件或模块：富文本图片布局、阅读位置与帖子会话缓存
  - 状态：待处理
  - 验收标准：图片加载前按宽高比或统一规则预留空间；加载后页面不明显跳动；进入图片预览、回复页或切后台返回后保留阅读位置、页码、只看楼主和正倒序状态。

- [ ] R-313 评估区分“回到帖子顶部”和“回到当前页顶部”
  - 优先级：低
  - 涉及文件或模块：详情浮动控件、分页交互
  - 状态：待确认
  - 验收标准：通过真机使用验证是否需要两个动作或长按菜单；交互含义清楚；不与现有页码选择器和返回顶部行为冲突。

## 测试覆盖建设

- [x] T-001 帖子详情连续回顶 Mock UI Test
  - 优先级：高
  - 涉及文件或模块：`ForumHubUITests/ForumHubUITests.swift`、`UITEST_PAGED_THREAD`
  - 状态：已于真机通过；连续两次“下滑至第 2 页 → 点击回顶”均返回第 1 页。
  - 验收标准：连续两次“下滑至第 2 页 → 点击回顶”均回到第 1 页；控件使用稳定无障碍标识。

- [x] T-002 GIF 播放协调器单元测试
  - 优先级：高
  - 涉及文件或模块：`InlineGIFPlaybackCoordinator`、`InlineGIFPlaybackCoordinatorTests`
  - 状态：已于真机 `ForumHubTests` 完整运行并通过
  - 验收标准：只选择视口附近候选；按距视口中心排序；不超过配置上限；上限为 0 时不播放。

- [x] T-003 Search、Feed、Detail 请求代次和取消回归测试
  - 优先级：高
  - 涉及文件或模块：`RequestGenerationTests`、对应 ViewModel/LoadController
  - 状态：已于真机 `ForumHubTests` 完整运行并通过
  - 验收标准：慢请求被取消或晚到时不覆盖后发请求结果；加载状态最终复位；不显示取消错误。

- [x] T-004 NGA 图片 Header 与域名隔离测试
  - 优先级：高
  - 涉及文件或模块：`NGAImageLoader`、`NGAImageRequestTests`
  - 状态：已于真机 `ForumHubTests` 完整运行并通过
  - 验收标准：可信 NGA 域名携带 Referer 和 User-Agent；非 NGA 域名不携带站点专属 Header 或 Cookie 策略。

- [x] T-005 登录过期与恢复状态测试
  - 优先级：中
  - 涉及文件或模块：`NGALoginState`、`AuthSessionDescriptor`
  - 状态：已于真机 `ForumHubTests` 完整运行并通过
  - 验收标准：Guest UID 识别为未登录；有效 UID/CID 恢复为已连接；账户摘要状态同步正确。

- [x] T-006 LINUX DO 解析与认证测试
  - 优先级：中
  - 涉及文件或模块：`LinuxDoSessionResponseParser`、`LinuxDoDiscourseParser`
  - 状态：已于真机 `ForumHubTests` 完整运行并通过
  - 验收标准：`current_user` 可解析；缺失账号识别为未登录；主题详情映射来源、楼主、回帖、频道与图片正文。

- [x] T-007 维护正式测试策略文档
  - 优先级：中
  - 涉及文件或模块：`docs/testing.md`
  - 状态：已完成，待后续测试运行结果补充
  - 验收标准：定义单元测试、Mock UI Test、只读真实会话 UI Test 的边界、执行方式、Fixture 规则和禁止写操作规则。
