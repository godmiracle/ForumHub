## ADDED Requirements

### Requirement: 来源会话具有类型化生命周期
系统 SHALL 使用 `checking`、`signedOut`、`authenticated` 和 `expired` 等类型化状态表达活动来源会话，不得仅使用布尔值或从用户文案反推状态。

#### Scenario: 启动时恢复会话
- **WHEN** 应用正在从 Keychain 或 Cookie Store 恢复来源凭证
- **THEN** 会话保持 `checking`，直到恢复与必要验证得到明确结果

#### Scenario: 用户主动退出
- **WHEN** 用户完成退出且本地凭证已清除
- **THEN** 会话进入 `signedOut`

### Requirement: 首页只显示需要用户处理的会话状态
系统 SHALL 在 `authenticated` 时隐藏成功状态，在 `signedOut` 时显示“登录”，在 `expired` 时显示“重新登录”，并避免 `checking` 期间闪现错误动作。

#### Scenario: 正常登录
- **WHEN** 活动来源会话为 `authenticated`
- **THEN** 首页不显示“已登录”或“已连接”状态胶囊，也不保留空白占位

#### Scenario: 会话失效
- **WHEN** 活动来源会话为 `expired`
- **THEN** 首页显示登录状态已失效和“重新登录”动作

### Requirement: 失效判断必须基于明确鉴权证据
系统 MUST 仅在 HTTP 401、来源明确的无效会话响应、或已保存身份被验证为游客身份等鉴权证据下进入 `expired`；离线、超时、限流、5xx 和普通权限不足不得触发失效。

#### Scenario: 论坛服务不可用
- **WHEN** 已认证用户的 Feed 请求返回 5xx
- **THEN** 系统保留会话状态并显示服务不可用错误，不显示“重新登录”

#### Scenario: 服务端明确拒绝过期凭证
- **WHEN** 来源适配器把响应分类为 `authenticationExpired`
- **THEN** 会话进入 `expired` 并提供重新登录动作

### Requirement: 登录完成后续接受保护的用户意图
系统 SHALL 在未登录或失效用户点击发帖时保存不含正文和凭证的来源/频道意图，并在登录成功且上下文仍有效时继续；取消、切换来源或目的地失效时 MUST 清除意图。

#### Scenario: 登录后继续发帖
- **WHEN** 未登录用户点击发帖并成功完成活动来源登录，且来源和频道未变化
- **THEN** 系统自动进入对应发帖目的地，无需用户再次点击

#### Scenario: 登录期间切换来源
- **WHEN** 用户发起登录后活动来源发生变化
- **THEN** 系统取消原待处理发帖意图，不得在错误来源继续

### Requirement: 会话展示不得泄漏凭证
系统 MUST 只向首页提供安全的会话枚举、来源和用户可见动作，不得包含 Cookie、Token、CID、密码或原始鉴权响应。

#### Scenario: 构建首页会话提示
- **WHEN** Session 层生成供首页消费的会话描述
- **THEN** 描述中不包含任何可复用凭证或敏感 Cookie 名值
