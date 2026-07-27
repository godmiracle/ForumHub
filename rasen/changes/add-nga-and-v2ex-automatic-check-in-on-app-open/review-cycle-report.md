# Review Cycle Report: add-nga-and-v2ex-automatic-check-in-on-app-open

日期：2026-07-23  
轮次：2/3  
执行模式：独立 delta re-review  
状态：BLOCKED（真实证据门禁）

## Round 1

| Finding | 原级别 | Fixer 处理 | 独立确认 | 状态 |
| --- | --- | --- | --- | --- |
| V-001 聚焦测试失败 | Blocker | 修复 Fixture bundle 查找与 UserDefaults 测试边界；重跑真机聚焦 17 项及完整 `ForumHubTests` | 复查 helper、断言范围与 fixer 测试证据 | RESOLVED |
| V-002 真实响应/production policy 未校准 | Blocker | 保持 production 写入 fail-closed，等待真实服务端周期 | tasks 1.2/1.3/1.5 仍开放，production policy 仍禁写 | OPEN |
| V-003 真实账号场景未验证 | Blocker | 完成真机构建；用户手动安装成功 | 安装成功不等于未签到/已签到/重复前台/离线/会话失效回归 | OPEN |
| V-004 持久化状态跨冷启动/账号复用 | Blocker | 改为进程内 generation-bound 完成缓存；增加 Web Session generation | 复查 cold-start、true→true 替换调用链与测试 | RESOLVED |
| V-005 旧会话任务未取消/隔离 | Major | 每来源 Task+generation；服务写前/写后取消检查；旧结果禁止记录 | 复查 actor 时序、defer 清理和状态读后切换测试 | RESOLVED |
| V-006 V2EX final URL/content type 未校验 | Major | 严格校验 scheme/host/path/MIME 并补负例测试 | 复查 parser、service 传参和跨域/错误 path/非 HTML 覆盖 | RESOLVED |
| V-007 spec 与 design/tasks 矛盾 | Major | spec 明确 dormant 接缝与 synthetic evidence 边界 | 复查 spec 与 tasks/design 的 production 门禁一致 | RESOLVED |

本轮结果：原 4 Blocker / 3 Major 中，关闭 2 Blocker / 3 Major；保留 2 Blocker；未发现新 Blocker/Major。

## Round 2：2026-07-23 真实采样增量

| Finding | 新增证据 | 独立确认 | 状态 |
| --- | --- | --- | --- |
| V-002 真实响应/production policy 未校准 | V2EX Chrome 取得官方 `/mission/daily` HTML 的“今日已领取”安全语义；NGA 真机取得 HTTP 200、`text/javascript`、服务端 `Date`、JSON `null` 与未解释的 `data/time` 结构 | V2EX 没有可领取动作或成功链；NGA 从未执行 POST 且周期字段语义未证实；两来源 production policy 仍禁写 | OPEN |
| V-003 真实账号场景未验证 | 完成两来源局部只读采样 | 局部已领取/响应形状不等于未完成→动作→二次确认，也不覆盖重复前台、离线和会话失效 | OPEN |

本轮没有新增 Blocker/Major，也没有关闭既有 Blocker。V2EX 证据只计入 task 1.3 的局部“已领取页面”；NGA 证据只计入 task 1.2 的只读传输与响应形状观察。tasks 1.2、1.3、1.5、6.4 保持未完成。

一次性 NGA DEBUG 探针已从 `ForumHub/ForumHubApp.swift` 及仓库应用源码中清除；该文件没有工作区 diff。production policy 独立复查结果为 NGA 空 code 集合且 `allowsProductionWrite == false`，V2EX 无确认 action path 且 `allowsProductionWrite == false`。

## Cancellation / Generation 复审结论

```text
session change
    │
    ├─ generation += 1
    ├─ cancel old task
    ├─ clear retry/completion/display state
    │
    └─ replacement run waits for old task to finish
           │
           ├─ old service checks cancellation/generation before write
           ├─ old result cannot record under a new generation
           └─ old defer only clears a matching-generation run slot
```

未发现旧 generation 删除新任务、旧结果写回新账号或同来源替换任务并发的剩余路径。网络写请求一旦交给 URL loading system 后无法保证服务端绝对未接收，这是网络副作用的一般边界；当前实现通过写前检查、结构化取消和 production 禁写把风险控制在现有验收口径内。

## Test Evidence

- 聚焦真机测试（fixer evidence）：
  - `env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project ForumHub.xcodeproj -scheme ForumHub -configuration Debug -destination 'platform=iOS,id=A67DE9B5-C985-51C3-83BE-FBC006C114A4' -only-testing:ForumHubTests/DailyCheckInParserTests -only-testing:ForumHubTests/DailyCheckInServiceTests test`
  - PASS，17 tests。
- 完整真机单元测试（fixer evidence）：
  - `env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcodebuild -project ForumHub.xcodeproj -scheme ForumHub -configuration Debug -destination 'platform=iOS,id=A67DE9B5-C985-51C3-83BE-FBC006C114A4' -only-testing:ForumHubTests test`
  - PASS，完整 `ForumHubTests`。
- 用户补充证据：2026-07-22 手动安装到真实设备成功。
- 2026-07-23 NGA 增量（implementer evidence，reviewer 独立检查记录边界）：只读请求取得官方 HTTPS、HTTP 200、`text/javascript`、服务端 `Date`、JSON `null` 与 `data/time` 结构；未执行 POST、无写后二次确认，探针已删除。
- 2026-07-23 V2EX 增量（Chrome 采样事实，reviewer 独立检查结论边界）：最终页面为 HTTPS 官方 `/mission/daily` HTML，安全语义为今日已领取，候选动作数量为 0；未执行动作，不能完成 task 1.3。
- tree：`b2ee9ade7fcf9626e7f13890d35e8106ab05f992`。
- 独立 reviewer 本轮按要求不重复长测试，完成 delta diff-read 与短门禁检查。
- strict Rasen validate：PASS（1/1）。
- `git diff --check`：PASS。
- 短敏感信息扫描：PASS；未发现可重放 Authorization/Bearer/Cookie/UID/CID/非占位动态参数值。

## Open Findings

### V-002（Blocker）

真实未签到/成功链路样本尚未取得，production evidence policy 尚未校准。V2EX 的“今日已领取”只读页面与 NGA 的未解释只读响应形状均不足以授权写入；未来采样完成前必须保持 NGA/V2EX production 写入不可达。

### V-003（Blocker）

真机安装已成功，也已取得两个来源的局部只读观测，但真实账号的未签到→动作→二次确认、重复前台、离线和会话失效场景尚未验证。task 6.4 必须保持未完成。

## Canonical Verdict

VERIFY VERDICT: BLOCKED — Blocker:2 Major:0 Minor:0 Trivial:0
