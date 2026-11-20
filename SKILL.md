---
name: noteexpress-mcp
description: 适用于通过 NoteExpress MCP 工具检索、阅读、整理、导入、导出或编辑文献，也适用于诊断 NoteExpress MCP 连接。要求当前 AI 客户端已注册 NoteExpress MCP 工具，并且能够连接运行 NoteExpress 的 Windows 电脑。
compatibility: NoteExpress MCP 在 Windows 上运行，地址为 127.0.0.1:49527。随附的健康检查需要在同一台 Windows 主机上使用 Windows PowerShell 5.1 或更高版本。
---

# NoteExpress MCP

本 Skill 面向已经接入 NoteExpress MCP 的 AI 客户端，提供操作指引。它本身不是 MCP 服务端，也不能强制或拦截客户端的工具调用。

## 必要时先确认连接

首次使用、连接报错后，或用户要求诊断时：

1. 确认 AI Agent 实际运行在哪里。`127.0.0.1` 指 Agent 所在的机器或容器；远程 Agent 无法通过自己的回环地址连接用户的 Windows 电脑。
2. 如果 Agent 能在运行 NoteExpress 的 Windows 主机上执行命令，从本 Skill 目录运行 `scripts/check-ne-mcp.ps1 -Json`。连接错误后再检查一次；不要在每次调用 NoteExpress 工具前都启动 PowerShell。
3. 分别解读每项检查。`READY` 表示监听端口归属已确认是 NoteExpress，且服务返回了包含必需工具的有效 `tools/list` 响应；它不能证明当前 AI 客户端已注册这些工具，也不能证明所有工具调用都会成功。
4. 检查当前客户端实际提供的工具。如果没有 `noteexpress_*` 工具，说明 MCP 尚未注册，并引导用户查看 `references/mcp-connection.md`。不要自动修改客户端配置。
5. 如果 Agent 无法安全连接 Windows 主机，说明连接边界。不要把远程 Agent 的本地 `127.0.0.1` 当成用户的 Windows 电脑，也不要将端口暴露到公共互联网。

健康检查使用已观察到的 `tools/list` 请求格式，不会强制发送 `initialize` 握手。`ping` 默认不检查，因为已提供的证据确认了 `tools/list`，而 `tools/call` 是后续才验证的。

## 使用当前工具 schema

每次执行工作流前，确认所需工具当前已注册，并读取实际输入 schema。NoteExpress 版本升级后，工具及其 schema 可能变化。目录中的快照仅供参考；应以当前客户端提供的 schema 为准，并按需读取对应页面：

- 检索、新增、更新、去重、导入、导出和写作：`references/reference-workflows.md`
- PDF 提取和附件：`references/pdf-and-attachments.md`
- 文献库、分类、智能文件夹和移动：`references/library-and-folders.md`
- 删除或覆盖等高影响操作：`references/mutation-safety.md`
- 工具名称和 schema 快照：`references/tools-catalog.md`

严格遵循当前 schema。不要臆造参数名、标识符、模板名、字段键、分类、文献库 ID 或附件 ID。准确报告工具返回结果和错误；不要编造文献记录或 PDF 内容。

## 保护文献库

- 必要时先读取或检索，以确认目标；部分读取操作也可能改变 NoteExpress 当前文献库或界面选中项。
- 只执行用户要求的更改。批量操作可用 `dry_run` 时，先运行预览。
- 执行实际去重或删除前，先展示目标和影响并取得用户明确确认。覆盖附件前也要这样做。
- `link_refs` 会保留来源分类关联；`move_refs` 会从来源分类中移除文献。
- NoteExpress 文献 UID 和附件 ID 是不同的标识符。应从目标文献及其附件记录中解析 ID。
- `[1]` 这样的编号引文只是纯文本，除非 Word 集成实际创建了 NoteExpress 动态引文域。

## 检查连接状态是否仍然有效

不要永久缓存健康状态。在当前已连接会话中可复用近期成功的检查；遇到连接类错误或用户要求诊断时再检查。Skill 已加载、客户端已配置 MCP、服务端健康是三个不同条件。
