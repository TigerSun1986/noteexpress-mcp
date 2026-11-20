# 故障排查

只在首次使用、发生连接类错误后，或用户要求诊断时，才在运行 NoteExpress 的 Windows 主机上执行 `scripts/check-ne-mcp.ps1 -Json`。JSON 中每项检查各自列出；`NOT_CHECKED` 不代表成功。

## Guard 状态

| 状态 | 含义 | 下一步 |
|---|---|---|
| `READY` | NoteExpress 进程拥有已观测到的监听端口，且 `/mcp` 返回了包含必需工具的有效 `tools/list`。 | 另行检查 AI 客户端实际注册的工具。这不能证明所有 `tools/call` 都能成功。 |
| `NO_PROCESS` | 未发现 NoteExpress 进程。 | 如果用户想使用 NoteExpress，请让用户自行打开程序。不要启动未知可执行文件。 |
| `PROCESS_RUNNING_PORT_CLOSED` | NoteExpress 正在运行，但预期端点未接受 TCP 连接。 | 检查 NoteExpress 中 MCP 服务是否已启用或仍在启动。启动后再次检查；不要更改端口。 |
| `PORT_CONFLICT` | 监听证据显示端口属于非 NoteExpress 进程，或归属存在冲突。 | 报告占用进程；不要结束进程，也不要仅凭 HTTP 请求成功就认定端口归属正确。 |
| `PORT_OWNER_UNKNOWN` | 无法确认监听端口的归属。 | MCP 响应本身可能表明它是 MCP 服务，但进程归属仍未核实。 |
| `HTTP_UNAVAILABLE` | TCP/HTTP 请求失败、返回非成功状态或超时。 | 如果服务可能仍在启动或关闭，可短暂等待后重试；随后报告传输错误。 |
| `MCP_INVALID_RESPONSE` | 响应不是请求 ID 匹配且包含结果的有效 JSON-RPC 2.0。 | 报告无法验证端点响应；不要判定服务健康。 |
| `MCP_TOOLS_MISSING` | `tools/list` 为空、格式错误或缺少必需工具。 | 抓取实时 schema，并检查 NoteExpress 版本和服务状态。 |
| `MCP_CALL_FAILED` | JSON-RPC 返回错误，或可选 ping 探测失败。 | 展示返回的错误。`tools/list` 仍可能单独正常。 |
| `CHECK_ERROR` | 诊断本身失败。 | 附上脚本错误；不要推断服务状态。 |

退出码：`READY` 为 `0`，`NO_PROCESS` 为 `1`，`PROCESS_RUNNING_PORT_CLOSED` 为 `2`，`PORT_CONFLICT` 为 `3`，`PORT_OWNER_UNKNOWN` 为 `4`，`HTTP_UNAVAILABLE` 为 `5`，`MCP_INVALID_RESPONSE` 为 `6`，`MCP_TOOLS_MISSING` 为 `7`，`MCP_CALL_FAILED` 为 `8`，`CHECK_ERROR` 为 `9`。

## 分别检查三项访问条件

1. Skill 可能已安装并加载。
2. AI 客户端可能已注册 `ne-mcp` 服务，也可能没有注册。
3. 正在运行的 NoteExpress 端点可能可从 Agent 运行环境访问，也可能不可访问。

逐项独立检查。远程或容器化客户端上的 `127.0.0.1` 指向该运行环境，而不是用户的 Windows 主机。如果有获准且安全的主机桥接，则使用该桥接。不要公开端口 49527。

## 更新工具定义

使用 `scripts/export-tool-schema.ps1` 抓取实时、分页的 `tools/list` 响应。抓取成功只能证明 schema 可获取，不能证明任意工具调用都能成功。只有当服务端公布了 `noteexpress_version`，且该工具 schema 允许空参数时，`-ProbeVersion` 才会调用它。协议版本证据和兼容性限制见 `mcp-connection.md`。
