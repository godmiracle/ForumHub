# V2EX API 2.0 Beta 本地文档

> 根据 V2EX 官方 API 帮助页整理。  
> 官方文档最后更新时间：2026-04-17  
> API 状态：Beta，接口可能继续调整。

## 1. 基本信息

### Base URL

```text
https://www.v2ex.com/api/v2/
```

### 数据格式

请求和响应通常使用 JSON。发送 JSON 请求体时建议携带：

```http
Content-Type: application/json
Accept: application/json
```

### 认证方式

V2EX API 2.0 使用 Personal Access Token（个人访问令牌）认证。

```http
Authorization: Bearer YOUR_PERSONAL_ACCESS_TOKEN
```

完整请求头示例：

```http
Authorization: Bearer YOUR_PERSONAL_ACCESS_TOKEN
Accept: application/json
Content-Type: application/json
```

> 不要把真实 Token 写入 Git 仓库、客户端源码或公开日志。建议通过环境变量、Keychain 或本地配置文件注入。

---

## 2. 请求频率限制

默认情况下，每个 IP 每小时最多请求 600 次。

响应头中可能包含：

```http
X-Rate-Limit-Limit: 120
X-Rate-Limit-Reset: 1409479200
X-Rate-Limit-Remaining: 116
```

字段说明：

| 响应头 | 说明 |
|---|---|
| `X-Rate-Limit-Limit` | 当前时间窗口内允许的请求总数 |
| `X-Rate-Limit-Remaining` | 当前时间窗口内剩余请求数 |
| `X-Rate-Limit-Reset` | 限流重置时间，通常为 Unix 时间戳 |

能够被 CDN 缓存的接口，一般只有第一次请求会消耗 Rate Limit 配额。

---

## 3. 接口总览

| 方法 | 路径 | 功能 | 需要认证 |
|---|---|---|---|
| `GET` | `/notifications` | 获取最新提醒 | 是 |
| `DELETE` | `/notifications/{notification_id}` | 删除指定提醒 | 是 |
| `GET` | `/member` | 获取当前用户 Profile | 是 |
| `GET` | `/token` | 查看当前使用的令牌 | 是 |
| `POST` | `/tokens` | 创建新的令牌 | 是 |
| `GET` | `/nodes/{node_name}` | 获取指定节点 | 是 |
| `GET` | `/nodes/{node_name}/topics` | 获取指定节点下的主题 | 是 |
| `GET` | `/topics/{topic_id}` | 获取指定主题 | 是 |
| `GET` | `/topics/{topic_id}/replies` | 获取指定主题下的回复 | 是 |
| `POST` | `/topics/{topic_id}/set-sticky` | 置顶自己的主题 | 是 |
| `POST` | `/topics/{topic_id}/boost` | 将自己的主题放置到首页 | 是 |

---

## 4. 提醒接口

### 4.1 获取最新提醒

```http
GET /notifications
```

#### Query 参数

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---:|---|
| `p` | Integer | 否 | `1` | 分页页码 |

#### 请求示例

```bash
curl \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/notifications?p=2"
```

#### JavaScript 示例

```javascript
const response = await fetch(
  "https://www.v2ex.com/api/v2/notifications?p=2",
  {
    headers: {
      Authorization: `Bearer ${process.env.V2EX_TOKEN}`,
      Accept: "application/json",
    },
  },
);

if (!response.ok) {
  throw new Error(`请求失败：${response.status}`);
}

const notifications = await response.json();
console.log(notifications);
```

---

### 4.2 删除指定提醒

```http
DELETE /notifications/{notification_id}
```

#### Path 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `notification_id` | Integer | 是 | 提醒 ID |

#### 请求示例

```bash
curl -X DELETE \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/notifications/123456"
```

---

## 5. 用户与令牌接口

### 5.1 获取当前用户 Profile

```http
GET /member
```

#### 请求示例

```bash
curl \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/member"
```

#### JavaScript 示例

```javascript
const response = await fetch("https://www.v2ex.com/api/v2/member", {
  headers: {
    Authorization: `Bearer ${process.env.V2EX_TOKEN}`,
    Accept: "application/json",
  },
});

const profile = await response.json();
console.log(profile);
```

---

### 5.2 查看当前使用的令牌

```http
GET /token
```

#### 请求示例

```bash
curl \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/token"
```

---

### 5.3 创建新的令牌

```http
POST /tokens
```

系统中最多可创建 10 个 Personal Access Token。

#### JSON 请求体

| 参数 | 类型 | 必填 | 可选值 | 说明 |
|---|---|---:|---|---|
| `scope` | String | 是 | `everything`、`regular` | `regular` 类型 Token 不能继续创建新 Token |
| `expiration` | Integer | 是 | `2592000`、`5184000`、`7776000`、`15552000` | 有效期秒数，分别对应 30、60、90、180 天 |

#### 请求体示例

```json
{
  "scope": "everything",
  "expiration": 2592000
}
```

#### cURL 示例

```bash
curl -X POST \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"scope":"everything","expiration":2592000}' \
  "https://www.v2ex.com/api/v2/tokens"
```

#### JavaScript 示例

```javascript
const response = await fetch("https://www.v2ex.com/api/v2/tokens", {
  method: "POST",
  headers: {
    Authorization: `Bearer ${process.env.V2EX_TOKEN}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  },
  body: JSON.stringify({
    scope: "everything",
    expiration: 2592000,
  }),
});

if (!response.ok) {
  throw new Error(`创建令牌失败：${response.status}`);
}

const token = await response.json();
console.log(token);
```

---

## 6. 节点接口

### 6.1 获取指定节点

```http
GET /nodes/{node_name}
```

#### Path 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `node_name` | String | 是 | 节点名称，例如 `python` |

#### 请求示例

```bash
curl \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/nodes/python"
```

---

### 6.2 获取指定节点下的主题

```http
GET /nodes/{node_name}/topics
```

#### Path 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `node_name` | String | 是 | 节点名称 |

#### Query 参数

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---:|---|
| `p` | Integer | 否 | `1` | 分页页码 |

#### 请求示例

```bash
curl \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/nodes/python/topics?p=2"
```

---

## 7. 主题接口

### 7.1 获取指定主题

```http
GET /topics/{topic_id}
```

#### Path 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `topic_id` | Integer | 是 | 主题 ID |

#### 请求示例

```bash
curl \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/topics/1"
```

---

### 7.2 获取指定主题下的回复

```http
GET /topics/{topic_id}/replies
```

#### Path 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `topic_id` | Integer | 是 | 主题 ID |

#### Query 参数

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---:|---|
| `p` | Integer | 否 | `1` | 分页页码 |

#### 请求示例

```bash
curl \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/topics/1/replies?p=2"
```

---

### 7.3 置顶自己的主题

```http
POST /topics/{topic_id}/set-sticky
```

仅用于置顶当前用户自己创建的主题。

#### Path 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `topic_id` | Integer | 是 | 主题 ID |

#### Query 参数

| 参数 | 类型 | 必填 | 默认值 | 可选值 |
|---|---|---:|---|---|
| `duration` | String | 否 | `15min` | `15min`、`1hr`、`8hr` |

#### 请求示例

```bash
curl -X POST \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/topics/1/set-sticky?duration=1hr"
```

---

### 7.4 将主题放置到首页

```http
POST /topics/{topic_id}/boost
```

#### 使用条件

- 只能操作自己创建的主题。
- 用户需要是 PRO 用户，或持有 50000 以上 Token。
- 基础费用为 100 铜币。
- 如果主题创建于过去年度，费用会根据主题年份增加。

#### Path 参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `topic_id` | Integer | 是 | 主题 ID |

#### 请求示例

```bash
curl -X POST \
  -H "Authorization: Bearer ${V2EX_TOKEN}" \
  -H "Accept: application/json" \
  "https://www.v2ex.com/api/v2/topics/1/boost"
```

---

## 8. 通用 JavaScript API Client

下面是一个适合 Node.js、前端项目或 TypeScript 项目继续封装的基础客户端。

```javascript
const V2EX_API_BASE_URL = "https://www.v2ex.com/api/v2";

export class V2EXApiClient {
  constructor(token) {
    if (!token) {
      throw new Error("V2EX Personal Access Token 不能为空");
    }

    this.token = token;
  }

  async request(path, options = {}) {
    const response = await fetch(`${V2EX_API_BASE_URL}${path}`, {
      ...options,
      headers: {
        Authorization: `Bearer ${this.token}`,
        Accept: "application/json",
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        ...options.headers,
      },
    });

    const contentType = response.headers.get("content-type") ?? "";
    const data = contentType.includes("application/json")
      ? await response.json()
      : await response.text();

    if (!response.ok) {
      const error = new Error(`V2EX API 请求失败：${response.status}`);
      error.status = response.status;
      error.data = data;
      throw error;
    }

    return data;
  }

  getNotifications(page = 1) {
    return this.request(`/notifications?p=${page}`);
  }

  deleteNotification(notificationId) {
    return this.request(`/notifications/${notificationId}`, {
      method: "DELETE",
    });
  }

  getCurrentMember() {
    return this.request("/member");
  }

  getCurrentToken() {
    return this.request("/token");
  }

  createToken(scope, expiration) {
    return this.request("/tokens", {
      method: "POST",
      body: JSON.stringify({ scope, expiration }),
    });
  }

  getNode(nodeName) {
    return this.request(`/nodes/${encodeURIComponent(nodeName)}`);
  }

  getNodeTopics(nodeName, page = 1) {
    return this.request(
      `/nodes/${encodeURIComponent(nodeName)}/topics?p=${page}`,
    );
  }

  getTopic(topicId) {
    return this.request(`/topics/${topicId}`);
  }

  getTopicReplies(topicId, page = 1) {
    return this.request(`/topics/${topicId}/replies?p=${page}`);
  }

  setTopicSticky(topicId, duration = "15min") {
    return this.request(
      `/topics/${topicId}/set-sticky?duration=${encodeURIComponent(duration)}`,
      { method: "POST" },
    );
  }

  boostTopic(topicId) {
    return this.request(`/topics/${topicId}/boost`, {
      method: "POST",
    });
  }
}
```

使用示例：

```javascript
import { V2EXApiClient } from "./V2EXApiClient.js";

const client = new V2EXApiClient(process.env.V2EX_TOKEN);

const member = await client.getCurrentMember();
const topics = await client.getNodeTopics("python", 1);

console.log(member);
console.log(topics);
```

---

## 9. VS Code REST Client 调试模板

安装 VS Code 的 REST Client 扩展后，可以新建 `v2ex-api.http`：

```http
@baseUrl = https://www.v2ex.com/api/v2
@token = YOUR_PERSONAL_ACCESS_TOKEN
@topicId = 1
@nodeName = python

### 获取当前用户
GET {{baseUrl}}/member
Authorization: Bearer {{token}}
Accept: application/json

### 获取令牌信息
GET {{baseUrl}}/token
Authorization: Bearer {{token}}
Accept: application/json

### 获取提醒
GET {{baseUrl}}/notifications?p=1
Authorization: Bearer {{token}}
Accept: application/json

### 获取节点
GET {{baseUrl}}/nodes/{{nodeName}}
Authorization: Bearer {{token}}
Accept: application/json

### 获取节点主题
GET {{baseUrl}}/nodes/{{nodeName}}/topics?p=1
Authorization: Bearer {{token}}
Accept: application/json

### 获取主题
GET {{baseUrl}}/topics/{{topicId}}
Authorization: Bearer {{token}}
Accept: application/json

### 获取主题回复
GET {{baseUrl}}/topics/{{topicId}}/replies?p=1
Authorization: Bearer {{token}}
Accept: application/json

### 置顶主题
POST {{baseUrl}}/topics/{{topicId}}/set-sticky?duration=15min
Authorization: Bearer {{token}}
Accept: application/json

### Boost 主题
POST {{baseUrl}}/topics/{{topicId}}/boost
Authorization: Bearer {{token}}
Accept: application/json

### 创建令牌
POST {{baseUrl}}/tokens
Authorization: Bearer {{token}}
Content-Type: application/json
Accept: application/json

{
  "scope": "regular",
  "expiration": 2592000
}
```

---

## 10. 错误处理建议

官方帮助页目前没有完整列出错误响应结构，因此客户端不要依赖未经验证的固定错误 JSON 字段。建议至少处理：

| HTTP 状态码 | 建议处理方式 |
|---|---|
| `400` | 检查路径参数、Query 参数及请求体 |
| `401` | 检查 Token 是否缺失、无效或过期 |
| `403` | 当前用户可能没有操作权限或不满足接口条件 |
| `404` | 节点、主题、回复或提醒不存在 |
| `429` | 请求过于频繁，读取 Rate Limit 响应头后重试 |
| `500`～`599` | 服务端异常，稍后重试并记录响应内容 |

推荐保留以下调试信息：

```text
HTTP method
Request URL
HTTP status
Response body
X-Rate-Limit-Limit
X-Rate-Limit-Remaining
X-Rate-Limit-Reset
```

不要在日志中输出完整 Authorization Header。

---

## 11. 注意事项

1. API 2.0 仍处于 Beta 阶段，生产环境应做好接口字段变化和兼容处理。
2. 官方帮助页未给出完整响应 JSON Schema，实际开发时应先用测试 Token 请求接口并保存样例响应。
3. Token 应保存在服务端环境变量、macOS/iOS Keychain 或其他安全存储中。
4. 不建议把 Personal Access Token 直接放进公开发布的 Web 前端代码。
5. 删除提醒、置顶主题和 Boost 主题属于写操作，调用前应在界面中向用户明确提示。
6. 分页接口当前使用 `p` 参数，默认页码为 `1`。
7. 路径中的节点名应进行 URL 编码。

---

## 12. 官方资料

- V2EX API 2.0 Beta：`https://www.v2ex.com/help/api`
- Personal Access Token：`https://www.v2ex.com/help/personal-access-token`
- API 讨论节点：`https://www.v2ex.com/go/v2exapi`
