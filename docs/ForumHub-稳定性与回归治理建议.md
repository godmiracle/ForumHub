# ForumHub 稳定性与回归治理建议

## 背景

ForumHub 目前已经从早期 Demo 进入多功能并行演进阶段，包含多数据源、帖子详情、分页、登录、收藏、回复、图片预览、GIF 播放、搜索、浏览历史等功能。

当前主要问题不是功能不足，而是功能增长速度已经超过测试、状态边界和回归治理能力，导致：

- 已有功能在改动后失效；
- 看似简单的 Bug 反复修复失败；
- 修改一个功能时意外影响其他模块；
- UI 状态、分页状态和异步任务之间相互干扰；
- 测试以解析和纯逻辑为主，真实交互覆盖不足。

本文档用于建立一套更稳定的开发与修复流程。

## 一、优先解决状态边界问题

### 1. 一个模块只能有一个主要状态所有者

当前帖子详情页同时涉及帖子加载、连续分页、当前页码、返回顶部、只看楼主、正序与倒序、收藏、回复、长图生成、GIF 播放和可视区域判断。

当这些状态都直接分布在 `ThreadDetailView` 内时，一个简单操作可能同时触发多套状态更新。

建议逐步调整为：

```text
ThreadDetailView
├── ThreadDetailViewModel
│   ├── 帖子数据
│   ├── 加载
│   ├── 回复
│   └── 收藏
├── ThreadDetailPaginationState
│   ├── 当前页
│   ├── 已加载页
│   └── 页码选择
├── ThreadDetailScrollState
│   ├── 滚动位置
│   ├── 返回顶部按钮
│   └── 当前可见区域
└── InlineMediaCoordinator
    ├── GIF 播放许可
    ├── 可视区域媒体
    └── 播放数量限制
```

### 2. View 只负责展示和事件转发

View 不应同时承担网络请求、状态推导、多任务取消、播放调度、分页合并和数据持久化。

理想流程：

```text
用户操作
↓
View 发送事件
↓
状态对象或 ViewModel 处理
↓
状态自然更新
↓
View 刷新
```

如果修复一个按钮需要同时修改三个以上 `@State`，应先检查状态边界是否有问题。

## 二、避免一次操作手动修改多个派生状态

一些状态本质上应该由其他状态推导，不应由多个入口反复手动修改。例如：

- `visiblePage` 应由滚动位置计算；
- `showsScrollToTopButton` 应由滚动距离决定；
- `isLoadingMore` 应由加载任务状态决定；
- 活动 GIF 集合应由视口和播放策略计算。

不推荐：

```swift
showsScrollToTopButton = false
visiblePage = 1
pendingPageSelection = 1
proxy.scrollTo(topAnchorID, anchor: .top)
```

推荐：

```swift
withAnimation {
    proxy.scrollTo(topAnchorID, anchor: .top)
}
```

随后由滚动监听自然更新其他状态。

原则：

> 用户动作只触发一个核心命令，其他状态由结果自然更新。

## 三、每个 Bug 先建立固定复现条件

不要只写“按钮没反应”，应记录为：

```text
前置条件：
- 使用 NGA 数据源；
- 打开一个至少 3 页的帖子；
- 已加载到第 3 页；
- 当前滚动到 40 楼附近；
- 页面中存在 GIF。

操作：
- 点击右下角返回顶部按钮。

预期：
- 1 秒内返回主楼；
- 当前页更新为第 1 页；
- 返回顶部按钮隐藏；
- 离屏 GIF 停止播放。

实际：
- 按钮消失；
- 页面没有移动；
- 页码可能提前变为第 1 页。
```

每个 Bug 都应记录前置条件、操作步骤、预期结果、实际结果、设备与系统版本、数据源、登录要求和复现概率。

## 四、每次 Bug 修复必须增加回归测试

建议建立硬性规则：

> 已经出现过的 Bug，修复时必须新增至少一条回归测试。

示例：

```text
返回顶部失效
→ 增加 UI Test

搜索键盘不收起
→ 增加 UI Test

分页重复回复
→ 增加单元测试

NGA 图片无法显示
→ 增加 Fixture 测试

旧请求覆盖新频道
→ 增加 ViewModel 并发测试

GIF 离屏仍播放
→ 增加媒体协调器单元测试
```

## 五、测试必须分层

### 1. 单元测试

适合 Parser、Mapper、URL 处理、分页合并、去重、排序、错误映射、持久化和播放调度策略。

特点：不启动完整 App、不依赖真实网络、执行速度快、每次提交都应运行。

### 2. ViewModel 测试

适合请求取消、generation 代次、旧响应丢弃、加载状态、错误恢复、搜索连续提交、数据源切换和页面退出取消任务。

必须覆盖典型竞态：

```text
请求 A 发出
请求 B 后发但先返回
请求 A 最后返回
最终页面只能保留请求 B 的结果
```

### 3. Mock UI Test

适合搜索提交、切换数据源、返回顶部、只看楼主、正倒序、页码选择、图片预览、错误状态和重试按钮。

要求固定数据、固定启动场景、不依赖真实网络、不依赖真实登录状态。

### 4. 真实接口集成测试

适合 NGA Cookie 恢复、V2EX Token、LINUX DO 登录、真实图片、Referer、Cookie、GIF、搜索接口和真实分页。

这类测试应手动运行、只读为主，不自动回复、删除收藏或登出。

### 5. 性能测试

适合 GIF 密集帖子、超长帖子、长图生成、启动耗时、滚动帧率、内存峰值、CPU 占用和能耗。

性能问题不能只靠普通单元测试判断，需要 Instruments、固定真实帖子、固定设备、固定操作路径和优化前后对比。

## 六、不要让默认 UI Test 依赖真实网络

真实接口会引入网络延迟、Cookie 失效、接口限流、数据内容变化、服务端异常和测试结果不稳定。

建议建立统一 UI Test 模式：

```swift
enum UITestScenario: String {
    case defaultFeed
    case search
    case sourceSwitch
    case pagedThread
    case scrollToTop
    case mediaHeavyThread
    case loadingError
}
```

启动参数示例：

```swift
app.launchArguments += [
    "UITEST_MODE",
    "UITEST_SCENARIO_SCROLL_TO_TOP"
]
```

App 根据场景加载固定 Mock 数据。

## 七、一个提交只解决一个问题

不要在同一个提交中同时修复返回顶部、修改分页、替换 GIF 组件、重构 ViewModel 和调整详情 UI。

推荐提交顺序：

```text
test: add scroll-to-top regression test
fix: stabilize thread detail scroll-to-top
refactor: extract thread detail scroll state
perf: pause offscreen GIF playback
```

每个提交应目标单一、可独立验证、可独立回退、不包含无关格式化、不修改无关文件。

## 八、Bug 修复与重构分开

正确流程：

```text
1. 固定复现条件
2. 新增失败测试
3. 最小修改修复
4. 测试通过
5. 真机验证
6. 单独提交
7. 再决定是否重构
```

不要在修 Bug 时顺便进行大范围重构。

## 九、限制 AI 修改范围

每次交给 AI 修改代码时，应明确：

```text
本次目标：
- 修复帖子详情返回顶部按钮。

允许修改：
- ThreadDetailView.swift
- ThreadDetailFloatingControls.swift
- 对应测试文件

禁止修改：
- Repository
- Domain Model
- 登录模块
- 搜索模块
- 其他页面
- 无关命名
- 全项目格式化
```

如果一个简单 Bug 需要修改超过 4 至 5 个文件，应先检查状态边界、职责耦合或方案是否过度设计。

## 十、建立核心功能回归清单

建议新增：

```text
docs/regression-checklist.md
```

### 首页与热门

- [ ] NGA 首页可加载；
- [ ] 热门可加载；
- [ ] 左右切换频道正常；
- [ ] 频道状态互不污染；
- [ ] 再次点击当前 Tab 返回顶部；
- [ ] 搜索提交正常；
- [ ] 搜索键盘可收起；
- [ ] 下拉刷新正常；
- [ ] 加载更多不重复。

### 帖子详情

- [ ] 主楼正常显示；
- [ ] 主楼图片正常；
- [ ] GIF 正常播放；
- [ ] 连续分页正常；
- [ ] 分页不重复回复；
- [ ] 页码选择正常；
- [ ] 返回顶部正常；
- [ ] 只看楼主正常；
- [ ] 正倒序正常；
- [ ] 收藏正常；
- [ ] 回复入口正常；
- [ ] 图片预览正常；
- [ ] 返回页面后阅读位置保持；
- [ ] 加载失败可重试。

### 数据源

- [ ] NGA 切换正常；
- [ ] V2EX 切换正常；
- [ ] LINUX DO 切换正常；
- [ ] 不同数据源数据不串台；
- [ ] 不同数据源相同帖子 ID 不冲突。

### 账户

- [ ] NGA 登录恢复；
- [ ] V2EX Token 恢复；
- [ ] LINUX DO Cookie 恢复；
- [ ] 登录过期提示正确；
- [ ] 登出正常；
- [ ] 非目标域名不携带站点 Cookie。

### 本地持久化

- [ ] 收藏可恢复；
- [ ] 屏蔽用户可恢复；
- [ ] 浏览历史可恢复；
- [ ] 频道订阅可恢复；
- [ ] 数据迁移正常。

## 十一、对复杂流程增加结构化日志

建议 Debug 模式增加日志。

### 滚动日志

```swift
logger.debug("scrollToTop tapped")
logger.debug("visiblePage before: \(visiblePage)")
logger.debug("topAnchor available")
logger.debug("scroll offset: \(offset)")
```

### 请求日志

记录请求类型、generation、数据源、频道 ID、帖子 ID、开始时间、结束时间、是否取消、是否被丢弃和是否覆盖状态。

### GIF 日志

记录媒体 ID、URL、进入视口、离开视口、开始播放、停止播放、缓存命中、解码开始和解码结束。

## 十二、拆分过大的测试文件和页面文件

建议测试拆分为：

```text
ForumHubTests/
├── ForumErrorTests.swift
├── NGAParserTests.swift
├── NGAImageTests.swift
├── NGAThreadMergeTests.swift
├── ThreadPaginationTests.swift
├── PersistenceTests.swift
├── FeedPolicyTests.swift
├── SearchViewModelTests.swift
├── ThreadDetailViewModelTests.swift
├── V2EXTests.swift
├── LinuxDoTests.swift
├── MediaPlaybackTests.swift
└── Fixtures/
```

详情模块建议拆分为：

```text
ThreadDetail/
├── ThreadDetailView.swift
├── ThreadDetailViewModel.swift
├── ThreadDetailScrollState.swift
├── ThreadDetailPaginationState.swift
├── InlineGIFPlaybackCoordinator.swift
├── ThreadDetailHeaderSection.swift
├── ThreadDetailReplySection.swift
├── ThreadDetailActionBar.swift
└── ThreadDetailFloatingControls.swift
```

拆分目标不是追求形式，而是降低每次修改需要理解的范围。

## 十三、建立明确的完成标准

功能或 Bug 不能以“代码已经写完”作为完成标准。

建议统一 Definition of Done：

```text
代码修改完成
+ 单元测试通过
+ UI Test 通过
+ 真机关键路径验证
+ 没有新增警告
+ git diff 无无关修改
+ 文档和 Todo 已同步
```

例如返回顶部修复必须验证：

- [ ] 第一页正常；
- [ ] 加载多页后正常；
- [ ] 只看楼主后正常；
- [ ] 倒序后正常；
- [ ] GIF 播放中正常；
- [ ] 下拉刷新后正常；
- [ ] 连续点击正常；
- [ ] UI Test 通过；
- [ ] 真机验证通过。

未满足全部标准时，只能标记：

```text
状态：已修改，等待验证
```

不能标记完成。

## 十四、推荐当前实施顺序

### 第一阶段：停止继续扩展新功能

优先完成测试环境 Mock 化、核心流程回归、返回顶部修复、GIF 性能基线、请求竞态测试和登录恢复测试。

### 第二阶段：补齐文档

新增：

```text
docs/testing.md
docs/regression-checklist.md
docs/debugging.md
```

### 第三阶段：拆分高风险状态

优先拆分：

```text
ThreadDetailScrollState
InlineGIFPlaybackCoordinator
SearchThreadsViewModel
```

### 第四阶段：建立提交门槛

每次提交前执行：

```text
1. 单元测试
2. 相关 UI Test
3. 核心回归清单
4. git diff 检查
5. 真机验证
```

## 十五、当前最优先的三件事

### 1. 补正式测试文档

新增 `docs/testing.md`，明确测试分层、Fixture 使用方式、UI Test 启动参数、Mock 场景、真机测试、性能测试和测试运行命令。

### 2. 为当前已知问题建立固定测试

优先增加：

```text
返回顶部 UI Test
GIF 播放协调器单元测试
搜索请求竞态测试
数据源切换请求取消测试
```

### 3. 暂停增加功能，集中做稳定性治理

建议本轮目标：

```text
状态边界整理
测试环境 Mock 化
核心流程回归
异步请求治理
GIF 性能优化
```

## 总结

ForumHub 当前的问题并不是缺少功能，而是：

```text
功能增长速度
>
状态治理速度
+
测试建设速度
+
回归验证速度
```

最有效的改进方式是：

1. 每个状态只有一个主要所有者；
2. 派生状态不手动多处修改；
3. 每个 Bug 先固定复现；
4. 每次修复必须增加回归测试；
5. Mock UI Test 与真实接口测试分开；
6. 一个提交只处理一个问题；
7. Bug 修复和重构分开；
8. 建立核心功能回归清单；
9. 使用结构化日志定位复杂问题；
10. 未完成验证的改动不得标记完成。
