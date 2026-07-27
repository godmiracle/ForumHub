## ADDED Requirements

### Requirement: 真实响应证据门禁
系统 MUST 在启用来源的 production 签到写操作或使其在 production 路径可达前，以当前真实登录会话采集并人工脱敏该来源的状态响应、成功响应、已完成响应和可安全取得的失败响应，并将可提交样本固化为测试 Fixture。解析器 MUST 对未知或未被真实 Fixture 支持的写入前提 fail closed。系统 MAY 在真实样本尚未齐全时实现 dormant、可注入且 production 不可达的解析与写服务安全接缝，并以明确标注的 synthetic Fixture 验证接缝；synthetic Fixture 不得作为解除 production 写入门禁的证据。

#### Scenario: 缺少真实未签到响应
- **WHEN** 某来源尚未取得能够明确证明“今日未签到”的真实脱敏 Fixture
- **THEN** 系统可以保留 dormant、可注入的写服务接缝，但不得启用该来源的 production 自动签到写请求，也不得使 production 路径能够到达远端写操作

#### Scenario: 使用 synthetic Fixture 验证安全接缝
- **WHEN** 真实未签到或成功响应尚未取得，但需要验证解析、取消、同源约束和单次动作控制
- **THEN** 系统可以使用明确标注为 synthetic 的 Fixture 驱动注入式测试，且该测试结果不得解除真实证据门禁或改变 production policy

#### Scenario: 响应结构未知
- **WHEN** 来源返回的结构不匹配任何已验证 Fixture 语义
- **THEN** 系统将结果视为不可安全识别且不执行后续写操作

#### Scenario: Fixture 完成脱敏
- **WHEN** 真实响应准备提交到仓库
- **THEN** Fixture 不包含 Cookie、访问令牌、UID、用户名、余额、动态 `once` 或其他可识别账号及重放请求的值

### Requirement: 用户按来源明确启用自动签到
系统 SHALL 为 NGA 与 V2EX 分别提供自动签到开关，两个开关 MUST 默认关闭，并且一个来源的选择不得改变另一个来源或 LINUX DO 的行为。

#### Scenario: 首次使用功能
- **WHEN** 用户尚未为任一来源保存自动签到偏好
- **THEN** NGA 与 V2EX 自动签到均保持关闭且不发送签到请求

#### Scenario: 仅启用 NGA
- **WHEN** 用户启用 NGA 自动签到但未启用 V2EX 自动签到
- **THEN** 合格触发只检查 NGA，不访问 V2EX 每日奖励页面

### Requirement: 在会话恢复后触发且不阻塞首页
系统 SHALL 在应用首次启动以及达到节流条件的前台恢复时，于来源会话恢复完成后检查已启用来源。签到任务 MUST 独立于 Feed 加载成功条件，来源切换和普通 Feed 刷新 MUST NOT 额外触发签到。

#### Scenario: 冷启动且来源已启用
- **WHEN** 应用冷启动、来源会话恢复完成且该来源自动签到已启用
- **THEN** 系统启动一次该来源签到检查，同时首页可独立继续加载

#### Scenario: 短时间重复进入前台
- **WHEN** 应用在节流窗口内多次进入 active 状态
- **THEN** 系统不会为同一来源重复启动签到检查

#### Scenario: 切换社区来源
- **WHEN** 用户在 NGA、V2EX 与 LINUX DO 之间切换浏览来源
- **THEN** 来源切换本身不产生新的签到请求

### Requirement: 来源会话资格保持隔离
系统 MUST 使用来源专属会话判断签到资格。NGA 仅在有效 NGA Cookie 会话下检查；V2EX 仅在有效 V2EX Web Cookie 会话下检查，Personal Access Token 不得单独提供 V2EX 签到资格。

#### Scenario: V2EX 只有 Token
- **WHEN** V2EX Personal Access Token 有效但 Web Session 无效或不存在
- **THEN** 系统跳过 V2EX 自动签到并将状态标记为需要网页登录

#### Scenario: NGA 未登录
- **WHEN** NGA 会话不包含项目定义的有效登录身份
- **THEN** 系统跳过 NGA 自动签到且不发送签到状态或写请求

### Requirement: NGA 先确认状态再签到
NGA 签到服务 MUST 先请求并解析签到统计。只有服务端响应明确表示当前周期未签到时，系统 SHALL 调用签到动作；已签到、未知、受限或鉴权不明确的响应 MUST NOT 触发签到写请求。写请求后 MUST 根据真实响应合约确认成功。

#### Scenario: NGA 今日未签到
- **WHEN** 已验证解析器从 `get_stat` 响应明确识别当前周期未签到
- **THEN** 系统发送至多一次 `check_in` 请求并确认最终结果

#### Scenario: NGA 今日已签到
- **WHEN** `get_stat` 明确表示当前周期已经签到
- **THEN** 系统返回已签到结果且不调用 `check_in`

#### Scenario: NGA 状态无法识别
- **WHEN** `get_stat` 返回未知结构、频率限制或无法明确分类的业务状态
- **THEN** 系统不调用 `check_in` 并保留安全诊断信息

### Requirement: V2EX 动态领取动作必须严格验证
V2EX 签到服务 MUST 从当前 `/mission/daily` 登录态页面区分可领取、已领取和未知状态。可领取动作 MUST 来自当前页面，使用 HTTPS，主机严格为 `www.v2ex.com`，路径匹配真实 Fixture 确认的领取路径，并包含非空动态 `once`；领取后 MUST 再确认服务端结果。

#### Scenario: V2EX 页面提供合法领取动作
- **WHEN** 已验证页面明确为可领取状态且包含满足全部同源约束的动态动作
- **THEN** 系统执行至多一次领取请求并重新确认今日状态

#### Scenario: V2EX 今日已领取
- **WHEN** 每日奖励页面明确表示今日奖励已领取
- **THEN** 系统返回已签到结果且不访问领取动作

#### Scenario: V2EX 页面包含意外链接
- **WHEN** 候选动作使用非 HTTPS、不同主机、错误路径、空 `once` 或页面不匹配已验证结构
- **THEN** 系统拒绝动作并且不发送领取请求

#### Scenario: V2EX 会话跳转到登录页
- **WHEN** 每日奖励请求明确重定向到 V2EX 登录页
- **THEN** 系统不领取奖励，并将该 Web Session 视为不具备签到资格

### Requirement: 并发去重与服务端权威
系统 MUST 保证同一来源在任一时刻最多存在一个签到任务。服务端状态 MUST 是是否已签到的最终权威；本地状态只能用于进程内去重、请求节流和安全展示，不得跨账号覆盖服务端判断。

#### Scenario: 启动与前台事件并发
- **WHEN** 启动检查尚未完成时又收到同一来源的前台检查
- **THEN** 系统复用或跳过第二次检查，不创建第二个写请求

#### Scenario: 多设备已完成签到
- **WHEN** 本机没有成功记录但服务端表示另一设备已经完成今日签到
- **THEN** 系统接受已签到结果且不再次写入

#### Scenario: 账号会话发生变化
- **WHEN** 用户登录、退出或替换某来源会话
- **THEN** 系统清除该来源可能跨账号误用的内存节流状态，并在下一次合格触发重新查询服务端

### Requirement: 失败不污染会话或阅读体验
网络离线、超时、限流、5xx 和未知响应 SHALL 作为签到失败处理，不得单独把来源会话标记为 expired，也不得阻止首页加载。系统 SHALL 在账户界面展示最近安全结果和可操作提示，正常成功或普通可重试失败不得在启动时强制弹窗。

#### Scenario: 签到请求离线失败
- **WHEN** 签到检查因离线或超时失败
- **THEN** 首页继续工作、登录状态保持原语义，并允许在后续节流窗口重试

#### Scenario: 缺少 V2EX Web Session
- **WHEN** 用户已启用 V2EX 自动签到但只有 Token 会话
- **THEN** 账户界面提示需要 V2EX 网页登录且启动过程不弹出强制提示

#### Scenario: 成功完成签到
- **WHEN** 来源明确确认刚刚签到或今日已经签到
- **THEN** 账户界面可显示该来源最近确认结果，且不以启动弹窗打断用户

### Requirement: 不承诺后台定时签到
系统 MUST 仅在应用运行并发生合格启动或前台触发时执行自动签到，不得向用户声称能够在应用未运行时保证每日签到。

#### Scenario: 应用整日未运行
- **WHEN** 某服务端签到周期内应用从未启动或进入前台
- **THEN** 系统不声称或记录该周期已自动签到
