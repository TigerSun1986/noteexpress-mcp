---
name: ne-mcp-guard
description: Use when 用户要用 NoteExpress MCP（ne-mcp）读/写题录、抽 PDF、导入导出，或 MCP 工具不可用需要排查时。只做一件事——检查 127.0.0.1:49527 是否由 NoteExpress 进程持有；不满足就停止任务并提示安装/启动。触发词：ne-mcp、NoteExpress MCP、NoteExpress 引文、题录、49527、noteexpress_、MCP 连不上、MCP 没反应。
---

# NoteExpress MCP 端口守卫

## 这个 skill 只做一件事

在调用任何 `noteexpress_*` 工具之前，先确认：本机 MCP 端口 `127.0.0.1:49527` 由 **NoteExpress** 进程持有。

- 满足 → 正常继续，用 `noteexpress_*` 工具干活。
- 否则 → **停止任务**，按脚本状态输出对应提示。

不负责：启动服务、改端口、换 host、用纯文本冒充引文、编造题录、替用户杀进程。

---

## 固定常量（不要改）

| 项 | 值 |
|---|---|
| Host | `127.0.0.1` |
| Port | `49527` |
| 进程名 | `NoteExpress` |
| MCP 地址 | `http://127.0.0.1:49527/mcp` |
| 安装/下载页 | `https://www.inoteexpress.com` |
| 默认安装位置 | `C:\Program Files\NoteExpress\NoteExpress.exe` |

NoteExpress 主程序内嵌 HTTP MCP；启动并打开文献库后监听 49527，工具名均为 `noteexpress_*`。

---

## 第一步：跑检查脚本（不要跳过）

安装位置固定，优先用绝对路径：

```
powershell -NoProfile -ExecutionPolicy Bypass -File "%APPDATA%\ai.necode.desktop\xdg-config\necode-desktop\skills\ne-mcp-guard\scripts\check-ne-mcp.ps1"
```

只有上面路径不存在时，才改用本 SKILL.md 所在目录下的 `scripts\check-ne-mcp.ps1`。

### 输出与退出码

| 输出 | 退出码 | 含义 |
|---|---|---|
| `STATUS=UP` | 0 | 端口归属 NoteExpress，可继续 |
| `STATUS=NO_PROCESS` | 1 | 无进程且端口未开 → 安装/启动 |
| `STATUS=STARTING` | 2 | 进程在跑但端口未开 → 稍等重试 |
| `STATUS=PORT_CONFLICT` | 3 | 端口被其它程序占用 |

`STATUS=UP` 时若多一行 `NOTE=port-owner-unverified`：当前系统取不到端口归属（旧版 Windows / 权限限制），已退化为「端口通 + 进程在」，结论仍可用。

---

## STATUS=UP 时

1. 确认会话里已挂载 NoteExpress MCP（能看到 `noteexpress_*` 工具名）。
2. **有工具** → 继续用户任务。  
   建议先轻量探活一次（任选其一，失败则提示重启 NoteExpress，不要自己起服务）：
   - `noteexpress_ping`
   - `noteexpress_get_server_status`
   - `noteexpress_version`（可拿到已注册工具名，便于能力协商）
3. **没有工具** → 客户端未配置 MCP。提示用户按下方「客户端配置」添加后重试。
4. 端口通但 `noteexpress_*` 调用报错 → 让用户重启 NoteExpress 后重跑本脚本；不要自己起服务。
5. 脚本本身跑不起来（找不到 powershell、策略拦截、非预期报错）→ 原样转述并停止，**不要**据此判断服务状态。

### 调用 noteexpress_* 时的硬规则

1. **题录主键用 uid（GUID）**，不要把整数 `id` 当成 PDF 的 `attachment_id`。
2. **抽 PDF**：先 `get_ref` 或 `list_attaches`，再用 `extract_pdf_text(uid, attachment_id)`；`attachment_id` 只能是 `attachments[].id`（file 类型）。
3. **笔记**：仅有 `noteexpress_get_note`（只读），**没有** create/update note 工具。
4. **删除**是软删（进回收站）；MCP 不暴露清空回收站。查重/批量删除优先 `dry_run`（若参数支持）再真实执行。
5. 部分写操作会跳转 NE UI；若返回 `blocked_uids`，提示用户关闭编辑器或等待 SmartUpdate 结束后再试。
6. 不要用纯文本 `[1]` 冒充库内引文；库不可用时停止生成带库内引用的正文。

### 能力速查（便于选工具，非本 skill 职责）

| 要做的事 | 优先工具 |
|----------|----------|
| 探活 / 当前库 | `ping`、`get_server_status`、`list_libraries` |
| 浏览文件夹 / 列表 | `list_categories`、`list_refs` |
| 条件搜索 | `search_refs`（至少给一个 title/author/doi/year/tags/keyword） |
| 单条详情 / 附件 | `get_ref`、`list_attaches` |
| 智能文件夹 | `list_smart_folders`、`get_smart_folder`；列表内容用 `list_refs(smart_leaf id)` |
| 新建（仅有 title/DOI） | `save_stub_refs`（会排队 SmartUpdate） |
| 新建（手工字段） | `create_ref`（先 list_templates / list_fields） |
| 改已有题录字段 | `update_ref`（先 list_editable） |
| 在线刷新元数据 | `smart_update_refs` |
| 从 PDF 建新题录 | `import_pdf_ref` |
| 挂附件到已有题录 | `attach_file` |
| 抽 PDF 正文 | `extract_pdf_text` |
| RIS/BibTeX/PubMed 导入 | `import_formatted_refs` |
| 导出 | `export_refs` |
| 查重 | `dedupe_refs`（先 dry_run） |

---

## STATUS=NO_PROCESS 时

停止一切写作/检索动作，只输出（可按用户语言微调措辞，事实不要改）：

> NoteExpress MCP 服务没有运行（127.0.0.1:49527 未监听）。
> 请先安装 NoteExpress（默认 `C:\Program Files\NoteExpress`，下载页 https://www.inoteexpress.com ），
> 再启动 `C:\Program Files\NoteExpress\NoteExpress.exe` 并打开需要的文献库。
> 启动后 MCP 会监听 49527；然后再让我继续。

然后结束本轮，等用户说「好了/启动了」再重跑脚本确认。

---

## STATUS=STARTING 时

NoteExpress 已在运行，HTTP 服务可能尚未起来（刚启动的几秒内正常）。

1. 等约 5 秒，重跑一次脚本。
2. 仍为 `STARTING` → 让用户看主窗口是否卡在启动/登录/升级提示，处理后再试。
3. 不要重复启动 NoteExpress，不要重装。

---

## STATUS=PORT_CONFLICT 时

49527 被非 NoteExpress 的进程占用。

只输出提示（不要自己杀进程）：

> 端口 49527 被其他程序占用，不是 NoteExpress。请在任务管理器结束占用该端口的进程后重启 NoteExpress。

需要证据时运行：

```powershell
Get-NetTCPConnection -LocalPort 49527 -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess
Get-Process -Id <上一步的 OwningProcess> | Select-Object Id,ProcessName,Path
```

---

## 客户端配置

会话里看不到 `noteexpress_*` 时，在 MCP 客户端中加入：

```json
{
  "mcpServers": {
    "ne-mcp": {
      "url": "http://127.0.0.1:49527/mcp"
    }
  }
}
```

若客户端要求显式 transport，选 Streamable HTTP 或 HTTP，URL 不变。前提：NoteExpress 已启动并打开文献库。

---

## 分发与安装（给人看的，不是给 AI 看的）

把整个 `ne-mcp-guard` 目录（或 zip）交给用户，解压后在该目录执行一次：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

脚本只复制到  
`%APPDATA%\ai.necode.desktop\xdg-config\necode-desktop\skills\ne-mcp-guard`，  
不动任何 MCP 配置。然后重启会话以加载 skill。

---

## 禁止

- 不要自己 `Start-Process` 启动服务，不要改端口、换 `localhost`/外网 IP。
- 不要把超时当成「服务正常」，不要重试超过 2 次。
- 不要由你执行结束进程的操作（含占用 49527 的进程），只提示用户在任务管理器处理。
- 端口未开或进程不在时，不要继续生成带库内引文的文档，也不要用 `[1]` 纯文本占位。
