# Verification Report: add-nga-and-v2ex-automatic-check-in-on-app-open

验证日期：2026-07-23

> 权限降级：`rasen status` 返回的外部 `workDir` 不在当前可写根目录，因此报告保存在 change 根目录。

## Summary

| Dimension | Status |
| --- | --- |
| Completeness | 20/24 tasks；4 项门禁保持未完成（1.2、1.3、1.5、6.4） |
| Correctness | 默认关闭、NGA production 写入 fail-closed、V2EX observed Web 流程严格解锁、服务端权威、会话 generation 隔离、响应来源校验和 UI Test 网络隔离均成立 |
| Coherence | proposal/design/spec/tasks 已统一为“按来源由真实证据独立解除 production 门禁；未知结构继续 fail closed” |

VERIFY VERDICT: BLOCKED — Blocker:2 Major:0 Minor:0 Trivial:0

## 已确认的安全性质

- NGA production policy 的未签到/成功 code 集合为空且 `allowsProductionWrite == false`；当前 production NGA 写请求不可达。
- V2EX production policy 只确认 `/mission/daily/redeem` 且 `allowsProductionWrite == true`；只有真实观测的唯一领取 `input`、有限 `location.href = '<URL>';` onclick、严格同源和唯一非空 `once` 能到达领取请求。
- 两来源偏好独立且默认关闭；LINUX DO 永远不具备自动签到资格。
- V2EX 只接受有效 Web Session，Token-only 不会加载每日奖励页面。
- V2EX 每日页解析要求 HTTPS、严格 `www.v2ex.com`、exact `/mission/daily` 和 HTML MIME；动作 URL 还要求经证据确认的 path、唯一且非空的 `once`。
- 冷启动跳过只依赖进程内、绑定 session generation 的完成缓存；持久化状态仅用于展示，不再代替服务端查询。
- 会话变化会递增 generation、取消旧任务、清除节流/完成缓存；来源服务在读后写前和结果记录前检查 cancellation/generation。
- UI Test 场景在启动与前台入口均提前返回，不访问真实签到端点。
- Fixture 明确区分脱敏观测样本和 synthetic 样本；V2EX 子门禁只由 2026-07-23 observed-sanitized onclick Fixture 解锁，historical/synthetic `href` 继续被拒绝。

## 2026-07-23 真实采样增量独立复核

### V2EX Chrome 真实领取链已解除来源子门禁

- 在用户授权的现有已登录 Chrome 标签中，初始最终页面为 HTTPS、严格 `www.v2ex.com`、精确 `/mission/daily` 和 `text/html`；页面存在唯一 `input onclick` 领取控件，安全文案为“领取 … 铜币”。
- 动态动作在内存中验证为 HTTPS、严格 `www.v2ex.com`、精确 `/mission/daily/redeem`，query 只有一个唯一非空 `once`；动作只触发一次，真实值未输出、保存或写入仓库。
- 动作后最终回到精确 `/mission/daily` 并出现“每日登录奖励已领取”，领取控件为 0；随后独立再次访问仍得到同一已领取语义和 0 个领取控件。
- 新 Fixture 保留 observed `input onclick` 结构，但奖励数量和 `once` 均替换为不可重放占位值。parser 只接受有限 `location.href = '<URL>';`，不会执行任意 JavaScript。
- 未取得真实失效会话跳转与完整 HTTP 3xx 链，因此 task 1.3 和整体验收继续未完成；这不否定已完成链对 V2EX action path、动作形状和成功判据的来源子门禁授权。

### NGA 真机采样未形成可写判据

- DEBUG-only 一次性探针只取得官方 HTTPS `nuke.php` 的 HTTP 200、`text/javascript`、服务端 `Date`，以及相邻读取中的精确 JSON `null` 与顶层 `data/time` 结构。
- 当前证据不能稳定解释 `last_day`、`now_day` 与服务端当前签到周期的编码关系；本轮从未执行 `check_in` POST，也没有成功响应或写后二次状态。
- 因此 tasks 1.2、1.5、6.4 保持未完成是正确的；NGA production 未签到/成功 code 集合不得从本轮样本推断。

### 探针清理与 production policy

- `ForumHub/ForumHubApp.swift` 当前仅保留正常 App 入口且没有工作区 diff；仓库范围搜索未发现本轮一次性采样探针、采样启动参数或 DEBUG 自动执行残留。
- NGA production policy 仍为两个空 code 集合与 `allowsProductionWrite == false`。V2EX production policy 已校准为 `confirmedActionPath == "/mission/daily/redeem"` 与 `allowsProductionWrite == true`，但解析和 URL 校验任一未知即停止写入。
- `tasks.md` 的 1.2、1.3、1.5、6.4 与 `docs/todo.md` 的 SD-0.6 均保持未完成，和本轮只取得局部只读证据的事实一致；文档没有把“已领取页面”或 HTTP 200 夸大为完整真实签到验收。

## Blocker

### V-002：剩余真实响应与整体验收门禁尚未完成

- 可信度：已确认。
- 证据：tasks 1.2、1.3、1.5 仍未勾选；截至 2026-07-23，V2EX 可领取→一次动作→成功→再次访问链已完成并独立解锁，但真实失效会话/完整重定向链仍缺失；NGA 仍只有未解释的只读响应形状且 production 写入禁止。
- 影响：V2EX observed Web 流程已具备生产能力，但不能把整项描述为 NGA/V2EX 全场景验收完成。
- 后续：补齐 NGA 未签到→成功→二次状态，以及 V2EX 真实失效会话和完整重定向证据。
- 验收标准：剩余真实 Fixture 支持全部来源判据，未知结构继续 fail closed，NGA production 写入只由真实证据解锁。

### V-003：真机安装成功，但真实账号业务场景回归尚未完成

- 可信度：已确认。
- 证据：用户于 2026-07-22 手动安装到真实设备成功；已有签名 Debug build 成功证据。NGA/V2EX 未签到、已签到、重复前台、离线和会话失效路径尚未逐项完成真实账号验证。
- 影响：安装/启动成功证明包可构建、签名和安装，但不能证明签到状态机、节流、失败降级和会话边界在真实服务端成立。
- 后续：保留 task 6.4 未完成；待真实状态窗口或第二账号可用时逐项执行并记录结果。
- 验收标准：两来源真实场景完成，且没有启动弹窗、会话误过期、重复写入或跨账号状态复用。

## Resolved Findings（Round 1 独立复审）

### V-001：自动化测试失败 — RESOLVED

- Fixture helper 已兼容 `Fixtures` 子目录与测试 bundle 根目录。
- 偏好测试已改为只验证本功能固定 key/value schema，不再扫描整个 UserDefaults 域。
- 独立最终验证证据：聚焦自动签到测试 20 项通过，完整 `ForumHubTests` 215 项全部通过。

### V-004：持久化完成状态跨冷启动/账号复用 — RESOLVED

- `DailyCheckInCoordinator` 使用进程内 `completionCache`，并绑定每来源 `sessionGenerations`；不再根据持久化展示状态跳过冷启动服务端查询。
- `V2EXAuthStore.webSessionGeneration` 在 restore/sync/refresh/logout 后递增，覆盖有效→有效的 Web Session 替换。
- `ContentView` 显式处理 generation，清除旧会话节流、完成缓存和展示状态。
- 测试覆盖冷启动仍查询服务端，以及显式 session change 后重新查询。

### V-005：旧会话任务未取消/隔离 — RESOLVED

- 每来源运行记录保存 generation 与 Task；session change 会先递增 generation 并取消旧任务。
- NGA/V2EX 服务均在状态读取后、写动作前及写后检查 cancellation 和 `shouldContinue`，且不再把 `CancellationError` 转换为普通失败。
- 协调器只在 generation 仍匹配时记录结果；旧任务的 defer 也不会删除新 generation 的任务。
- 测试将切换点放在“状态已读、动作尚未执行”，确认旧任务不动作、不记录，并确认替换任务不并发。

### V-006：V2EX final URL/content type 未校验 — RESOLVED

- 每日页仅在 HTTPS、严格 `www.v2ex.com`、exact `/mission/daily` 且 MIME 为 `text/html` 或 `application/xhtml+xml` 时参与分类。
- 明确的 HTTPS `www.v2ex.com/signin` 仍分类为会话失效；其他来源、path、scheme 或 MIME 均为 unknown。
- 测试覆盖跨域、HTTP、同域错误 path、非 HTML，以及 service 不到达动作请求。

### V-007：spec 与 design/tasks 矛盾 — RESOLVED

- spec 已明确允许 dormant、可注入、production 不可达的接缝和 synthetic 测试。
- spec 同时明确 synthetic 不能解除真实证据门禁；缺少真实未签到样本时 production 写操作必须不可达。

## Test Evidence

- 聚焦测试：
  - command: `env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project ForumHub.xcodeproj -scheme ForumHub -configuration Debug -destination 'platform=iOS,id=A67DE9B5-C985-51C3-83BE-FBC006C114A4' -only-testing:ForumHubTests/DailyCheckInParserTests -only-testing:ForumHubTests/DailyCheckInServiceTests test`
  - result: 2026-07-23 PASS，20 tests / 2 suites；覆盖 production policy 仅解锁 observed V2EX、NGA 继续关闭，以及 observed onclick 正例、historical `href` 拒绝、恶意 onclick、多参数、跨域、多个候选、未知结构和一次动作后二次确认。
- 完整单元测试（独立最终验证）：
  - command: `env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project ForumHub.xcodeproj -scheme ForumHub -configuration Debug -destination 'platform=iOS,id=A67DE9B5-C985-51C3-83BE-FBC006C114A4' -only-testing:ForumHubTests test`
  - result: 2026-07-23 PASS；xcresult 摘要为 215/215 passed、0 failed、0 skipped。
- 独立真机 Debug build：
  - command: `env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project ForumHub.xcodeproj -scheme ForumHub -configuration Debug -destination 'platform=iOS,id=A67DE9B5-C985-51C3-83BE-FBC006C114A4' build`
  - result: 2026-07-23 `BUILD SUCCEEDED`。
- 真机安装：用户于 2026-07-22 手动安装成功。
- 2026-07-23 NGA 真机只读采样：DEBUG-only 探针复用现有 Cookie 会话，确认官方 HTTPS `nuke.php`、HTTP 200、`text/javascript` 与服务端 `Date`；相邻读取出现 JSON `null` 与 `data/time` 统计结构切换。因未能稳定证明 `last_day/now_day` 的周期编码语义，未执行 POST、无写后二次确认，探针随后从源码删除。
- 2026-07-27 NGA 真机 `app_api.php` 采样：用户确认授权账号处于未签到状态；DEBUG-only 探针复用现有 Cookie 会话，按本地 App API 文档依次请求 `get_stat`、至多一次 `check_in`、写后 `get_stat`。三次均为官方 HTTPS `/app_api.php`、HTTP 200、`text/json`、含服务端 `Date`，且均返回相同 `code/msg/result` 顶层结构、业务 `code=2`、数组型 `result` 和相同响应长度；没有成功或状态变化证据。随后只读复查结果不变。探针未输出原始正文或身份数据，已从源码删除，并已重新构建、安装无探针 Debug 包。
- 2026-07-23 V2EX Chrome 授权真实链：复用用户现有已登录标签，确认唯一 `input onclick` 领取控件和严格 `/mission/daily/redeem?once=<动态值>` 动作；只触发一次，随后及独立再次访问 `/mission/daily` 均精确确认已领取。未读取或保存 Cookie、账号、奖励数量或真实动态参数；缺失真实失效会话和完整 3xx 链。
- content tree fingerprint: `b2ee9ade7fcf9626e7f13890d35e8106ab05f992`。
- 独立最终验证开始前通过 `devicectl list devices` 确认目标真机为 `available (paired)`，随后重新运行完整测试与独立 Debug build；未以模拟器替代。
- `rasen validate add-nga-and-v2ex-automatic-check-in-on-app-open --strict --json`：PASS（1/1）。
- `git diff --check`：PASS。
- 敏感信息扫描：针对签到源码、测试、来源专属 Fixture、change artifacts 与本轮文档扫描可重放 Authorization/Bearer/Cookie/Token/UID/CID/用户名/余额和非占位动态 `once`；仅命中类型/字段说明与明确不可重放占位值，未发现真实凭证、账号标识、余额或可重放参数。

TEST EVIDENCE
- command: `env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project ForumHub.xcodeproj -scheme ForumHub -configuration Debug -destination 'platform=iOS,id=A67DE9B5-C985-51C3-83BE-FBC006C114A4' -only-testing:ForumHubTests test`
- result: pass
- tree: `b2ee9ade7fcf9626e7f13890d35e8106ab05f992`

## Final Assessment

修复后的安全接缝、并发隔离和自动化验证可以接受，V-001/V-004/V-005/V-006/V-007 已关闭。2026-07-23 V2EX 真实领取链已足以按严格 observed 结构解除该来源 production 子门禁；NGA 写入仍关闭。2026-07-27 的 `app_api.php` 真实调用返回稳定 `code=2`，没有完成签到，说明仍缺少请求合约条件，不能据此校准成功 code 或 production 端点。由于 V-002 与 V-003 仍覆盖 NGA 完整证据、V2EX 失效会话/完整重定向及整项人工场景回归，本变更不得被描述为“NGA/V2EX 全场景自动签到已完成”，也不得 ship/archive 或归档为完整交付。

VERIFY VERDICT: BLOCKED — Blocker:2 Major:0 Minor:0 Trivial:0
