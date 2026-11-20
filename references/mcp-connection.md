# MCP 连接与兼容性

## NoteExpress 服务端点证据

本项目收到的任务信息记录了一次成功的 Windows PowerShell 请求：

- 进程：`NoteExpress.exe`（常见路径：`C:\Program Files\NoteExpress\NoteExpress.exe`）
- 主机和端口：`127.0.0.1:49527`
- URL：`http://127.0.0.1:49527/mcp`
- 请求：HTTP POST，`Content-Type: application/json`，JSON-RPC 2.0 方法 `tools/list`，`params` 为空
- 结果：`result.tools` 中包含 30 个工具定义，每项都有 `name`、`description` 和 `inputSchema`

任务中最初粘贴的响应没有保存在仓库中。本包随后抓取了本机实时端点，快照见 [tools/list 和版本信息](tool-schemas/noteexpress-tools-20261120T030400Z.json)。文件包含一页原始 `tools/list` 响应、全部 30 个工具的精确定义，以及原始 `noteexpress_version` 调用响应。快照对应特定版本；每次操作仍应以当前客户端提供的实时 schema 为准。

## 协议版本范围

实时 `noteexpress_version` 响应显示 NoteExpress `4.4.0.10931`（构建号 `10931`）、MCP 协议 `2025-06-18`、服务端版本 `1.0.0`。兼容性探测随后按 `2025-06-18` 完成了标准协议流程：发送 `initialize`，收到匹配的 `protocolVersion`，发送 `notifications/initialized`（HTTP 202），再通过 `MCP-Protocol-Version: 2025-06-18` 请求头取得包含 30 个工具的 `tools/list`。通过 `tools/call` 调用 `noteexpress_ping` 也成功。

同一端点也接受最初测试过的普通 `tools/list` POST，无需先初始化或添加协议请求头。健康检查保留了这个已验证且快速的请求；使用 `2025-06-18` 协议的客户端则可以采用已验证的标准握手。这些测试只证明上述特定请求成功，不代表完全符合协议，也不代表所有工具都能调用成功。当前官方 MCP 规范修订版为 `2026-07-28`；不要据此推断这个较旧协议版本的服务端实现了全部最新行为。

不要仅凭对 MCP 的一般假设，就在 Guard 中添加 `initialize` 请求。已安装的服务端会明确报告协议版本，标准初始化流程也已实际测试。但仅凭 `tools/list`、`initialize` 和 `ping`，仍不能声称服务端完全符合当前规范。应按服务端公布的实时 schema 读取 `noteexpress_version`，并将其中的 `mcp_protocol` 字段视为服务端明确报告的协议版本。

官方参考：

- [当前 MCP 规范](https://modelcontextprotocol.io/specification/2026-07-28)
- [当前协议版本与旧版本兼容说明](https://modelcontextprotocol.io/specification/draft/basic/versioning)
- [2025-06-18 生命周期](https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle)
- [2025-06-18 Streamable HTTP 传输](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)
- [2025-06-18 工具规范](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [2025-11-25 生命周期](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
- [MCP 工具的列出与调用](https://modelcontextprotocol.io/specification/draft/server/tools)

## 健康检查行为

请在运行 NoteExpress 的 Windows 电脑上执行脚本，不要在无关的远程 Agent 上运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-ne-mcp.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-ne-mcp.ps1 -Json
```

脚本会检查所有 `NoteExpress.exe` 进程和端口 49527 的所有监听记录，核对每个监听者 PID，测试回环 TCP 连接，并发送已观测到的 JSON-RPC `tools/list` 请求。如果 `Get-NetTCPConnection` 不可用或被拒绝，脚本会改为解析 `netstat.exe -ano -p tcp`；如果两种方式都无法确认端口归属，状态会保持为未知。脚本不会启动 NoteExpress，也不会终止任何进程。

| 状态 | 退出码 | 含义 |
|---|---:|---|
| `READY` | 0 | 所有已观测到的监听记录都属于 NoteExpress，且非空、有效的工具列表包含三个 Guard 必需工具。 |
| `NO_PROCESS` | 1 | 未发现 NoteExpress 进程，端点也未开放。 |
| `PROCESS_RUNNING_PORT_CLOSED` | 2 | NoteExpress 正在运行，但无法连接端口 49527。 |
| `PORT_CONFLICT` | 3 | 至少一条监听记录属于其他进程。 |
| `PORT_OWNER_UNKNOWN` | 4 | TCP 可连接，但无法取得或确认端口归属；即使工具发现成功，也不会因此升级为 `READY`。 |
| `HTTP_UNAVAILABLE` | 5 | TCP 可连接或存在监听记录，但 MCP HTTP 请求未能成功完成，包括超时和 HTTP 失败。 |
| `MCP_INVALID_RESPONSE` | 6 | 响应正文不是带有匹配请求 ID 和预期结果结构的有效 JSON-RPC 2.0。 |
| `MCP_TOOLS_MISSING` | 7 | `tools/list` 未返回工具，或缺少 Guard 必需工具。 |
| `MCP_CALL_FAILED` | 8 | `tools/list` 返回 JSON-RPC 错误，或可选的 ping 探测失败。 |
| `CHECK_ERROR` | 9 | 无法检查进程表，或 Guard 自身运行出错。 |

JSON 输出会分别报告进程和路径、监听查询、TCP 连接、端口归属、`tools/list`、工具结构、必需工具、ping，以及客户端工具注册情况。客户端注册检查始终为 `NOT_CHECKED`；脚本无法读取 AI 应用当前启用的工具列表。

### Ping 探测

最初的任务证据只确认了 `tools/list`；之后的实时检查才验证了 `noteexpress_version` 和 `noteexpress_ping` 的 `tools/call`。为保持默认检查精简，Guard 默认跳过 ping。只有当前工具列表中公布了 ping，且其 schema 没有必需参数时，`-ProbePing` 才会调用它。对本机端点的只读兼容性探测还验证了标准 initialize 流程和这两项调用。

## 服务、客户端与 Skill 状态

请分别检查以下三项：

1. **Skill 已加载：** 客户端发现了本 `SKILL.md`，并且能读取其中的参考文档。
2. **MCP 已注册：** 客户端配置了 MCP 服务，并向当前会话提供相应的 `noteexpress_*` 工具。
3. **服务健康：** Windows 主机上的检查返回了当前状态。

其中任意一项都不能证明另外两项成立。健康检查为 `READY` 无法修复客户端缺少 MCP 配置的问题；客户端能看到 Skill 也不代表它已获得 MCP 访问权限。

## 本机回环地址的边界

如果 Agent 运行在另一台电脑、容器或云端会话中，它访问的 `127.0.0.1` 指向 Agent 自己的运行环境，而不是装有 NoteExpress 的 Windows 电脑。请明确确认实际连接路径。只使用用户可控且安全的主机桥接，或获准在主机侧运行的工具。不要把 NoteExpress 服务绑定到公共网络接口，也不要将端口 49527 暴露到互联网。

客户端配置方法见 `README.md`。安装器只复制 Skill 文件，不会写入客户端的 MCP 配置。
