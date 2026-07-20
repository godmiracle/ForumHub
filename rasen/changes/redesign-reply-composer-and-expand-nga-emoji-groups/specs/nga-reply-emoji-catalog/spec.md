## ADDED Requirements

### Requirement: 回复目录提供六个 NGA 表情分类
系统 SHALL 按 `NG娘、AC娘 v1、AC娘 v2、潘斯特、外域、企鹅` 的顺序提供六个可选择分类，并使用可横向浏览的分类导航确保每个分类名称可访问。

#### Scenario: 浏览全部分类
- **WHEN** 用户打开 NGA 表情目录并横向浏览分类栏
- **THEN** 系统允许用户选择全部六个分类，且当前分类具有明确选中状态

### Requirement: 新增分类使用确认的资源边界
系统 MUST 以两位十进制编号生成新增目录文件名：潘斯特包含 `pt00.png` 至 `pt64.png` 共 65 项，外域包含 `dt01.png` 至 `dt33.png` 共 33 项，企鹅包含 `pg01.png` 至 `pg15.png` 共 15 项。

#### Scenario: 生成潘斯特目录
- **WHEN** 系统构建潘斯特表情组
- **THEN** 第一项为 `pt00.png`、最后一项为 `pt64.png`，且目录恰好包含 65 个唯一文件名

#### Scenario: 生成外域目录
- **WHEN** 系统构建外域表情组
- **THEN** 第一项为 `dt01.png`、最后一项为 `dt33.png`，且目录恰好包含 33 个唯一文件名

#### Scenario: 生成企鹅目录
- **WHEN** 系统构建企鹅表情组
- **THEN** 第一项为 `pg01.png`、最后一项为 `pg15.png`，且目录恰好包含 15 个唯一文件名

### Requirement: 表情资源 URL 由来源目录确定
系统 SHALL 为每个目录条目生成 `https://img4.nga.178.com/ngabbs/post/smile/<filename>` URL，不得通过运行时网络探测决定目录成员。

#### Scenario: 构造新增表情 URL
- **WHEN** 目录解析 `pt00.png`、`dt01.png` 或 `pg01.png`
- **THEN** 系统分别生成以对应文件名结尾的 NGA smile HTTPS URL

### Requirement: 表情可在当前选择位置连续插入
系统 MUST 将用户选择的表情插入当前正文选择位置，并允许在表情目录保持打开时连续选择多个条目。

#### Scenario: 在文字中间插入
- **WHEN** 光标位于现有正文两个字符之间且用户选择一个新增表情
- **THEN** 富文本编辑器在该位置显示表情，并保留前后文字顺序

#### Scenario: 连续选择多个表情
- **WHEN** 用户在同一分类或不同分类中连续选择多个表情
- **THEN** 系统按选择顺序插入所有表情，且表情目录保持可继续操作

### Requirement: 六组表情支持可逆序列化
系统 MUST 将目录表情序列化为 `[img]<NGA smile URL>[/img]`，并通过统一目录从该标记中的文件名恢复对应富文本表情；未知文件名不得被误识别为目录表情。

#### Scenario: 新增表情往返
- **WHEN** 回复文档包含 `pt64.png`、`dt33.png` 和 `pg15.png` 表情并完成序列化后恢复
- **THEN** 恢复文档包含顺序和 URL 均相同的三个表情组件

#### Scenario: 识别未知图片
- **WHEN** 回复正文包含不属于六组目录的 `[img]` URL
- **THEN** 系统不得将该 URL 恢复为 NGA 目录表情

### Requirement: 既有三个分类保持兼容
系统 SHALL 在目录统一后保留当前 NG娘、AC娘 v1、AC娘 v2 的可选择条目与既有回复文档恢复行为。

#### Scenario: 恢复既有表情回复
- **WHEN** 回复文档包含当前支持的 `ng_`、`ac` 或 `a2_` smile 图片标记
- **THEN** 系统继续将其恢复为可编辑的富文本表情，并保持提交标记不变
