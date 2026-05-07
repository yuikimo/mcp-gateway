# MCP Gateway

## 简介

MCP Gateway 是一个反向代理服务器，用于将客户端请求转发到 MCP 服务器，或通过统一入口使用网关下的所有 MCP 服务器。

支持两种传输协议（启动时可切换）：

- **SSE**（默认，传统 MCP 传输方式）
- **Streamable HTTP**（MCP 规范）

## 功能特性

- 部署多个 MCP 服务器
- 连接到 MCP 服务器
- 通过网关调用 MCP 服务器
- 获取所有 MCP 服务器的 SSE 流
- 获取所有 MCP 服务器的工具（tools）
- 提供 Streamable HTTP 聚合端点，并通过 `Mcp-Session-Id` 头管理会话
- 动态能力聚合（网关只声明至少有一个下游 MCP 支持的能力）
- API Key 认证（Bearer token / query 参数）与基于会话的鉴权

## 安装

本地构建 Docker 镜像

```bash
docker build -t mcp-gateway .
```

## 使用

运行本地构建的 Docker 容器

```bash
docker run -d --name mcp-gateway -p 8080:8080 mcp-gateway
```

## 配置

网关会从配置目录读取 `config.json`（默认优先使用存在的 `./vm`，否则使用当前目录 `.`）。最小示例：

```json
{
    "LogLevel": 0,
    "Bind": "[::]:8080",
    "Auth": {
        "Enabled": true,
        "ApiKey": "123456"
    },
    "GatewayProtocol": "sse",
    "McpServiceMgrConfig": {
        "McpServiceRetryCount": 3
    }
}
```

关键字段说明：

| 字段 | 默认值 | 说明 |
| --------------------------------------- | ------------- | ---------------------------------------------------------------------------------- |
| `Bind`                                  | `[::]:8080`   | 服务监听地址。 |
| `GatewayProtocol`                       | `sse`         | 传输协议：`sse` 或 `streamhttp`。也可通过 `--protocol` 参数覆盖。 |
| `Auth.Enabled`                          | `true`        | 是否启用 API Key 认证。 |
| `Auth.ApiKey`                           | `123456`      | 客户端使用的 API Key。 |
| `SessionGCInterval`                     | `10s`         | 清理空闲代理会话的 GC 周期。 |
| `ProxySessionTimeout`                   | `1m`          | 代理会话空闲超时后会被 GC。 |
| `McpServiceMgrConfig.McpServiceRetryCount` | `3`        | MCP 服务失败后，标记为 `failed` 前的最大重试次数。 |

### 选择网关协议

方式 1：在 `config.json` 中设置 `GatewayProtocol`：

```json
{ "GatewayProtocol": "streamhttp" }
```

方式 2：通过 CLI 参数（优先级更高）：

```bash
./mcp-gateway --protocol=streamhttp
```

可选值：`sse`（默认）或 `streamhttp`。

## 认证

当 `Auth.Enabled` 为 `true` 时，每个请求都必须携带凭证。网关按以下顺序查找密钥：

1. `Authorization: Bearer <ApiKey>` 请求头
2. `?api_key=<ApiKey>` 查询参数
3. `?sessionId=<id>` 查询参数（仅在会话已创建后有效）
4. `Mcp-Session-Id: <id>` 请求头（Streamable HTTP 客户端）
5. `X-Session-Id: <id>` 请求头

典型使用方式：

- **长连接客户端（agent / Inspector）**：一次性配置 `Authorization: Bearer <ApiKey>`；网关也会在响应中传递会话标识，后续请求可按需不再携带 API Key。
- **浏览器 / 调试场景**：在 URL 后追加 `?api_key=<ApiKey>`。

`initialize`（会话中的首个请求）**必须**携带 API Key，因为此时还没有会话。

## API

### 部署（Deploy）

支持：`uvx`、`npx`，或 SSE URL。

```http
POST /deploy HTTP/1.1
Host: localhost:8080
Content-Type: application/json

{
    "mcpServers": {
        "time": {
            "url": "http://mcp-server:8080",  // url 和 command 二选一
            "command": "uvx",  // url 和 command 二选一
            "args": ["mcp-server-time", "--local-timezone=America/New_York"],  // 可选，command 的参数
            "env": {  // 可选，环境变量
                "KEY1": "VALUE1",
                "KEY2": "VALUE2"
            }
        }
    }
}
```

### 使用 MCP（SSE 模式）

> 当 `GatewayProtocol` 为 `sse`（默认）时可用。

#### GET SSE

```http
GET /{mcp-server-name}/sse HTTP/1.1
Host: localhost:8080
```

#### POST Message

```http
POST /{mcp-server-name}/message HTTP/1.1
Host: localhost:8080
Content-Type: application/json

{
    "method": "tools/call",
    "params": {
        "name": "get_current_time",
        "arguments": {
            "timezone": "Asia/Seoul"
        }
    },
    "jsonrpc": "2.0",
    "id": 2
}
```

### 使用网关（SSE 模式）

> 当 `GatewayProtocol` 为 `sse`（默认）时可用。

网关与直连 MCP 的区别在于：只需与网关交互，网关会自动将请求转发到对应 MCP 服务器。调用时需要在 method 前添加 `mcpServerName` 信息，以标识请求来自哪个 MCP 服务器。

#### GET SSE

```http
GET /sse HTTP/1.1
Host: localhost:8080
```

这里的 `sse` 是整个网关下所有 MCP 服务器的 SSE 聚合流。

当客户端订阅 `sse` 时，网关会为每个 MCP 服务器创建 SSE 连接，并将所有 SSE 流合并。

在所有 `tools/call` 响应结果中，method 前会添加 `mcpServerName`，标识结果来自哪个 MCP 服务器。

#### POST Message

```http
POST /message HTTP/1.1
Host: localhost:8080
Content-Type: application/json

{
    "method": "tools/call",
    "params": {
        "name": "{mcp-server-name}-get_current_time",
        "arguments": {
            "timezone": "Asia/Seoul"
        }
    },
    "jsonrpc": "2.0",
    "id": 2
}
```

获取网关下所有工具：

```http
POST /message HTTP/1.1
Host: localhost:8080
Content-Type: application/json

{
    "method": "tools/list",
    "jsonrpc": "2.0",
    "id": 1
}

# SSE 响应 message event

{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "{mcpServerName}-get_current_time",
        "description": "Get current time in a specific timezones",
        "inputSchema": {
          "type": "object",
          "properties": {
            "timezone": {
              "type": "string",
              "description": "IANA timezone name (e.g., 'America/New_York', 'Europe/London'). Use 'America/New_York' as local timezone if no timezone provided by the user."
            }
          },
          "required": [
            "timezone"
          ]
        }
      },
      {
        "name": "{mcpServerName}-convert_time",
        "description": "Convert time between timezones",
        "inputSchema": {
          "type": "object",
          "properties": {
            "source_timezone": {
              "type": "string",
              "description": "Source IANA timezone name (e.g., 'America/New_York', 'Europe/London'). Use 'America/New_York' as local timezone if no source timezone provided by the user."
            },
            "time": {
              "type": "string",
              "description": "Time to convert in 24-hour format (HH:MM)"
            },
            "target_timezone": {
              "type": "string",
              "description": "Target IANA timezone name (e.g., 'Asia/Tokyo', 'America/San_Francisco'). Use 'America/New_York' as local timezone if no target timezone provided by the user."
            }
          },
          "required": [
            "source_timezone",
            "time",
            "target_timezone"
          ]
        }
      }
    ]
  }
}
```

### 使用网关（Streamable HTTP 模式）

> 当 `GatewayProtocol` 为 `streamhttp`（通过配置或 `--protocol=streamhttp` 设置）时可用。
>
> 实现了规范 `2025-03-26` 定义的 MCP Streamable HTTP 传输。网关提供单一聚合端点 `/stream`，支持 `POST`、`GET`、`DELETE`。会话标识通过 `Mcp-Session-Id` HTTP 头传递。

#### 1. 建立会话（initialize）

```http
POST /stream HTTP/1.1
Host: localhost:8080
Authorization: Bearer 123456
Accept: application/json, text/event-stream
Content-Type: application/json

{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-03-26",
        "capabilities": {},
        "clientInfo": {"name": "my-client", "version": "1.0.0"}
    }
}
```

响应：

```http
HTTP/1.1 200 OK
Content-Type: application/json
Mcp-Session-Id: 7782f2f9-563c-4379-b961-df06e49e54c0

{
    "jsonrpc": "2.0",
    "id": 1,
    "result": {
        "protocolVersion": "2025-03-26",
        "serverInfo": {"name": "mcp-gateway", "version": "1.0.0"},
        "capabilities": { /* 从所有下游 MCP 服务按 OR 规则聚合 */ },
        "instructions": "MCP Gateway aggregates multiple MCP servers. Tools are namespaced as <serverName>_<toolName>."
    }
}
```

保存返回的 `Mcp-Session-Id`，并在后续每次请求中携带。

#### 2. 完成握手（notification）

```http
POST /stream HTTP/1.1
Host: localhost:8080
Authorization: Bearer 123456
Content-Type: application/json
Mcp-Session-Id: 7782f2f9-563c-4379-b961-df06e49e54c0

{"jsonrpc": "2.0", "method": "notifications/initialized"}
```

响应：`202 Accepted`（空响应体）。

#### 3. 调用工具或列出资源

```http
POST /stream HTTP/1.1
Host: localhost:8080
Authorization: Bearer 123456
Accept: application/json, text/event-stream
Content-Type: application/json
Mcp-Session-Id: 7782f2f9-563c-4379-b961-df06e49e54c0

{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
        "name": "{mcp-server-name}_get_current_time",
        "arguments": {"timezone": "Asia/Seoul"}
    }
}
```

聚合工具名格式为 `<serverName>_<toolName>`，与 SSE 网关模式一致。

响应会同步返回在 HTTP 响应体中：

```json
{"jsonrpc": "2.0", "id": 2, "result": { /* ... */ }}
```

通知消息（不带 `id` 的 JSON-RPC）会返回 `202 Accepted`，并异步转发。

#### 4. 订阅服务端主动事件（可选）

```http
GET /stream HTTP/1.1
Host: localhost:8080
Authorization: Bearer 123456
Accept: text/event-stream
Mcp-Session-Id: 7782f2f9-563c-4379-b961-df06e49e54c0
```

网关会保持连接并推送 `event: message` 帧，用于服务端 -> 客户端的 JSON-RPC **request** 和 **notification**（例如进度更新、日志消息）。JSON-RPC **response** 不会在这里推送，而是返回在发起对应 `POST /stream` 的 HTTP 响应中。

以 `:` 开头的行是 SSE keepalive 注释，可忽略。

#### 5. 关闭会话

```http
DELETE /stream HTTP/1.1
Host: localhost:8080
Authorization: Bearer 123456
Mcp-Session-Id: 7782f2f9-563c-4379-b961-df06e49e54c0
```

响应：`200 OK`。

#### 单服务透传

在 Streamable HTTP 模式下，也可以直接访问某个 MCP 服务：

```http
POST /{mcp-server-name} HTTP/1.1
GET  /{mcp-server-name} HTTP/1.1
```

网关会将请求转发到目标 MCP 的 `message` 端点。此模式下的会话管理由下游服务自行负责。

#### 使用 MCP Inspector 连接

1. 在 Inspector 中选择 **Transport Type**：`Streamable HTTP`。
2. URL 填写：`http://localhost:8080/stream`。
3. 在 *Configuration* -> *Custom Headers* 中添加：`Authorization: Bearer <ApiKey>`。
4. 点击 **Connect**。Inspector 会自动处理 `Mcp-Session-Id` 交换。
