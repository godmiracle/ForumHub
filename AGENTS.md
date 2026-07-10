# ForumHub AI Agent 协作规范

本文件是 Codex、ChatGPT、Claude Code、Gemini CLI 等 AI Coding Agent 以及人工协作者进入 ForumHub 项目的统一入口。

默认使用简体中文进行分析、说明、待办记录和最终总结；代码、命令、文件名、类型名、接口名及错误原文可以保留英文。

## 一、开始任务前

修改任何代码前，必须优先阅读与本次任务相关的文档：

1. [README.md](README.md)
2. [docs/context.md](docs/context.md)
3. [CONTEXT.md](CONTEXT.md)
4. [docs/architecture.md](docs/architecture.md)
5. [docs/decisions.md](docs/decisions.md)
6. [docs/todo.md](docs/todo.md)
7. 对应模块文档：[docs/modules](docs/modules/)
8. 执行代码审查时额外阅读 [docs/review.md](docs/review.md)

如果相关文件存在但尚未阅读，不得直接修改代码。无需机械读取整个仓库，应优先定位任务入口、调用链、相关类型、配置和测试。

## 二、项目边界

- `ForumHub` 是产品外壳。
- `NGA`、`V2EX` 和 `LINUX DO` 是数据源适配器。
- 共享 UI 应依赖领域模型，不应直接依赖数据源响应字段。
- 数据源特有逻辑应保留在 `Data/<Source>` 或对应适配层，除非它已被证明是通用能力。
- View 不负责解析远端响应。
- 不得为了快速完成任务破坏现有多数据源架构。

## 三、代码导航

- `ForumHub/Data`：Repository、Parser、DTO 映射和数据源适配
- `ForumHub/Domain`：`ForumThread`、`Reply`、内容块等共享领域模型
- `ForumHub/Features`：首页、热榜、帖子详情、搜索、账户、历史和社区管理 UI
- `ForumHub/Session`：登录流程、Cookie 同步、Token 与 Keychain 身份状态
- `ForumHub/DesignSystem`：颜色、字体、玻璃效果和可复用 UI 样式
- `ForumHub/Sync`：同步实验和未来扩展点
- `ForumHubTests`：单元测试、解析测试和 Fixtures
- `ForumHubUITests`：UI 自动化测试

## 四、禁止假设

不得凭经验虚构或补全以下内容：

- 文件、目录、类型、方法或变量；
- 接口、响应字段或数据库结构；
- 数据源行为、登录状态或 Cookie 合约；
- Apple 平台能力和第三方库能力；
- 项目中不存在的业务规则。

如果关键上下文缺失，应停止修改并明确说明缺少哪些文件、定义或运行信息。非关键上下文缺失时，可以继续完成确定部分，但必须把未确认内容标记为“待确认”。

## 五、修改原则

- 保持现有架构、命名、目录和代码风格一致。
- 修改范围尽可能小，优先修复根本原因。
- 优先复用已有实现，不重复造轮子。
- 同类问题影响多个 NGA 详情入口时，优先在共享接缝修复。
- 不进行无关的大规模重构，除非用户明确要求。
- 不删除现有功能、测试或错误处理来规避问题。
- 不得顺手格式化或重构与当前任务无关的代码。
- 不引入无必要的依赖、抽象层或设计模式。
- 不遗留调试日志、测试账号、硬编码密钥或临时文件。
- 用户可见文案默认使用中文。

发现更优但影响较大的方案时，应先说明收益、影响范围、迁移成本和风险，未经明确要求不得直接实施。

## 六、iOS 专项规则

- 遵守 Apple 平台限制，不默认使用私有 API。
- 注意 Swift 并发安全、`MainActor`、任务取消和状态回写时序。
- SwiftUI View 保持展示职责，业务状态和复杂加载逻辑优先放入合适的 Store 或 ViewModel。
- 注意 Scene 生命周期、前后台切换、登录恢复、Cookie 同步和 Keychain 行为。
- 涉及照片、网络、登录、隐私或系统权限时，必须说明风险和降级路径。
- 不假设模拟器和真机行为完全一致。

## 七、验证规则

优先在已连接的 iOS 真机上构建：

```sh
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
  -project ForumHub.xcodeproj \
  -scheme ForumHub \
  -configuration Debug \
  -destination 'platform=iOS,id=<CONNECTED_DEVICE_ID>' \
  build
```

如果当前没有可用真机，可以跳过构建，不要擅自改用模拟器并声称等价验证。

修改完成后，根据实际情况执行：

1. 构建或编译；
2. 相关自动化测试；
3. 静态检查；
4. 功能与边界状态验证；
5. `git diff` 检查。

只有实际执行并通过，才可以写“已通过”。无法执行时写“未执行”并说明原因；不得把理论分析描述成验证结果。

## 八、待办与文档同步

- 待办状态变化时更新 [docs/todo.md](docs/todo.md)。
- 只有满足验收标准并完成必要验证后，才能将 `[ ]` 自动更新为 `[x]`。
- 代码已修改但尚未验证时，保持 `[ ]`，标记“已修改，等待验证”或“等待人工验证”。
- 领域术语、业务不变量或数据源合约变化时更新 [CONTEXT.md](CONTEXT.md) 和 [docs/context.md](docs/context.md)。
- 非显而易见的产品或架构选择更新 [docs/decisions.md](docs/decisions.md)。
- 用户可见行为变化更新 [docs/changelog.md](docs/changelog.md)。
- 安装、运行方式、公开功能或目录入口变化时才更新 README。
- 独立开发会话需要留档时，在 `docs/sessions/YYYY-MM-DD.md` 中记录。

## 九、Review 规则

执行 Review 时必须遵循 [docs/review.md](docs/review.md)：

- 每个问题使用唯一编号，例如 `R-001`；
- 标注优先级和可信度；
- 提供涉及文件、证据、影响、建议和验收标准；
- 可执行问题同步到 `docs/todo.md`；
- 未验证问题不得标记完成；
- 不输出“建议优化代码质量”一类无法执行的空泛结论。

## 十、停止条件

出现以下情况时停止生成或修改代码：

- 无法确认正确实现；
- 缺少关键接口、类型、配置或数据源合约；
- 方案依赖未经验证的假设；
- 修改可能造成较大破坏但影响范围不明确；
- 整体可信度低于 80%。

停止时说明已确认内容、缺失上下文、已读取文件以及建议继续读取或补充的材料。

## 十一、最终输出格式

```md
## 本次修改

- 修改文件：
- 新增文件：
- 删除文件：

## 修改原因

- 问题：
- 根本原因：
- 解决方式：

## 验证结果

- 构建：
- 测试：
- 静态检查：
- 人工验证：
- Git Diff 检查：

## 影响与风险

- 影响范围：
- 已知风险：
- 未验证部分：
- 回滚方式：

## 待办状态

- 已完成：
- 等待验证：
- 未处理：

## 上下文检查

- 已读取：
- 未读取：
- 使用的现有实现：
- 推测：

## 可信度

- 整体可信度：
- 低于 100% 的原因：
```

最后输出：`SPEC:v2`
