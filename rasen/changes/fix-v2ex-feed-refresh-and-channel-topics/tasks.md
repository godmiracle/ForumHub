## 1. V2EX 节点主题解析

- [x] 1.1 在 `ForumHubTests/Fixtures` 增加脱敏 V2EX 普通节点页 Fixture，覆盖无 `topic-link` class、属性顺序变化、干扰链接和下一页标记，并在 Fixture 文档登记来源与用途
- [x] 1.2 先补充 `V2EXRecentPageParser` 失败回归测试，断言 `qna`/`all4all` 真实形状可提取主题 ID、标题、作者、回复数与分页状态，空节点不误报主题
- [x] 1.3 最小修改 `V2EXRecentPageParser`，在主题 item 内按 `/t/<numeric-id>` 语义解析 anchor，解除对 CSS class 和属性顺序的依赖，保持 `/go/<nativeKey>?p=<page>` 请求与公共匿名浏览不变
- [x] 1.4 补充 Repository 请求测试，确认普通节点使用正确 native key/page URL，且无需 Token 或 Web Cookie

## 2. 信息流下拉刷新

- [x] 2.1 为 `ForumFeedContent` 注入 async `onRefresh`，在内部实际 `ScrollView` 应用 `.refreshable`，由 `ContentView` 传入 `ForumViewModel.reload()` 并移除外层重复 modifier
- [x] 2.2 在固定 Mock UI Test 场景增加下拉刷新回归，断言 Home/Hot Feed 的下拉手势触发并完成刷新，同时保留刷新按钮、纵向滚动、主题点击与横向频道切换
- [x] 2.3 运行现有请求 generation/cancellation 聚焦测试，确认刷新失败或被新上下文取代时不会过期回写或卡住加载状态
- [x] 2.4 先增加恢复 V2EX 来源的初始化单测，断言首帧 `forum`、默认频道和 source 一致；增加 V2EX “最热”短列表 UI 场景，验证修复前下拉是否稳定不触发
- [x] 2.5 最小修复默认初始化状态源；仅在 UI 回归稳定复现时为真实 Feed `ScrollView` 强制纵向 bounce，并保持系统 `.refreshable` 与现有 generation 接缝
- [x] 2.6 按 PC “更多新主题”真实 `/recent` 目标为左上角 V2EX “最热”增加滚动续载，保留首屏官方 Top 10、匿名请求、generation 与主题 ID 去重；将“最热”保持为虚拟聚合入口并保留每条主题的真实节点标签；增加真机 UI 回归
- [x] 2.7 修复 Home `.forum` 首屏与分页无条件覆盖 Repository 主题节点的问题；当前频道仅作为缺失元数据 fallback，并以单测和真机 UI 断言左上角“最热”与底栏“热门”保持相同真实节点标签

## 3. 验证与文档

- [x] 3.1 运行 V2EX parser/Repository、Feed presentation、request generation 聚焦测试并记录结果
- [x] 3.2 在已连接 iOS 真机运行完整 `ForumHubTests` 与 Debug 构建；人工验证 V2EX “问与答”“二手交易”可显示主题、下拉刷新可用、横滑频道不回归
- [x] 3.3 检查 `git diff` 与敏感信息，按实际验证结果更新 `docs/todo.md`，并将用户可见修复写入 `docs/changelog.md`；仅在所有验收通过后勾选待办
- [x] 3.4 重跑 V2EX hot 短列表下拉、启动高亮、滚动续载、完整 `ForumHubTests` 与 Debug 真机构建，安装最终包并按真实结果更新文档
