# ForumHub 第三轮 Code Review

## 审查摘要

- 审查范围：帖子详情滚动、GIF/图片渲染、真机界面与功能体验。
- 重点问题：帖子详情返回顶部按钮失效；GIF 密集帖子滚动卡顿、CPU 与内存占用偏高。
- 已确认问题：`ThreadDetailView` 将正文内容作为 View ID，正文变化会导致 Header 整体重建；详情页同时维护滚动、分页和 GIF 播放状态。
- 高概率问题：返回顶部前同步修改分页状态，可能导致 ScrollView 布局重算与 `scrollTo` 时序冲突；当前 GIF 播放数量限制未必等同于解码和内存限制。
- 本次直接修复：无，仅形成 Review 与待办。
- 构建状态：未执行。
- 测试状态：未执行。
- 真机验证：依据仓库真机截图和已记录的性能数据提出整改建议，仍需在真实 GIF 密集帖子上回归。

## 推荐修复与优化顺序

### P0：先恢复核心交互

1. 修复帖子详情返回顶部按钮。
2. 删除正文字符串作为 Header View ID 的实现，改为稳定 ID 或不设置 ID。
3. 为返回顶部补充可重复的真机验证和 UI Test。

### P1：建立 GIF 性能基线并替换播放链路

1. 使用固定的 GIF 密集帖子记录 CPU、内存、滚动帧率和峰值能耗。
2. 将静态图片与 GIF/APNG 分流，避免静态图片进入动画解码链路。
3. 评估并接入 `SDWebImage` 动画图片模块，优先使用可显式控制生命周期的 `SDAnimatedImageView` 包装。
4. 保留 NGA 图片请求所需的可信域名、Referer、User-Agent 与 Cookie 策略，避免更换图片库后出现图片加载回归。
5. 实现可视区附近播放、离屏暂停、高速滚动暂停、进入后台停止和内存警告释放。
6. 对超大 GIF 默认展示首帧并允许点击播放。

### P2：降低详情页状态耦合

1. 将滚动状态抽离为独立的 `ThreadDetailScrollState`。
2. 将 GIF 候选排序、最大播放数和活动集合抽离为 `InlineGIFPlaybackCoordinator`。
3. 避免把完整 `activeInlineGIFPlaybackIDs` 集合传递给整个 Header 和回复 Section，改为向单个媒体节点传递播放许可，或通过环境协调器查询。
4. 确保媒体节点 ID 稳定，不在正文重复解析时重新生成 UUID。

### P3：真机功能与界面整改

1. 精简详情页底部常驻操作，只保留回复、收藏和更多；只看楼主、倒序、刷新、长图等放入更多菜单。
2. 在阅读设置中增加 GIF 自动播放策略和同时播放数量。
3. 为图片加载失败、登录失效和详情加载失败增加明确的重试入口。
4. 为图片预留稳定宽高比，减少加载后的页面跳动和可见页误判。
5. 评估区分“回到帖子顶部”和“回到当前页顶部”。
6. 保存帖子阅读位置、页码、只看楼主和正倒序状态，避免进入图片预览或切后台后丢失。

## 问题详情

### R-301：返回顶部前同步修改分页状态，可能使滚动命令失效

- 优先级：高
- 可信度：高概率
- 类型：功能正确性、SwiftUI 状态时序
- 涉及文件：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
- 证据：`onScrollToTop` 在 `proxy.scrollTo(topAnchorID, anchor: .top)` 前同步设置 `showsScrollToTopButton = false`、`visiblePage = 1` 和 `pendingPageSelection = 1`。
- 影响：按钮点击后可能先消失，但页面未回到顶部；分页锚点和页码状态也可能提前变化。
- 建议：返回顶部操作只执行 `scrollTo`，页码状态由滚动监听自然更新；如必须更新状态，应在滚动后的下一次 MainActor 周期执行。
- 验收标准：
  - 滚动超过两屏后点击按钮可以稳定回到主楼；
  - 加载多页、只看楼主、倒序和 GIF 播放中均可正常回顶；
  - 快速连续点击不会造成页码错乱或多个异步任务；
  - 增加稳定的 `accessibilityIdentifier` 和 UI Test。

### R-302：顶部锚点与滚动目标需要稳定化

- 优先级：中
- 可信度：高概率
- 类型：SwiftUI 滚动稳定性
- 涉及文件：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
- 证据：顶部目标是高度为 1 的透明 View，并使用字符串 ID。
- 影响：在分页插入、图片高度变化和刷新重建时，滚动目标可能处于布局切换阶段。
- 建议：使用稳定、强类型的锚点 ID，并保持锚点节点不随正文或分页数据重建。
- 验收标准：刷新、分页插入和图片高度变化后锚点仍可被定位；不存在重复 ID。

### R-303：正文字符串作为 Header View ID 导致无必要整体重建

- 优先级：高
- 可信度：已确认
- 类型：性能、状态稳定性
- 涉及文件：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`
- 证据：`ThreadDetailHeaderSection(...).id(detailThread.body)`。
- 影响：API/Web 补全、正文修正或图片 URL 变化后，SwiftUI 将 Header 视为新节点；大量媒体内容会被重新创建，可能影响滚动锚点和 GIF 生命周期。
- 建议：删除该 `.id`，或改为基于帖子 ID 的稳定标识；需要局部刷新时通过模型状态更新，而不是更换整个 View 身份。
- 验收标准：正文补全后内容能够更新；Header 不因正文字符串变化整体重建；图片和 GIF 不重复请求或丢失播放状态。

### R-304：GIF 播放限流没有覆盖下载、解码和内存生命周期

- 优先级：高
- 可信度：高概率
- 类型：性能、内存、能耗
- 涉及模块：帖子详情富文本、图片加载与缓存链路
- 证据：详情页已有 `maximumSimultaneousInlineGIFs` 和活动 GIF 集合，但现有性能记录仍显示 GIF 密集帖子 CPU、内存和能耗过高。
- 影响：即使只有少量 GIF 正在播放，其他 GIF 仍可能被完整下载、解码或持有动画帧；快速滚动时可能反复创建动画对象。
- 建议：静态图片与动画图片分流；使用支持增量解码和缓冲控制的动画图片组件；离屏停止并释放动画帧；高速滚动和后台状态停止全部动画。
- 验收标准：
  - 同时活动 GIF 数不超过配置值；
  - 离屏 GIF 停止计时与动画解码；
  - 进入后台后无 GIF 继续播放；
  - 内存警告后动画帧缓存可以释放；
  - 相同 URL 不重复下载；
  - NGA 图片 Header/Cookie 行为不回归。

### R-305：详情页滚动、分页和媒体状态仍存在耦合

- 优先级：中
- 可信度：已确认
- 类型：架构、可维护性
- 涉及文件：`ForumHub/Features/ThreadDetail/ThreadDetailView.swift`、`ForumHub/Features/ThreadDetail/*`
- 证据：View 内仍直接维护滚动偏移、视口高度、当前页、浮动按钮和活动 GIF 集合等状态。
- 影响：一个媒体或分页状态变化可能扩大 SwiftUI 重算范围，并增加滚动 Bug 的定位难度。
- 建议：优先抽离 `ThreadDetailScrollState` 和 `InlineGIFPlaybackCoordinator`，不进行与问题无关的大规模重构。
- 验收标准：滚动状态和媒体播放策略具有单一所有者；View 只负责展示及事件转发；分页行为和现有交互不回归。

### R-306：活动 GIF 集合向大范围视图传播，可能扩大重绘

- 优先级：中
- 可信度：高概率
- 类型：SwiftUI 性能
- 涉及模块：`ThreadDetailHeaderSection`、`ThreadDetailReplySection`、媒体节点
- 证据：Header 和回复 Section 接收完整的 `activeInlineGIFPlaybackIDs`。
- 影响：任一 GIF 进入或离开视口都会改变整个 Set，可能使大范围富文本区域重新求值。
- 建议：媒体节点只接收自己的 `isPlaybackAllowed`，或使用环境协调器按稳定 ID 查询；保证内容解析不会为同一媒体反复生成新 UUID。
- 验收标准：活动 GIF 切换时只有相关媒体节点更新；正文和回复区域不发生大范围重复解析；滚动帧率较基线改善。

### R-307：详情页错误与媒体失败状态缺少就地恢复入口

- 优先级：中
- 可信度：高概率
- 类型：功能体验
- 涉及模块：详情错误卡片、图片/GIF 组件、登录失效处理
- 影响：用户可能只能依靠下拉刷新或重新进入页面恢复，图片失败时容易出现空白区域。
- 建议：详情错误卡片增加重新加载；登录失效增加重新登录；图片/GIF 失败显示失败占位、点击重试和打开原图。
- 验收标准：网络失败、登录失效和媒体失败均有明确恢复入口；重试成功后恢复正常内容；不泄露底层错误细节。

## SDWebImage 接入判断

可以接入，推荐使用 `SDWebImage` 的动画图片能力处理 GIF/APNG，但不应把所有图片无差别替换为动画组件。建议静态图片继续走轻量加载链路，动画图片使用 `SDAnimatedImageView` 或经过验证的 SwiftUI 包装，并明确处理创建、更新、暂停、取消请求和销毁。

接入不会直接影响收藏、回复、分页、登录等业务，但可能影响图片请求、缓存和身份验证，因此必须复用当前 NGA 可信域名与 Header/Cookie 策略。依赖接入前后都应使用同一真实帖子做性能和功能对比。

## 建议测试

- `testScrollToTopAfterLoadingMultiplePages`
- `testScrollToTopWhileGIFIsPlaying`
- `testScrollToTopAfterToggleReverseOrder`
- `testScrollToTopAfterFilteringAuthor`
- `testOnlyMaximumAllowedGIFsArePlaying`
- `testGIFStopsAfterLeavingViewport`
- `testGIFStopsWhenSceneEntersBackground`
- `testLargeGIFDefaultsToPosterMode`
- `testNGAImageHeadersRemainIsolatedAfterSDWebImageMigration`

## 风险与限制

- 本次未执行 Xcode 构建、自动化测试和 Instruments 测量。
- 返回顶部根因需要在真机上结合当前点击区域、布局重算和滚动监听进一步确认。
- SDWebImage 是否最终优于当前实现，应以固定真实帖子的 CPU、内存、帧率和能耗对比结果决定。

`REVIEW:v1`
