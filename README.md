# NoteExpress MCP Skill

这是一个可复用的 Agent Skills 包，用于通过嵌入在 NoteExpress 中的 MCP 服务进行操作。包内含一个轻量的 Windows 主机健康检查，以及按需查阅的详细工作流文档。它不会实现另一个 MCP 服务，也不会修改 NoteExpress。

## 已验证内容

任务提供的 PowerShell 检查显示，向 `http://127.0.0.1:49527/mcp` 发送 JSON-RPC 2.0 `tools/list` 请求后，返回了 30 个工具。本包于 2026-11-20 抓取了实时端点；完整原始响应、精确 schema 和 `noteexpress_version` 结果保存在 `references/tool-schemas/noteexpress-tools-20261120T030400Z.json`。换用其他 NoteExpress 版本前，请通过随附的导出脚本更新快照。

实时版本工具报告 NoteExpress 4.4.0.10931、构建号 10931、MCP 协议 2025-06-18 和服务端版本 1.0.0。一次本机只读兼容性探测验证了 `initialize` → `notifications/initialized` → 带版本请求头的 `tools/list` 流程，也通过 `tools/call` 验证了 `noteexpress_ping`。这不代表所有工具均已验证。Guard 默认使用已观测到的 `tools/list` 快速检查；`-ProbePing` 为可选项。

## 包含内容

- `SKILL.md` — 简明的路由、连接和安全指引。
- `scripts/check-ne-mcp.ps1` — 适用于 PowerShell 5.1 的主机诊断脚本；根据状态返回对应退出码，并支持 `-Json`。
- `scripts/NeMcpGuard.psm1` — 健康检查所使用的实现模块。
- `scripts/export-tool-schema.ps1` — 抓取原始分页 `tools/list` 响应和解析后的 schema。可选的 `-ProbeVersion` 只会在 `noteexpress_version` 没有必需参数时调用该工具。
- `references/` — 按主题组织的工作流、限制、客户端设置、安全规则和故障排查说明。
- `examples/mcp-config.json` — 最简的 Cursor/Pi 风格 `mcpServers` URL 配置示例。Claude Code 的 JSON 配置还需要设置 `"type": "http"`；OpenCode 则使用带 `type: "remote"` 的 `mcp.servers`。

## 要求与限制

NoteExpress 内置 MCP 服务运行在 Windows 主机的 `127.0.0.1:49527`。健康检查脚本需要在运行 NoteExpress 的 Windows 主机上使用 Windows PowerShell 5.1 或 PowerShell 7。在其他操作系统上仍可使用本 Skill 的通用操作指引，但脚本无法检查 Windows 进程表。请只通过可信的主机命令，或确实在该 Windows 电脑上执行命令的安全桥接运行脚本。

如果安装 Skill 时本机未检测到 NoteExpress，安装器会提示用户前往 [NoteExpress 官网](https://www.inoteexpress.com/) 下载适用于该 Windows 电脑且包含 MCP 服务的版本。安装并启动 NoteExpress 后，还需确认服务已启用，并在 AI 客户端单独注册 MCP。

本机健康检查只验证一次 `tools/list` 请求。它不会读取 AI 客户端的 MCP 注册表，不会让当前会话自动出现全部 30 个工具，也不能证明每个工具都能成功调用。脚本会输出 `client_tool_registration: NOT_CHECKED`，以明确区分这两项检查。

## 安装 Skill

安装器只复制 Skill 文件，不会配置 MCP 服务。默认的用户级目标目录为 `~/.agents/skills/noteexpress-mcp`；能够发现该目录的 Codex、Cursor、OpenCode 和 Pi 安装可以共用它。

```powershell
# 共用的 Agent Skills 目录（Codex、Cursor、OpenCode、Pi）
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# Claude Code 用户级 Skill 目录
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Client ClaudeCode

# 指定其他 Skills 根目录；安装器会在其下追加 noteexpress-mcp
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -TargetDirectory 'D:\AgentSkills'

# 保留旧版 NeCode 的 Windows 路径和 Skill ID
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Client NeCode
```

如果目标目录已存在，请先检查内容。传入 `-Force` 可替换本包对应的文件。安装器不会删除用户添加的文件、更新 MCP 设置或结束 NoteExpress 进程。使用 `-WhatIf` 可预览目标路径。

卸载时使用相同的客户端选项或目标目录：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -Client ClaudeCode
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -TargetDirectory 'D:\AgentSkills'
```

卸载器会先验证 Skill 的 frontmatter，再删除对应 Skill 目录。它不会修改任何客户端 MCP 配置。卸载器支持 `-WhatIf`，并会在删除前询问确认。

## 客户下载

正式发布时，请从 GitHub Releases 下载 `noteexpress-mcp-v版本号.zip`。这是按安装所需文件生成的精简包，不含测试目录和维护者构建文件。GitHub 页面提供的 Source code 压缩包对应完整源码仓库，包含维护者文件，不作为客户安装包。

## 单独注册 NoteExpress MCP

安装或加载 Skill 并不会配置 MCP 服务。请根据 Agent 运行的客户端和环境选择对应配置方式。检查并自行应用配置；安装器不会修改它。

### Codex

在运行 NoteExpress 的 Windows 电脑上，使用 Codex CLI，或编辑 `config.toml`：

```powershell
codex mcp add ne-mcp --url http://127.0.0.1:49527/mcp
codex mcp list
```

也可以在现有的 `~/.codex/config.toml` 中添加以下配置，并保留其他设置：

```toml
[mcp_servers.ne-mcp]
url = "http://127.0.0.1:49527/mcp"
```

### Claude Code

```powershell
claude mcp add --transport http --scope user ne-mcp http://127.0.0.1:49527/mcp
claude mcp list
```

在会话中使用 `/mcp` 查看连接状态和可用工具。

### Cursor

Cursor 支持将 MCP JSON 配置写入项目级 `.cursor/mcp.json` 或用户级 `~/.cursor/mcp.json`。将以下条目添加到已有的 `mcpServers` 对象中，不要覆盖其他服务：

```json
{
  "mcpServers": {
    "ne-mcp": {
      "url": "http://127.0.0.1:49527/mcp"
    }
  }
}
```

### OpenCode

OpenCode 在 `opencode.json` 或 `opencode.jsonc` 中使用 `mcp.servers` 对象，也支持 `opencode mcp add`：

```powershell
opencode mcp add ne-mcp --url http://127.0.0.1:49527/mcp
opencode mcp list
```

OpenCode 允许配置 MCP 协议行为。我们已直接测试 NoteExpress 端点的标准 `2025-06-18` 握手，但尚未验证 OpenCode 客户端集成。如果连接失败，请检查 OpenCode 的连接错误和 `references/mcp-connection.md`；不要凭猜测更改协议模式。

### Pi

Pi 支持 `mcpServers` JSON 配置和 CLI 注册：

```powershell
pi mcp add ne-mcp --url http://127.0.0.1:49527/mcp
pi mcp list
```

Pi 会在自己的工具命名空间中注册 MCP 工具。请使用当前 Pi 会话实际提供的工具名称和 schema。

### NeCode

`install.ps1 -Client NeCode` 会保留旧版 Windows Skills 目录和 `ne-mcp-guard` Skill ID。旧路径来自原仓库安装器；NeCode 当前文档没有公开该确切路径，因此请在 NeCode 的 Skills 界面中确认安装结果。本包不会修改 NeCode 客户端配置或内嵌 MCP 设置。

## 客户端能力对照

| 客户端 | 安装器使用的 Skill 目录 | MCP 设置方式 |
|---|---|---|
| Codex | `~/.agents/skills/noteexpress-mcp` | `codex mcp add` 或 `~/.codex/config.toml` |
| Cursor | `~/.agents/skills/noteexpress-mcp` | `~/.cursor/mcp.json` 或 `.cursor/mcp.json` |
| Claude Code | `~/.claude/skills/noteexpress-mcp` | `claude mcp add --transport http` |
| OpenCode | `~/.agents/skills/noteexpress-mcp` | `opencode mcp add`；直接协议探测已通过，OpenCode 客户端集成尚未验证 |
| Pi | `~/.agents/skills/noteexpress-mcp` | `pi mcp add` |
| NeCode | 旧版 `%APPDATA%\ai.necode.desktop\xdg-config\necode-desktop\skills\ne-mcp-guard` 路径 | 继续在 NeCode 界面/配置中设置 MCP；目前尚未核实它的确切路径 |

符合 Agent Skills 格式只表示客户端能够发现 `SKILL.md` 所在目录；这不能证明 MCP 客户端已完成配置、客户端能运行 PowerShell，或它能够连接 Windows 主机。远程 Agent 的回环 URL 指向远程运行环境本身。需要时使用安全且受支持的主机桥接；不要把 NoteExpress 的回环端口公开到互联网。

本包路径和设置说明所参考的客户端官方文档：

- [Agent Skills 格式](https://agentskills.io/specification)
- [Codex Skills](https://learn.chatgpt.com/docs/build-skills) 和 [Codex MCP 设置](https://developers.openai.com/learn/docs-mcp)
- [Cursor Skills](https://cursor.com/docs/skills) 和 [Cursor MCP 设置](https://cursor.com/docs/mcp)
- [Claude Code Skills](https://code.claude.com/docs/en/skills) 和 [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [OpenCode Skills](https://opencode.ai/docs/skills) 和 [OpenCode MCP](https://opencode.ai/docs/mcp-servers)
- [Pi Skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md) 和 [Pi MCP](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md)

## 抓取实时工具 schema

本包在 `references/tool-schemas/` 中包含一份带日期的 30 工具快照。抓取并保存更新后的服务端快照：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tool-schema.ps1
```

脚本会在 `references/tool-schemas/` 下生成带时间戳的 JSON 快照。如需额外调用已公布的 `noteexpress_version` 工具并传入空参数（前提是 schema 允许），执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tool-schema.ps1 -ProbeVersion
```

这个可选操作只调用 `noteexpress_version`，不代表其他工具调用成功。仓库中的响应明确报告 `mcp_protocol: 2025-06-18`；兼容性探测结果见 `references/mcp-connection.md`。
