# NGA 非官方 API 开发文档

> 基于 `wolfcon/NGA-API-Documents` 与实际运行客户端 `BugenZhao/MNGA` 源码整理  
> 初版整理日期：2026-07-10  
> MNGA 修订日期：2026-07-11  
> 文档性质：社区逆向整理，**不是 NGA 官方公开 API**。接口可能随时调整、失效或增加风控，请勿用于高频抓取、批量注册、垃圾信息、绕过权限或其他违反 NGA 用户协议的用途。

---

## 1. 文档概览

NGA 现存接口大致可以分成两套：

1. **官方 App 接口**
   - 主入口：`https://bbs.nga.cn/app_api.php`
   - 账户入口：`https://account.178.com/app_api.php`
   - 参数通常使用 `__lib` 与 `__act`
   - 返回格式通常使用 App JSON，常见 `__output=14`

2. **旧版网页接口**
   - 主题列表：`forum.php`
   - 阅读主题：`read.php`
   - 发帖与回复：`post.php`
   - 后台动作：`nuke.php`
   - 可通过 `lite=js/xml` 或 `__output` 控制输出格式
   - 默认字符集长期以 GBK 为主，提交 UTF-8 参数时可尝试增加 `__inchst=UTF8`

实际开发中建议：

- 浏览、搜索、收藏、用户信息等优先研究 `app_api.php`
- 为兼容历史客户端或获取更完整字段，可使用旧版网页接口
- 不要假设同名字段在两套接口中的类型完全一致
- 所有数字字段都应兼容“数字”和“数字字符串”
- 返回对象中经常出现以数字为键的对象，不一定是标准数组

---

## 2. 基础地址

```text
官方 App 主接口：
https://bbs.nga.cn/app_api.php

账户接口：
https://account.178.com/app_api.php

旧版主题列表：
https://bbs.nga.cn/thread.php
https://bbs.nga.cn/forum.php

旧版阅读主题：
https://bbs.nga.cn/read.php

旧版发帖：
https://bbs.nga.cn/post.php

旧版后台接口：
https://bbs.nga.cn/nuke.php
```

部分历史域名、图片域名和附件域名可能改变。客户端不应把图片主机写死，应优先使用响应中的完整 URL，或通过统一 URL 解析器兼容：

```text
https://img.nga.178.com/
https://img4.nga.cn/
https://img4.ngacn.cc/
```

---

## 3. 登录态与 Cookie

### 3.1 核心 Cookie

登录后最重要的两个 Cookie：

| Cookie | 说明 |
|---|---|
| `ngaPassportUid` | NGA 用户 UID |
| `ngaPassportCid` | 登录认证 Token |

请求需要登录权限的接口时，应携带完整 Cookie，而不是只复制单个字段。建议使用系统 Cookie 容器持久化：

```http
Cookie: ngaPassportUid=123456; ngaPassportCid=xxxxxxxx
```

### 3.2 登录状态判断

可尝试：

```http
GET /nuke.php?__lib=login&__act=iflogin&__output=14
```

也可以根据响应中是否包含当前用户结构判断，例如旧版返回里的：

```json
{
  "__CU": {
    "uid": 123456,
    "group_bit": 32,
    "admincheck": 0,
    "rvrc": 100
  }
}
```

未登录时，`__CU` 可能不存在。

### 3.3 网页登录

网页登录入口：

```text
https://bbs.nga.cn/nuke.php?__lib=login&__act=account&login
```

典型流程：

1. 在 WebView 中加载登录页面
2. 用户自行输入账号、密码和验证码
3. 登录成功后读取 Cookie
4. 将 Cookie 同步给 API 请求 Session

这种方式比直接实现账号密码加密更稳妥，也更适合第三方客户端。

### 3.4 App 专属登录

账户接口：

```http
POST https://account.178.com/app_api.php
```

仓库记录的历史参数：

| 参数 | 示例 | 说明 |
|---|---:|---|
| `_act` | `login` | 动作 |
| `app_id` | `1001` | 历史 iOS App ID |
| `email` | 用户输入 | 用户名、手机号或邮箱 |
| `password` | AES 后密文 | 密码密文 |
| `t` | Unix 时间戳 | 秒级时间戳 |
| `sign` | MD5 | 客户端签名 |

仓库还记录了历史 AppSecret、AES ECB 和签名拼接方式。**不建议在新项目中直接使用这些历史密钥**：它们可能已经失效，也可能触发安全和合规问题。第三方客户端优先采用 WebView 登录并保存 Cookie。

---

## 4. 请求与响应格式

### 4.1 App API 通用请求

```http
GET https://bbs.nga.cn/app_api.php?__lib=home&__act=category&_v=2
```

或者：

```http
POST https://bbs.nga.cn/app_api.php
Content-Type: application/x-www-form-urlencoded

__lib=subject&__act=list&fid=-7&page=1
```

常用公共参数：

| 参数 | 说明 |
|---|---|
| `__lib` | 模块名 |
| `__act` | 动作名 |
| `__output` | 输出格式，App 常用 `14` |
| `_v` | 接口版本 |
| `fid` | 版面 ID |
| `tid` | 主题 ID |
| `pid` | 回复 ID |
| `page` | 页码，通常从 1 开始 |
| `uid` | 用户 ID |
| `__inchst=UTF8` | 指定输入参数按 UTF-8 处理 |

### 4.2 旧版 `lite` 输出

旧版页面可使用：

```text
lite=js
lite=xml
```

`lite=js` 返回形式可能类似：

```javascript
window.script_muti_get_var_store={
  "data": {},
  "time": 1375213298
}
```

它不一定是严格 JSON。解析前应去掉：

```text
window.script_muti_get_var_store=
```

并处理尾部分号。

### 4.3 `__output` 输出格式

历史 Wiki 记录：

| 值 | 格式 |
|---:|---|
| `1` | JS，类似 `lite=js` |
| `3` | HTML 中嵌入 JS |
| `8` | 类 JSON，无变量赋值前缀，历史上可能是 GBK |
| `9` | XML |
| `11` | 标准 JSON |
| `12` | 旧 App JSON |
| `14` | App JSON，较常用 |

推荐优先尝试：

```text
__output=14
```

旧网页接口也可尝试：

```text
__output=11
```

### 4.4 编码

NGA 历史接口大量使用 GBK。建议：

- 请求参数默认使用 UTF-8 时增加 `__inchst=UTF8`
- 根据 HTTP Header、响应字段 `encode` 和实际字节判断编码
- JSON 解码失败时先尝试 GB18030/GBK 转 UTF-8
- 不要对已经编码的参数重复 URL Encode

### 4.5 通用错误结构

旧前台接口可能返回：

```json
{
  "data": {
    "__MESSAGE": {
      "0": 123,
      "1": "提示信息",
      "2": "详细信息",
      "3": 200
    }
  },
  "encode": "GBK",
  "time": 1375213298
}
```

`nuke.php` 常见形式：

```json
{
  "data": {},
  "error": {
    "0": "错误信息"
  },
  "encode": "GBK",
  "time": 1375213298
}
```

客户端判断失败时不能只看 HTTP 200，还要检查：

- `error`
- `__MESSAGE`
- `code`
- `msg`
- `message`
- 返回内容是否其实是登录页或验证码页

---

# 第一部分：App API

## 5. 首页模块 `home`

基础形式：

```text
__lib=home&__act=<action>
```

### 5.1 获取首页分类

```http
GET /app_api.php?__lib=home&__act=category&_v=2
```

用途：

- 获取首页分类
- 获取版面分组
- 构建首页导航

可能包含：

- 分类名称
- 分类图标
- 子版面
- `fid`
- 版面描述
- 跳转类型

### 5.2 首页新内容状态

```text
__lib=home&__act=hasnew
```

用于判断首页版面或订阅内容是否有更新。

### 5.3 首页 Banner

```text
__lib=home&__act=bannerrecm
```

### 5.4 标签版面

```text
__lib=home&__act=tagforums
```

### 5.5 App 栏目

```text
__lib=home&__act=appcolumns
```

### 5.6 广告

```text
__lib=home&__act=ad
```

第三方客户端应谨慎处理广告字段，不要假设返回始终存在。

### 5.7 推荐主题

```text
__lib=home&__act=recmthreads&_v=3
```

---

## 6. 主题列表模块 `subject`

基础形式：

```text
__lib=subject&__act=<action>
```

仓库注明 `list` 主要使用 POST，请求至少需要 `fid`，可选 `page`。

### 6.1 获取版面主题列表

```http
POST /app_api.php

__lib=subject
__act=list
fid=-7
page=1
```

常见参数：

| 参数 | 必需 | 说明 |
|---|---|---|
| `fid` | 是 | 版面 ID |
| `page` | 否 | 页码 |
| `recommend` | 否 | `1` 时可能仅获取推荐主题 |
| `order_by` | 否 | 排序方式，具体值需实测 |
| `__output` | 否 | 推荐 14 |

### 6.2 获取置顶主题

```text
__lib=subject&__act=topped
```

### 6.3 推荐主题列表

```text
__lib=subject&__act=list&recommend=1
```

### 6.4 主题投票

```text
__lib=subject&__act=vote
```

通常需要登录，可能需要：

- `tid`
- 投票选项 ID
- 表单校验字段

具体参数应以实时抓包为准。

### 6.5 搜索主题

```text
__lib=subject&__act=search
```

常见可能参数：

| 参数 | 说明 |
|---|---|
| `key` / `keyword` | 搜索词 |
| `fid` | 限定版面 |
| `page` | 页码 |
| `authorid` | 限定作者 |
| `content` | 是否搜索正文，需实测 |

### 6.6 订阅主题

```text
__lib=subject&__act=subscription
```

### 6.7 热门主题

```text
__lib=subject&__act=hot
```

---

## 7. 阅读主题与帖子模块 `post`

### 7.1 获取帖子列表

```text
__lib=post&__act=list
```

常见参数：

| 参数 | 说明 |
|---|---|
| `tid` | 主题 ID |
| `page` | 页码 |
| `pid` | 定位回复 |
| `authorid` | 只看某作者 |
| `order_by` | 排序 |
| `__output` | 输出格式 |

示例：

```http
POST /app_api.php

__lib=post
__act=list
tid=12345678
page=1
```

### 7.2 获取主题分类

```text
__lib=post&__act=titletype
```

用于发帖页面获取主题分类、标签或前缀。

### 7.3 推荐帖子

```text
__lib=post&__act=recommend
```

可能用于点赞、推荐或取消推荐，具体动作字段需要抓包确认。

### 7.4 获取发帖准备信息

```text
__lib=post&__act=check
```

可能返回：

- 是否允许发帖
- 上传地址
- 验证码
- 发帖限制
- 主题分类
- 表单 Token

发帖前建议先调用。

### 7.5 发布新主题

```text
__lib=post&__act=new
```

常见字段可能包括：

| 参数 | 说明 |
|---|---|
| `fid` | 版面 ID |
| `subject` | 标题 |
| `content` | 正文 |
| `type` / `post_subject` | 分类 |
| `attachments` | 附件 |
| 验证码字段 | 触发验证码时需要 |
| 表单 Token | 防重放或权限校验 |

### 7.6 回复主题

```text
__lib=post&__act=reply
```

常见字段：

| 参数 | 说明 |
|---|---|
| `tid` | 主题 ID |
| `pid` | 被回复的回复 ID，可选 |
| `content` | 回复内容 |
| `subject` | 回复标题，可选 |
| 附件字段 | 可选 |

### 7.7 编辑主题或回复

```text
__lib=post&__act=modify
```

常见参数：

- `tid`
- `pid`
- `subject`
- `content`
- 附件保留或删除信息

---

## 8. 收藏主题模块 `favor`

### 8.1 获取全部收藏

```text
__lib=favor&__act=all
```

### 8.2 其他收藏动作

```text
__lib=favor&__act=<action>
```

可能动作包括添加、删除、分类或同步，但仓库未给出完整 action 名称，应通过当前客户端抓包确认。

---

## 9. 收藏版面模块 `favorforum`

### 9.1 同步收藏版面

```text
__lib=favorforum&__act=sync
```

### 9.2 其他版面收藏动作

```text
__lib=favorforum&__act=<action>
```

---

## 10. 用户模块 `user`

### 10.1 用户发布主题

```text
__lib=user&__act=subjects
```

常见参数：

- `uid`
- `page`

### 10.2 用户回复

```text
__lib=user&__act=replys
```

注意仓库中的动作名为 `replys`，不是标准英文 `replies`。

### 10.3 用户详情

```text
__lib=user&__act=detail
```

常见参数：

```text
uid=<用户ID>
```

### 10.4 按用户名获取详情

```text
__lib=user&__act=detailname
```

常见参数可能为：

```text
username=<用户名>
```

### 10.5 更新用户信息

```text
__lib=user&__act=update
```

### 10.6 编辑签名

```text
__lib=user&__act=editsignature
```

### 10.7 第三方登录

```text
__lib=user&__act=thirdpartylogin
```

### 10.8 第三方注册

```text
__lib=user&__act=thirdpartyregister
```

---

## 11. 短消息模块 `message`

### 11.1 短消息列表

```text
__lib=message&__act=list
```

可能参数：

- `page`
- 文件夹类型
- 会话类型

### 11.2 离开会话

```text
__lib=message&__act=leave
```

### 11.3 发送短消息

```text
__lib=message&__act=send
```

常见字段：

| 参数 | 说明 |
|---|---|
| `to` / `uid` | 接收人 |
| `subject` | 标题 |
| `content` | 内容 |

### 11.4 回复短消息

```text
__lib=message&__act=reply
```

### 11.5 短消息详情

```text
__lib=message&__act=detail
```

---

## 12. 礼物模块 `gift`

```text
__lib=gift&__act=list
__lib=gift&__act=userlist
__lib=gift&__act=send
__lib=gift&__act=setreceive
```

| action | 说明 |
|---|---|
| `list` | 礼物列表 |
| `userlist` | 用户礼物列表 |
| `send` | 赠送礼物 |
| `setreceive` | 设置接收状态 |

涉及虚拟资产的接口应避免自动调用，并在提交前二次确认。

---

## 13. 提醒模块 `notify`

### 13.1 提醒列表

```text
__lib=notify&__act=list
```

### 13.2 未读提醒数

```text
__lib=notify&__act=unreadcnt
```

适合 App Badge 或消息中心红点。

---

## 14. 附近用户模块 `nearby`

```text
__lib=nearby&__act=updLocAndGetUsersNear
```

该接口可能上传位置并获取附近用户。应在取得用户明确授权后调用，不应后台静默上传。

---

## 15. 屏蔽模块 `block`

```text
__lib=block&__act=list
__lib=block&__act=<action>
```

通常用于黑名单、屏蔽用户或关键词。具体动作需实测。

---

## 16. 版面搜索模块 `forum`

```text
__lib=forum&__act=search
```

用于搜索版面，可能使用：

```text
keyword=<关键词>
```

---

## 17. 设备模块 `device`

```text
__lib=device&__act=upload
```

可能用于上传推送 Token、设备信息或客户端信息。第三方客户端不要伪装官方设备标识。

---

## 18. 黑市/商城模块 `blackstore`

```text
__lib=blackstore&__act=list
__lib=blackstore&__act=purchased
__lib=blackstore&__act=order
__lib=blackstore&__act=exchange
__lib=blackstore&__act=lastaddr
__lib=blackstore&__act=address
```

| action | 说明 |
|---|---|
| `list` | 商品列表 |
| `purchased` | 已购买项目 |
| `order` | 下单 |
| `exchange` | 兑换 |
| `lastaddr` | 最近地址 |
| `address` | 地址操作 |

---

## 19. 地址簿模块 `addresslist`

```text
__lib=addresslist&__act=get
```

---

## 20. 游戏模块

### 20.1 通用游戏

```text
__lib=game&__act=query
__lib=game&__act=items
__lib=game&__act=scores
```

### 20.2 比赛

```text
__lib=match&__act=list
__lib=match&__act=items
```

### 20.3 守望先锋 `ow`

```text
__lib=ow&__act=playerlist
__lib=ow&__act=playershow
__lib=ow&__act=heroshow
__lib=ow&__act=playerranking
__lib=ow&__act=heroranking
__lib=ow&__act=playerrefresh
__lib=ow&__act=playerupdate
__lib=ow&__act=playerremove
```

### 20.4 魔兽世界 `wow`

```text
__lib=wow&__act=characterlist
__lib=wow&__act=realmlist
__lib=wow&__act=characteradd
__lib=wow&__act=characterremove
__lib=wow&__act=charactershow
__lib=wow&__act=characterrefresh
__lib=wow&__act=characterranking
__lib=wow&__act=charactercheck
__lib=wow&__act=characteruncheck
__lib=wow&__act=guildranking
__lib=wow&__act=raidlist
```

这些接口年代较久，部分可能已经停用。

---

## 21. 管理模块 `manage`

```text
__lib=manage&__act=topicget
__lib=manage&__act=topicset
__lib=manage&__act=topicdel
__lib=manage&__act=postget
__lib=manage&__act=postset
__lib=manage&__act=gagget
__lib=manage&__act=gagset
__lib=manage&__act=scoreget
__lib=manage&__act=scoreset
```

仅有相应管理权限的账号可使用。第三方客户端应根据返回权限决定是否显示入口。

---

## 22. OpenIM 模块

```text
__lib=openim&__act=user
```

可能用于获取即时通讯用户信息。

---

## 23. 签到模块

### 23.1 执行签到

```text
__lib=check_in&__act=check_in&__output=14
```

### 23.2 获取签到统计

```text
__lib=check_in&__act=get_stat&__output=14
```

签到可能有频率限制，不应自动重复调用。

---

# 第二部分：旧版网页 API

## 24. 获取论坛首页

历史 Wiki 使用论坛首页接口获取版面树、分类和当前用户信息。由于 NGA 页面入口多次调整，推荐优先使用 App API 的：

```text
__lib=home&__act=category&_v=2
```

旧版返回常包含：

- `__CU`：当前用户
- `__GLOBAL`：公共变量 XML
- 版面分类
- 版面 ID 与版面名称
- 子版面结构

---

## 25. 获取主题列表

旧版主题列表通常使用：

```http
GET /thread.php?fid=-7&page=1&lite=js
```

或历史接口：

```http
GET /forum.php?fid=-7&page=1&lite=js
```

常用参数：

| 参数 | 说明 |
|---|---|
| `fid` | 版面 ID |
| `page` | 页码 |
| `order_by` | 排序 |
| `authorid` | 作者 UID |
| `key` | 搜索词 |
| `lite` | `js` 或 `xml` |
| `__output` | 输出格式 |
| `__inchst` | 输入编码 |

主题对象常见字段：

| 字段 | 说明 |
|---|---|
| `tid` | 主题 ID |
| `fid` | 所在版面 |
| `subject` | 标题 |
| `author` | 作者名 |
| `authorid` | 作者 UID |
| `postdate` | 发布时间戳 |
| `lastpost` | 最后回复时间 |
| `lastposter` | 最后回复用户 |
| `replies` | 回复数 |
| `type` | 主题状态位 |
| `topic_misc` | 扩展信息 |
| `recommend` | 推荐值 |
| `ifupload` | 是否有附件 |

---

## 26. 阅读主题 `read.php`

### 26.1 请求地址

```text
https://bbs.nga.cn/read.php
```

### 26.2 参数

| 参数 | 说明 |
|---|---|
| `tid` | 主题 ID |
| `pid` | 回复 ID，可直接定位某条回复 |
| `page` | 页码 |
| `authorid` | 只看指定作者 |
| `lite` | `js` 或 `xml` |
| `__output` | 输出格式 |
| `v2` | 历史接口常固定为 `1` |

示例：

```http
GET /read.php?tid=12345678&page=1&lite=js&v2=1
```

只看某作者：

```http
GET /read.php?tid=12345678&authorid=123456&lite=js&v2=1
```

定位回复：

```http
GET /read.php?pid=123456789&lite=js&v2=1
```

### 26.3 顶层响应字段

旧版响应的 `data` 中常见：

| 字段 | 说明 |
|---|---|
| `__CU` | 当前访问用户 |
| `__GLOBAL` | 公共变量文件 |
| `__U` | 本页涉及的用户字典 |
| `__GROUPS` | 用户组字典 |
| `__MEDALS` | 徽章字典 |
| `__REPUTATIONS` | 声望数据 |
| `__R` | 回复字典 |
| `__T` | 主题信息 |
| `__F` | 版面信息 |
| `__ROWS` | 帖子总数 |
| `__R__ROWS` | 当前页帖子数 |
| `__R__ROWS_PAGE` | 每页帖子数 |

页数计算：

```text
总页数 = ceil(__ROWS / __R__ROWS_PAGE)
```

### 26.4 回复对象 `__R`

常见字段：

| 字段 | 说明 |
|---|---|
| `content` | 正文 |
| `alterinfo` | 编辑、评分等附加信息 |
| `type` | 帖子状态位 |
| `authorid` | 作者 UID |
| `subject` | 回复标题 |
| `pid` | 回复 ID，主楼可能为 0 |
| `tid` | 主题 ID |
| `fid` | 版面 ID |
| `content_length` | 内容长度 |
| `from_client` | 发布客户端 |
| `org_fid` | 原始版面 |
| `attachs` | 附件 |
| `lou` | 楼层 |
| `postdatetimestamp` | 发布时间戳 |

### 26.5 用户对象 `__U`

常见字段：

| 字段 | 说明 |
|---|---|
| `uid` | 用户 ID |
| `username` | 用户名 |
| `medal` | 徽章 ID |
| `groupid` | 用户组 |
| `memberid` | 用户组 |
| `avatar` | 头像，类型可能不稳定 |
| `yz` | 账号状态 |
| `site` | 个人版名 |
| `honor` | 头衔 |
| `regdate` | 注册时间 |
| `mute_time` | 禁言截止时间 |
| `postnum` | 发帖数 |
| `rvrc` | 威望原始值 |
| `money` | 铜币 |
| `thisvisit` | 最近访问 |
| `signature` | 签名 |
| `bit_data` | 用户状态位 |
| `remark` | 用户备注 |
| `buffs` | Buff 数据 |

注意：论坛显示威望可能是原始 `rvrc / 10`。

### 26.6 附件对象

常见字段：

| 字段 | 说明 |
|---|---|
| `aid` | 附件 ID |
| `url_utf8_org_name` | 原始文件名 |
| `path` | 相对目录 |
| `size` | 大小 |
| `ext` | 扩展名 |
| `name` | 文件名 |
| `thumb` | 缩略图位标记 |
| `attachurl` | 附件路径 |
| `type` | 附件类型 |

历史缩略图位：

| Bit | 后缀 |
|---:|---|
| 8 | `.thumb_ss.jpg` |
| 16 | `.thumb_s.jpg` |
| 32 | `.thumb.jpg` |
| 64 | `.medium.jpg` |

客户端应优先使用服务端直接返回的缩略图 URL；只有缺失时才拼接历史后缀。

---

## 27. 发帖、回复与编辑

旧版一般使用：

```text
https://bbs.nga.cn/post.php
```

常见动作：

| `action` | 说明 |
|---|---|
| `new` | 发布主题 |
| `reply` | 回复 |
| `modify` | 编辑 |
| 其他值 | 可能用于投票、附件等 |

典型发帖参数可能包括：

```text
action=new
fid=<版面ID>
subject=<标题>
content=<正文>
post_subject=<分类>
```

典型回复参数：

```text
action=reply
tid=<主题ID>
content=<正文>
```

编辑：

```text
action=modify
tid=<主题ID>
pid=<回复ID>
content=<正文>
```

真实调用通常还需要页面动态生成的校验字段、权限字段或验证码。推荐流程：

1. 先访问发帖页面或 App `post/check`
2. 获取表单 Token、验证码和附件上传信息
3. 按原表单字段提交
4. 检查 `__MESSAGE`，不要只依赖 HTTP 状态码
5. 提交成功后用返回 `tid/pid` 跳转

---

## 28. 用户信息

App API 推荐：

```text
__lib=user&__act=detail&uid=<uid>
__lib=user&__act=detailname&username=<name>
__lib=user&__act=subjects&uid=<uid>&page=1
__lib=user&__act=replys&uid=<uid>&page=1
```

旧版用户信息可能通过 `nuke.php` 或用户页面取得。用户字段类型差异较大，建议在模型层全部使用可选字段。

---

## 29. 短消息

App API 推荐：

```text
__lib=message&__act=list
__lib=message&__act=detail
__lib=message&__act=send
__lib=message&__act=reply
__lib=message&__act=leave
```

涉及发送操作时：

- 用户应明确点击发送
- 客户端防止重复提交
- 遇到验证码或限流时展示原始提示
- 不应自动批量私信

---

## 30. 收藏主题或回复

App API：

```text
__lib=favor&__act=all
__lib=favor&__act=<具体动作>
```

旧版收藏动作可能位于 `nuke.php`。由于仓库没有完整列出 action 与参数，建议抓取当前网页或官方客户端请求补充。

---

## 31. 签到

App API：

```text
__lib=check_in&__act=check_in&__output=14
__lib=check_in&__act=get_stat&__output=14
```

---

## 32. 提醒信息

App API：

```text
__lib=notify&__act=list
__lib=notify&__act=unreadcnt
```

旧版提醒也可能从用户中心或 `nuke.php` 获取。

---

## 33. `nuke.php` 接口索引

仓库 README 收录了以下接口：

### 33.1 登录与登出

```text
nuke.php?__lib=login&__act=account&login
nuke.php?__lib=login&__act=account&logout
nuke.php?__lib=login&__act=logout
nuke.php?__lib=login&__act=iflogin
nuke.php?__lib=login&__act=qrlogin_ui
```

### 33.2 管理日志与操作日志

```text
nuke.php?__lib=filter&__act=get_log&fid=<fid>&id=<id>&__output=14&jump_to=1
nuke.php?func=adminlog&f=access_log
```

### 33.3 推荐主题

```text
nuke.php?__lib=app_inter&__act=recmd_topic
```

### 33.4 首页活动与 Banner

```text
nuke.php?__lib=nga_index&__act=get_event_app&__output=14
nuke.php?__lib=app_inter&__act=banner_list
```

### 33.5 道具判断

```text
nuke.php?__lib=item&__act=have_item&type=4&sub_type=<sub_type>
```

### 33.6 视频任务

```text
nuke.php?__lib=mission&__act=video_view_task_counter_add
nuke.php?__lib=mission&__act=video_view_task_get
```

### 33.7 分享记录

```text
nuke.php?__lib=data_query&__act=topic_share_log_v2
```

### 33.8 回复楼梯

```text
nuke.php?__lib=load_topic&__act=load_topic_reply_ladder
```

可能用于加载回复引用链、楼中楼或回复关系。

---

# 第三部分：公共数据模型

## 34. 当前用户 `CurrentUser`

```json
{
  "uid": 58,
  "group_bit": 1034239,
  "admincheck": 1,
  "rvrc": 465
}
```

| 字段 | 说明 |
|---|---|
| `uid` | 当前用户 ID |
| `group_bit` | 权限位 |
| `admincheck` | 当前页面是否具有部分管理权限 |
| `rvrc` | 威望原始值 |

---

## 35. 用户权限位 `group_bit`

历史位定义：

| Bit | 值 | 说明 |
|---|---:|---|
| `_GB_ADMIN` | 1 | 管理员 |
| `_GB_SUPER` | 2 | 超级版主 |
| `_GB_GREATER` | 4 | 版主 |
| `_GB_SUPERLESSER` | 8 | 超级次级版主 |
| `_GB_LESSER` | 16 | 次级版主 |
| `_GB_NORMAL` | 32 | 普通用户 |

判断方法：

```swift
let isNormal = (groupBit & 32) != 0
```

---

## 36. 帖子类型位 `type`

历史定义：

| 值 | 说明 |
|---:|---|
| 1 | 评论 |
| 2 | 隐藏 |
| 4 | 存在评论 |
| 16 | 列表展示额外用户信息 |
| 64 | 阻止回复提示 |
| 128 | 超期仍可编辑 |
| 256 | 仅自己可回复 |
| 1024 | 锁定 |
| 4096 | 含自动翻译内容 |
| 8192 | 含上传文件 |

判断时使用位运算，不要使用相等判断：

```swift
let isLocked = (type & 1024) != 0
let hasUpload = (type & 8192) != 0
```

---

## 37. 版面类型位

历史定义：

| 值 | 说明 |
|---:|---|
| 8 | 有同义词翻译表 |
| 32 | 设置监视关键词 |
| 64 | 设置主题分类颜色 |
| 128 | 自定义声望级别 |
| 256 | 强制主题分类 |
| 512 | 设置版面背景图 |

---

## 38. `topic_misc`

`topic_misc` 是主题扩展字段。

### 38.1 旧格式

首字符为 `~` 时，可能包含：

```text
red
blue
green
orange
silver
b
i
u
```

分别表示标题颜色、粗体、斜体、下划线。

### 38.2 二进制格式

首字符不是 `~` 时，历史 Wiki 说明它可能是 Base64 编码的二进制结构。由于格式扩展较多，建议：

- 保留原始字符串
- 只解析已确认的类型
- 未知类型跳过，不要导致整个主题解码失败

---

## 39. 公共变量 XML

历史公共变量文件可能包含：

```xml
<__IMG_BASE>...</__IMG_BASE>
<__IMGPATH>...</__IMGPATH>
<__IMG_STYLE>...</__IMG_STYLE>
<__COMMONRES_PATH>...</__COMMONRES_PATH>
<__FORUM_ICON_PATH>...</__FORUM_ICON_PATH>
```

以及版面图标映射：

```xml
<forum fid="320" icon="10"/>
```

不要长期缓存固定域名，可缓存映射并设置过期时间。

---

# 第四部分：客户端实现建议

## 40. 网络层设计

推荐统一封装：

```swift
struct NGARequest {
    let path: String
    let method: HTTPMethod
    let parameters: [String: String]
    let requiresLogin: Bool
}
```

网络层职责：

1. 自动携带 Cookie
2. 自动补充 User-Agent
3. URL Form 编码
4. UTF-8/GBK 解码
5. 去除 JS 包装
6. 统一错误解析
7. 处理登录失效
8. 限速和重试
9. 保存原始响应用于调试

### 40.1 User-Agent

建议使用真实的第三方客户端标识：

```text
ForumHub/1.0 (iOS 27.0; iPhone)
```

不要冒充 NGA 官方 App。

### 40.2 Cookie 持久化

建议：

- iOS 使用 `HTTPCookieStorage`
- 敏感 Cookie 可同步存入 Keychain
- 退出登录时删除 NGA 相关 Cookie
- 不要打印完整 `ngaPassportCid`

---

## 41. 宽松 JSON 解码

NGA 字段可能出现：

```json
{ "uid": 123 }
```

也可能出现：

```json
{ "uid": "123" }
```

建议实现：

```swift
enum FlexibleInt: Codable {
    case value(Int)
}
```

或者在 `init(from:)` 中依次尝试：

```swift
if let int = try? container.decode(Int.self) { ... }
if let string = try? container.decode(String.self),
   let int = Int(string) { ... }
```

对象数组也可能表现为：

```json
{
  "0": {...},
  "1": {...}
}
```

应先按键转换并按数字排序。

---

## 42. 正文解析

NGA 正文可能包含：

- BBCode
- 引用
- 图片
- 附件
- 表情
- URL
- 折叠内容
- 表格
- 代码块
- 回复引用标记

建议分两层：

1. **解析层**：将原始内容转换为 AST
2. **渲染层**：AST 渲染为 AttributedString、SwiftUI View 或 HTML

不要只用大量正则直接替换，否则嵌套 Quote、Code 和 Table 很容易错乱。

---

## 43. 图片与附件

建议建立 URL 规范化函数：

```swift
func normalizeNGAURL(_ raw: String, baseURL: URL) -> URL?
```

处理：

- `//img...`
- `/attachments/...`
- `mon_YYYYMM/...`
- HTML Entity
- URL Encode
- 历史图片域名
- HTTP 自动升级 HTTPS

加载策略：

- 列表只加载缩略图
- 详情页延迟加载
- 大图点击后查看原图
- GIF 单独处理
- 控制缓存大小

---

## 44. 分页

NGA 多数页码从 1 开始，但部分接口可能使用偏移量。

建议状态：

```swift
struct PageState {
    var currentPage = 1
    var hasMore = true
    var isLoading = false
}
```

判定是否还有下一页时综合：

- 当前返回数量
- 总数量字段
- 每页数量
- 服务端 `has_more`
- 下一页是否返回重复数据

主题列表可能因置顶帖导致跨页重复，应以 `tid` 去重；回复以 `pid` 去重，主楼可使用 `tid + lou` 作为辅助标识。

---

## 45. 风控、验证码和限流

可能出现：

- 验证码页面
- 登录页面 HTML
- 频率过高提示
- HTTP 403
- HTTP 418/429
- 返回 JSON 但业务错误
- Cookie 被刷新
- IP 风控

处理原则：

1. 不无限重试
2. 写操作不自动重试
3. GET 请求最多指数退避重试 1～2 次
4. 验证码交给用户完成
5. 展示服务端提示
6. 限制并发
7. 缓存首页、版面信息和用户信息

---

## 46. 推荐的 MVP 接口组合

第三方 NGA 客户端第一版只需实现：

### 首页

```text
home/category
home/recmthreads
favorforum/sync
```

### 主题列表

```text
subject/list
subject/topped
subject/search
```

### 主题详情

```text
post/list
```

或旧版：

```text
read.php?tid=...&lite=js&v2=1
```

### 用户

```text
user/detail
user/subjects
user/replys
```

### 登录

```text
WebView 登录 + Cookie
```

### 消息

```text
notify/unreadcnt
notify/list
message/list
```

### 写操作

```text
post/check
post/new
post/reply
post/modify
```

建议先完成只读功能，再实现登录和写操作。

---

# 第五部分：请求示例

## 47. cURL：首页分类

```bash
curl 'https://bbs.nga.cn/app_api.php?__lib=home&__act=category&_v=2&__output=14' \
  -H 'User-Agent: ForumHub/1.0'
```

## 48. cURL：主题列表

```bash
curl 'https://bbs.nga.cn/app_api.php' \
  -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Cookie: ngaPassportUid=YOUR_UID; ngaPassportCid=YOUR_CID' \
  --data-urlencode '__lib=subject' \
  --data-urlencode '__act=list' \
  --data-urlencode 'fid=-7' \
  --data-urlencode 'page=1' \
  --data-urlencode '__output=14'
```

## 49. cURL：阅读主题

```bash
curl 'https://bbs.nga.cn/read.php?tid=12345678&page=1&lite=js&v2=1' \
  -H 'Cookie: ngaPassportUid=YOUR_UID; ngaPassportCid=YOUR_CID'
```

## 50. cURL：签到

```bash
curl 'https://bbs.nga.cn/app_api.php?__lib=check_in&__act=check_in&__output=14' \
  -H 'Cookie: ngaPassportUid=YOUR_UID; ngaPassportCid=YOUR_CID'
```

## 51. JavaScript 示例

```javascript
async function fetchTopics(fid, page = 1, cookie = "") {
  const body = new URLSearchParams({
    __lib: "subject",
    __act: "list",
    fid: String(fid),
    page: String(page),
    __output: "14",
  });

  const response = await fetch("https://bbs.nga.cn/app_api.php", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Cookie": cookie,
    },
    body,
  });

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }

  const text = await response.text();
  return JSON.parse(text);
}
```

浏览器环境通常不能直接设置 `Cookie` Header，并可能受到 CORS 限制；该示例更适用于 Node.js、Electron 后端或原生客户端。

## 52. Swift 示例

```swift
import Foundation

final class NGAClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func request(
        lib: String,
        action: String,
        parameters: [String: String] = [:]
    ) async throws -> Data {
        let url = URL(string: "https://bbs.nga.cn/app_api.php")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "ForumHub/1.0 (iOS)",
            forHTTPHeaderField: "User-Agent"
        )

        var values = parameters
        values["__lib"] = lib
        values["__act"] = action
        values["__output"] = values["__output"] ?? "14"
        values["__inchst"] = values["__inchst"] ?? "UTF8"

        let body = values
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")

        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200..<300 ~= http.statusCode else {
            throw NSError(
                domain: "NGAClient",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }
        return data
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
                .union(CharacterSet(charactersIn: "-._~"))
        ) ?? self
    }
}
```

---

# 第六部分：接口总表

## 53. App API 总表

| 模块 | Action | 说明 |
|---|---|---|
| `check_in` | `check_in` | 签到 |
| `check_in` | `get_stat` | 签到统计 |
| `home` | `category` | 首页分类 |
| `home` | `hasnew` | 新内容状态 |
| `home` | `bannerrecm` | Banner |
| `home` | `tagforums` | 标签版面 |
| `home` | `appcolumns` | App 栏目 |
| `home` | `ad` | 广告 |
| `home` | `recmthreads` | 推荐主题 |
| `subject` | `list` | 主题列表 |
| `subject` | `topped` | 置顶主题 |
| `subject` | `vote` | 投票 |
| `subject` | `search` | 搜索 |
| `subject` | `subscription` | 订阅 |
| `subject` | `hot` | 热门主题 |
| `favor` | `all` | 全部收藏 |
| `favorforum` | `sync` | 同步收藏版面 |
| `user` | `subjects` | 用户主题 |
| `user` | `replys` | 用户回复 |
| `user` | `detail` | 用户详情 |
| `user` | `detailname` | 按用户名查询 |
| `user` | `update` | 更新用户信息 |
| `user` | `editsignature` | 编辑签名 |
| `user` | `thirdpartylogin` | 第三方登录 |
| `user` | `thirdpartyregister` | 第三方注册 |
| `post` | `list` | 阅读主题 |
| `post` | `titletype` | 主题分类 |
| `post` | `recommend` | 推荐操作 |
| `post` | `check` | 发帖准备 |
| `post` | `new` | 发布主题 |
| `post` | `reply` | 回复 |
| `post` | `modify` | 编辑 |
| `message` | `list` | 短消息列表 |
| `message` | `leave` | 离开会话 |
| `message` | `send` | 发送消息 |
| `message` | `reply` | 回复消息 |
| `message` | `detail` | 消息详情 |
| `gift` | `list` | 礼物列表 |
| `gift` | `userlist` | 用户礼物 |
| `gift` | `send` | 赠送礼物 |
| `gift` | `setreceive` | 设置接收 |
| `notify` | `list` | 提醒列表 |
| `notify` | `unreadcnt` | 未读数 |
| `nearby` | `updLocAndGetUsersNear` | 更新位置并获取附近用户 |
| `block` | `list` | 屏蔽列表 |
| `forum` | `search` | 搜索版面 |
| `device` | `upload` | 上传设备信息 |
| `blackstore` | `list` | 商城列表 |
| `blackstore` | `purchased` | 已购买 |
| `blackstore` | `order` | 下单 |
| `blackstore` | `exchange` | 兑换 |
| `blackstore` | `lastaddr` | 最近地址 |
| `blackstore` | `address` | 地址操作 |
| `addresslist` | `get` | 地址簿 |
| `game` | `query` | 游戏查询 |
| `game` | `items` | 游戏项目 |
| `game` | `scores` | 游戏分数 |
| `match` | `list` | 比赛列表 |
| `match` | `items` | 比赛项目 |
| `ow` | 多项 | 守望先锋数据 |
| `wow` | 多项 | 魔兽世界数据 |
| `manage` | 多项 | 版主管理 |
| `openim` | `user` | IM 用户 |

---

# 第七部分：已知限制

## 54. 为什么本文不能保证每个参数都可直接使用

原仓库本身明确说明接口是通过非官方方式整理，可能不完整。并且：

- README 最近内容仍主要是接口索引
- Wiki 多数页面最后编辑于 2021 年
- NGA 服务端在之后可能多次调整
- 部分接口仅官方 App、特定用户组或特定版面可用
- 写接口经常依赖动态 Token、验证码和权限
- 游戏、附近用户、商城等旧模块可能已停用
- 响应字段可能按账号、版面、设备和 `_v` 不同而变化

因此，本文将“仓库有记录的接口”完整归类，但对仓库没有明确记录的参数，不虚构确定值，统一标记为需要实测或抓包确认。

---

## 55. 建议的验证方法

对每个接口建立测试记录：

```markdown
### subject/list

- 测试日期：
- 是否需要登录：
- GET/POST：
- 必需参数：
- 可选参数：
- 成功响应样本：
- 未登录响应：
- 无权限响应：
- 限流响应：
- 备注：
```

测试时：

1. 使用自己的账号
2. 低频调用
3. 先在网页或官方 App 完成相同动作
4. 对比请求参数
5. 删除 Cookie、Token、手机号、IP 等敏感信息后保存样本
6. 将响应模型做成宽松可选字段

---

## 56. 来源

- GitHub 仓库：`wolfcon/NGA-API-Documents`
- 仓库 README：App API 索引、登录方式、`nuke.php` 索引
- 仓库 Wiki：数据格式、公共字段、首页、主题、阅读、发帖、用户、短消息、登录、客户端、收藏、任务、签到、道具和提醒等历史资料
- 原 Wiki 引用的 NGA 论坛历史说明帖

> 本文是对社区资料的重新组织与工程化说明，不代表 NGA 官方承诺。

---

# MNGA 实际调用修订与补全

> 本章基于 `BugenZhao/MNGA` 当前源码中的网络层、请求函数和响应解析模型整理。  
> 相比仅列出接口名称的历史文档，本章中的路径和参数均来自实际客户端调用，应作为实现 NGA 第三方客户端时的优先参考。  
> 但 MNGA 仍然是第三方客户端，不代表 NGA 官方对接口稳定性的承诺。

## 57. 结论：接口优先级需要调整

此前文档将 NGA 接口分为：

1. `app_api.php`
2. `thread.php` / `read.php` / `post.php` / `nuke.php`

根据 MNGA 的实现，建议调整优先级：

### 实际主要接口

```text
thread.php
read.php
post.php
nuke.php
forum.php
```

主要用于：

- 版面主题列表
- 搜索主题
- 收藏主题列表
- 阅读帖子
- 只看作者
- 发帖、回复、编辑、评论
- 收藏夹管理
- 版面收藏
- 点赞/踩
- 举报
- 屏蔽子版面
- 用户帖子列表

### 辅助 App API

```text
app_api.php
```

MNGA 当前明确使用它获取首页版面分类：

```text
app_api.php?__lib=home&__act=category
```

因此，`app_api.php` 不应被视为 MNGA 的唯一主接口；对 ForumHub 这类第三方客户端，更合理的做法是：

- 版面目录：`app_api.php`
- 主题列表与搜索：`thread.php`
- 帖子详情：`read.php`
- 写操作：`post.php`
- 收藏、推荐、举报和用户设置：`nuke.php`

---

## 58. MNGA 网络请求约定

### 58.1 可切换主机

MNGA 内置以下主机：

```text
nga.178.com
bbs.nga.cn
ngabbs.com
```

默认：

```text
https://nga.178.com/
```

客户端不应把所有 URL 写死为单一域名，建议提供可切换 Base URL。

### 58.2 通用输入编码

MNGA 为请求统一增加：

```text
__inchst=UTF8
```

该参数应作为 NGA 请求的默认参数之一。

### 58.3 请求方法

MNGA 对大部分结构化接口使用：

```http
POST
Content-Type: application/x-www-form-urlencoded
```

即使参数位于 Query 中，底层仍可能使用 POST，并把登录信息放入 Form。

### 58.4 登录凭据 Form

MNGA 的鉴权请求会在 Form 中加入：

```text
access_token=<token>
access_uid=<uid>
```

这说明除了浏览器 Cookie 登录外，部分接口可以直接使用：

- `access_token`
- `access_uid`

具体值来自当前登录信息。

### 58.5 Header

MNGA 设置：

```http
User-Agent: <设备UA>
X-User-Agent: <设备UA>
Referer: <当前NGA请求URL>
```

对于 `read.php`，在用户未手动选择自定义设备时，MNGA 默认使用 Windows Phone User-Agent，因为项目认为该返回更稳定。

建议客户端实现可配置 UA，而不是只使用默认 URLSession UA。

### 58.6 超时

MNGA 网络层设置：

```text
连接超时：5 秒
读取超时：20 秒
启用 gzip
仅 HTTPS
```

### 58.7 字符编码

响应文本按：

```text
GB18030
```

进行解码，而不是简单假定 UTF-8。

---

## 59. 响应格式与回退策略

MNGA 优先解析 XML，而不是将所有接口强制当作 JSON。

### 59.1 XML 输出参数

优先尝试：

```text
lite=xml
```

备选：

```text
__output=10
```

历史上还存在：

```text
__output=9
__output=11
__output=8
```

但 MNGA 当前重点使用：

1. `lite=xml`
2. `__output=10`

### 59.2 JSON 输出

`nuke.php` 和部分 `app_api.php` 请求通过 JSON 解析器处理。

### 59.3 自动重试

MNGA 会在以下情况自动更换输出参数：

- XML 解析失败
- 响应内容异常
- HTTP 状态异常
- 接口被特定输出参数限制

对 `read.php` 还可能进行：

1. 直接 XML
2. 网页 HTML 转换为结构化数据
3. 代理请求
4. 本地缓存回退

因此，客户端不应只依赖单一：

```text
read.php?lite=xml
```

建议实现：

```text
lite=xml
→ __output=10
→ HTML 页面解析
→ 本地缓存
```

代理属于 MNGA 自身基础设施，不建议第三方项目直接依赖。

---

# MNGA 验证的接口

## 60. 获取版面分类

```http
POST /app_api.php?__lib=home&__act=category&__inchst=UTF8
```

MNGA 实际参数：

| 参数 | 值 |
|---|---|
| `__lib` | `home` |
| `__act` | `category` |
| `__inchst` | `UTF8` |

响应为 JSON。

主要解析结构：

```text
分类
└── groups
    └── forums
```

版面常见字段：

| 字段 | 说明 |
|---|---|
| `id` | 图标或版面标识 |
| `fid` | 普通版面 ID |
| `stid` | 综合/主题版面 ID |
| `name` | 版面名称 |
| `info` | 说明 |
| `topped_topic` | 置顶主题 ID |

### fid 与 stid

MNGA 对版面 ID 使用联合类型：

```text
fid
或
stid
```

调用接口时根据类型分别传：

```text
fid=<fid>
```

或：

```text
stid=<stid>
```

不要把 `stid` 强制转换为 `fid`。

---

## 61. 搜索版面

```http
POST /forum.php?key=<关键词>&lite=xml&__inchst=UTF8
```

参数：

| 参数 | 必需 | 说明 |
|---|---|---|
| `key` | 是 | 搜索关键词 |
| `lite=xml` | 推荐 | XML 输出 |
| `__inchst=UTF8` | 推荐 | 输入编码 |

MNGA 从：

```text
/root/item
```

解析版面列表。

---

## 62. 主题列表

```http
POST /thread.php
```

MNGA 实际参数：

| 参数 | 说明 |
|---|---|
| `fid` | 普通版面 ID |
| `stid` | 综合版面 ID |
| `page` | 页码 |
| `order_by` | 排序方式 |
| `recommend` | 是否仅推荐主题 |
| `__inchst=UTF8` | 输入编码 |
| `lite=xml` 或 `__output=10` | 输出格式 |

示例：

```text
thread.php?fid=-7&page=1&order_by=&recommend=&lite=xml&__inchst=UTF8
```

或：

```text
thread.php?stid=123456&page=1&lite=xml&__inchst=UTF8
```

响应主要结构：

```text
/root/__T/item
/root/__F
/root/__F/sub_forums
/root/__ROWS
/root/__T__ROWS_PAGE
```

### 分页

MNGA 使用：

```text
总条目数：/root/__ROWS
每页条目数：/root/__T__ROWS_PAGE
默认每页：35
```

### 主题字段

MNGA 实际解析：

| 字段 | 说明 |
|---|---|
| `tid` | 主题 ID |
| `quote_from` | 某些场景替代 `tid` |
| `fid` | 版面 ID |
| `subject` | 标题 |
| `authorid` | 作者 UID |
| `author` | 作者名 |
| `postdate` | 发布时间 |
| `lastpost` | 最后回复时间 |
| `replies` | 回复数 |
| `type` | 类型位 |
| `topic_misc` | 标题样式和扩展信息 |
| `tpcurl` | 可能包含收藏标识 |

---

## 63. 只看推荐主题

仍使用主题列表接口：

```http
POST /thread.php
```

参数：

```text
fid=<fid>
recommend=1
page=<page>
```

MNGA 将布尔值转换后传给 `recommend`。

---

## 64. 主题搜索

```http
POST /thread.php
```

MNGA 实际参数：

| 参数 | 说明 |
|---|---|
| `fid` | 普通版面 ID |
| `stid` | 综合版面 ID |
| `key` | 搜索关键词 |
| `recommend` | 是否只搜索推荐主题 |
| `content` | 是否搜索正文 |
| `page` | 页码 |

示例：

```text
thread.php?fid=-7&key=Swift&recommend=0&content=1&page=1
```

返回主题结构仍为：

```text
/root/__T/item
```

---

## 65. 收藏主题列表

```http
POST /thread.php
```

参数：

| 参数 | 说明 |
|---|---|
| `favor` | 收藏夹 ID |
| `page` | 页码 |

示例：

```text
thread.php?favor=<folder_id>&page=1&lite=xml
```

分页字段：

```text
/root/__ROWS
/root/__T__ROWS_PAGE
```

---

## 66. 收藏夹列表 V2

```http
POST /nuke.php?__lib=topic_favor_v2&__act=list_folder&page=1
```

参数：

| 参数 | 位置 | 值 |
|---|---|---|
| `__lib` | Query | `topic_favor_v2` |
| `__act` | Query | `list_folder` |
| `page` | Query | `1` |

响应为 JSON。

文件夹字段：

| 字段 | 说明 |
|---|---|
| `id` | 收藏夹 ID |
| `name` | 收藏夹名 |
| `length` | 主题数量 |
| `default` | 存在时表示默认收藏夹 |

---

## 67. 新建收藏夹

```http
POST /nuke.php?__lib=topic_favor_v2&__act=new_folder&raw=3
```

Form：

| 参数 | 说明 |
|---|---|
| `name` | 收藏夹名称 |
| `opt` | `2` 表示设为默认，否则 `0` |

响应中收藏夹 ID 可能位于：

```text
data["1"]
```

或：

```text
data["0"]
```

---

## 68. 修改、设默认或删除收藏夹

统一入口：

```http
POST /nuke.php?__lib=topic_favor_v2&__act=<action>&raw=3
```

### 重命名

```text
__act=modify_folder
```

Form：

```text
folder=<folder_id>
name=<新名称>
```

### 设为默认

```text
__act=modify_folder
```

Form：

```text
folder=<folder_id>
opt=2
```

### 删除

```text
__act=del_folder
```

Form：

```text
folder=<folder_id>
```

---

## 69. 主题详情

```http
POST /read.php
```

MNGA 实际参数：

| 参数 | 说明 |
|---|---|
| `tid` | 主题 ID |
| `page` | 页码 |
| `fav` | 收藏标识，可选 |
| `pid` | 定位回复，可选 |
| `authorid` | 只看指定作者 |
| `opt` | 匿名作者筛选时为 `512` |
| `__inchst=UTF8` | 输入编码 |
| `lite=xml` 或 `__output=10` | 输出格式 |

示例：

```text
read.php?tid=12345678&page=1&lite=xml&__inchst=UTF8
```

只看作者：

```text
read.php?tid=12345678&page=1&authorid=123456&lite=xml
```

定位回复：

```text
read.php?tid=12345678&pid=987654321&lite=xml
```

仅匿名作者：

```text
read.php?tid=12345678&opt=512&lite=xml
```

### MNGA 的详情回退策略

```text
XML 快速请求
→ HTML 页面解析
→ XML 普通请求
→ 代理请求
→ 本地缓存
```

项目还会记录本次使用的解析方式，便于调试。

### 主要响应节点

```text
/root/__U/item
/root/__R/item
/root/__T
/root/__F
/root/__ROWS
/root/__R__ROWS_PAGE
```

---

## 70. 帖子回复字段

MNGA 当前解析字段：

| 字段 | 说明 |
|---|---|
| `pid` | 回复 ID |
| `tid` | 主题 ID |
| `fid` | 版面 ID |
| `lou` | 楼层 |
| `authorid` | 作者 UID |
| `content` | 正文 |
| `postdatetimestamp` | 发布时间 |
| `score` | 评分 |
| `alterinfo` | 编辑、评分等信息 |
| `from_client` | 客户端 |
| `attachs` | 附件 |
| `hotreply` | 热门回复 |
| `comment` | 楼中楼评论 |

对于匿名用户，`authorid` 可能为负数。MNGA 会结合当前主题上下文构造临时唯一用户标识。

---

## 71. 发新主题、回复、引用、编辑和评论

统一使用：

```http
POST /post.php
```

### Action

MNGA 根据操作类型设置：

```text
action=<操作值>
step=2
```

操作包含：

- 新主题
- 回复
- 引用
- 编辑
- 评论

具体 `action` 字符串由 MNGA 的枚举序列化值决定；实现时应通过当前页面表单或源码枚举核对，不要自行猜值。

### 通用 Form

| 参数 | 说明 |
|---|---|
| `action` | 操作类型 |
| `step` | 固定 `2` |
| `post_content` | 正文 |
| `post_subject` | 标题，可选 |
| `attachments` | 附件名称，Tab 分隔 |
| `attachments_check` | 附件校验值，Tab 分隔 |
| `anony` | 匿名发帖时为 `1` |

### 新主题

传：

```text
fid=<fid>
```

或：

```text
stid=<stid>
```

### 回复、引用、编辑和评论

传：

```text
tid=<tid>
pid=<pid>
```

### 评论

额外：

```text
comment=1
```

### 追加编辑

额外：

```text
modify_append=1
```

---

## 72. 获取编辑器原始内容

在编辑或引用前，MNGA 请求：

```http
POST /post.php
```

参数：

```text
action=<action>
tid=<tid>
pid=<pid>
```

新主题则传：

```text
fid=<fid>
```

或：

```text
stid=<stid>
```

响应节点：

| 节点 | 说明 |
|---|---|
| `/root/content` | 编辑器正文 |
| `/root/subject` | 标题 |
| `/root/modify_append` | 是否追加编辑 |
| `/root/auth` | 上传鉴权值 |
| `/root/attach_url` | 附件上传地址 |

发帖前建议先调用该接口获取动态字段。

---

## 73. 附件上传

上传地址不是固定写死，而是由 `post.php` 编辑器准备接口返回：

```text
attach_url
```

请求：

```http
POST <attach_url>
Content-Type: multipart/form-data
```

MNGA 使用的 Multipart 字段：

| 字段 | 值/说明 |
|---|---|
| `v2` | `1` |
| `origin_domain` | `ngabbs.com` |
| `func` | `upload` |
| `auth` | 编辑器接口返回值 |
| `fid` | 版面 ID |
| `attachment_file1_img` | `1` |
| `attachment_file1_dscp` | 文件名 |
| `attachment_file1_url_utf8_name` | UTF-8 文件名 |
| `attachment_file1_watermark` | 空 |
| `attachment_file1_auto_size` | 空 |
| `attachment_file1` | 文件二进制 |

响应节点：

```text
/root/attachments
/root/url
/root/attachments_check
```

提交帖子时需要把：

```text
attachments
attachments_check
```

一起带回 `post.php`。

---

## 74. 推荐、点赞或踩帖子

MNGA 使用：

```http
POST /nuke.php
```

Query：

```text
__lib=topic_recommend
__act=add
value=<操作值>
tid=<tid>
pid=<pid>
```

响应 JSON 中增量值可能位于：

```text
data["1"]
```

或：

```text
data["0"]
```

MNGA 根据返回增量判断状态：

- 大于 0：赞
- 小于 0：踩
- 等于 0：取消状态

---

## 75. 举报帖子

```http
POST /nuke.php
```

Query：

```text
__lib=log_post
__act=report
raw=3
info=<举报内容>
tid=<tid>
pid=<pid>
```

举报操作不经过 `post.php`。

---

## 76. 用户帖子列表

```http
POST /thread.php
```

参数：

```text
searchpost=1
authorid=<uid>
page=<page>
```

响应包含主题和简化帖子正文：

```text
/root/__T/item
/root/__T/item/__P
```

适合实现“用户回复”页面。

---

## 77. 版面收藏列表

```http
POST /nuke.php?__lib=forum_favor2&__act=forum_favor
```

Form：

```text
action=get
```

响应为 JSON，主要数据位于：

```text
data["0"]
```

---

## 78. 添加或删除版面收藏

```http
POST /nuke.php?__lib=forum_favor2&__act=forum_favor
```

Form：

```text
action=add
fid=<fid或stid>
```

删除：

```text
action=del
fid=<fid或stid>
```

注意：即使传入的是 `stid`，MNGA 仍统一使用 Form 字段名：

```text
fid
```

---

## 79. 屏蔽或恢复子版面

```http
POST /nuke.php
```

Query：

```text
__lib=user_option
__act=set
add=<子版面过滤ID>
```

恢复显示时：

```text
del=<子版面过滤ID>
```

Form：

```text
fid=<父版面ID>
type=1
info=add_to_block_tids
```

---

# 数据模型补全

## 80. 主题标题样式

MNGA 将 `topic_misc` 作为 Base64 无填充数据解析。

其中数据类型 `1` 的四字节大端整数表示标题样式位：

| Mask | 样式 |
|---:|---|
| `0x01` | 红色 |
| `0x02` | 蓝色 |
| `0x04` | 绿色 |
| `0x08` | 橙色 |
| `0x10` | 银色 |
| `0x20` | 粗体 |
| `0x40` | 斜体 |
| `0x80` | 下划线 |

之前文档中的文本 `~red~` 形式仍可作为历史兼容，但现代客户端应优先支持 Base64 二进制格式。

---

## 81. 特殊主题类型位

MNGA 使用：

```text
type & 0x8000
```

判断主题是否为 `stid` 快捷版面。

使用：

```text
type & 0x200000
```

判断是否从 `topic_misc_var` 提取快捷版面 `fid`。

因此主题 `type` 不应只解释为锁定、附件等帖子状态；它还可能表示“主题卡片实际是版面入口”。

---

## 82. 子版面字段

MNGA 从主题列表的：

```text
/root/__F/sub_forums/*
```

解析：

| 位置/字段 | 说明 |
|---|---|
| 第 0 项 | fid 或 stid |
| 第 1 项 | 名称 |
| 第 2 项 | 说明 |
| 第 3 项 | 过滤 ID |
| 第 4 项 | attributes |

当 `attributes > 40` 时，MNGA 将其视为可过滤子版面。

---

# 对原文档的纠正

## 83. 应继续保留的内容

此前文档中这些内容仍有效：

- `ngaPassportUid` / `ngaPassportCid` Cookie
- `app_api.php` 首页分类
- `thread.php` / `read.php` 基础结构
- `post.php` 发帖
- `nuke.php` 后台动作
- GBK/GB18030 兼容
- `__output` 多种格式
- `__U` / `__R` / `__T` / `__F`
- 主题和回复字段
- 附件 URL 处理
- 位字段解析

## 84. 应调整的内容

### 原表述

```text
App API 是主要接口，旧网页接口用于兼容。
```

### 修订为

```text
MNGA 实际以 thread.php、read.php、post.php 和 nuke.php 为核心；
app_api.php 主要用于版面目录等少数结构化数据。
```

### 原表述

```text
优先使用 __output=14。
```

### 修订为

对于 MNGA 路线：

```text
thread.php/read.php/post.php：
优先 lite=xml，备选 __output=10。

nuke.php/app_api.php：
根据具体接口使用 JSON。
```

### 原表述

```text
GET/POST 均可。
```

### 修订为

MNGA 网络层主要按 POST 请求，并使用 Form 提交登录凭据和写操作数据。

---

# ForumHub 推荐实现

## 85. MVP 接口

### 首页

```text
POST app_api.php
__lib=home
__act=category
```

### 版面主题

```text
POST thread.php
fid/stid
page
order_by
recommend
lite=xml
```

### 搜索

```text
POST thread.php
fid/stid
key
content
page
```

### 详情

```text
POST read.php
tid
page
pid
authorid
lite=xml
```

### 用户帖子

```text
POST thread.php
searchpost=1
authorid
page
```

### 收藏

```text
nuke.php?__lib=topic_favor_v2
nuke.php?__lib=forum_favor2
```

### 写操作

```text
post.php
nuke.php?__lib=topic_recommend
nuke.php?__lib=log_post
```

---

## 86. 推荐网络层结构

```swift
enum NGAEndpoint {
    case forumCategories
    case forumSearch(keyword: String)
    case topicList(id: ForumID, page: Int, order: String?, recommendedOnly: Bool)
    case topicSearch(id: ForumID, keyword: String, searchContent: Bool, page: Int)
    case topicDetail(tid: String, page: Int, pid: String?, authorID: String?)
    case userPosts(uid: String, page: Int)
    case favoriteFolders
    case favoriteTopics(folderID: String, page: Int)
    case favoriteForums
    case postEditor(action: PostAction)
    case submitPost(action: PostAction, content: String)
    case recommendPost(tid: String, pid: String, value: Int)
    case reportPost(tid: String, pid: String, reason: String)
}
```

请求层应支持：

```text
JSON
XML
HTML fallback
GB18030
application/x-www-form-urlencoded
multipart/form-data
Cookie
access_uid/access_token
多 Base URL
可配置 User-Agent
```

---

## 87. 实现可信度分级

在后续文档中建议给接口标记：

### A：MNGA 当前源码直接调用

例如：

```text
thread.php 主题列表
read.php 主题详情
post.php 写操作
topic_favor_v2
forum_favor2
topic_recommend
log_post
```

### B：wolfcon 文档记录，但 MNGA 当前未使用

例如：

```text
app_api.php 的 gift、nearby、blackstore、ow、wow
```

### C：根据返回字段或历史行为推测

必须注明：

```text
待实测
```

ForumHub 第一版应只依赖 A 级接口。

---

## 88. 最终结论

`BugenZhao/MNGA` 应作为 NGA 文档的主要工程参考，因为它提供了：

- 实际路径
- 实际 Query 与 Form 参数
- XML 和 JSON 的真实选择
- GB18030 解码
- UA 和 Header
- 登录信息注入
- 输出格式回退
- HTML 解析回退
- 收藏夹 V2
- 版面收藏 V2
- 写操作
- 附件上传
- 数据模型解析
- 接口异常处理

但不能简单认为“源码里出现就永久有效”。最可靠的排序应是：

```text
MNGA 当前源码调用
> 自己账号低频实测
> wolfcon 历史文档
> 未验证推测
```
