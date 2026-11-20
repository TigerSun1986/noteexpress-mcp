# PDF 阅读与附件管理

每次操作前先查看当前工具 schema。下列限制来自任务提供的 NoteExpress schema 描述；由于后续版本可能不同，实际操作前应重新核对实时描述。

## 阅读文献附件中的 PDF

1. 通过真实的检索/列表结果解析目标文献，或在目标文献库中确认用户提供的标识符。
2. 使用 `noteexpress_get_ref` 或 `noteexpress_list_attaches`，查看返回的 `attachments[]` 记录。
3. 选择实时元数据标记为文件或 PDF 附件的条目。如果实时 schema 要求传入附件标识符，就使用该条目的 `attachments[].id`。
4. 按 schema 要求，将真实文献 UID 和附件 ID 传给 `noteexpress_extract_pdf_text`。不要用数据库整数 `id`、笔记 ID 或臆造路径替代。
5. 只总结实际返回的文本。在答复中保留提取错误、页错误、截断信息和不确定性。

文献 `uid` 是 GUID，与数据库整数 `id` 和附件 ID 均不同。不要猜测本地文件路径：MCP 服务运行在 NoteExpress 所在的 Windows 主机上，由该服务解析自己的文件。

任务提供的 schema 描述指出：PDF 大小上限为 64 MiB，文本提取硬上限为 2,000,000 个字符，并且一次 HTTP JSON-RPC 批处理中最多执行两次 PDF 提取调用。依赖这些限制前，请先从当前 schema 或描述中再次核实。已确认服务端能解析 PDF，但没有证据表明支持 OCR。遇到扫描件、提取结果为空或部分失败时，应说明无法取得文本；如有需要，请用户提供可进行 OCR 的来源。不要根据标题或摘要补写缺失的文档内容。

## 添加附件

- 只有在确认目标文献，且确认源文件路径在运行 NoteExpress 的 Windows 电脑上真实存在后，才使用 `noteexpress_attach_file`。
- 任务提供的 schema 使用 `uuid` 作为文献标识参数，而不是 `uid`。遵循实时 schema，不要混用不同工具的 ID。
- 查看实时描述对 `on_duplicate` 的说明。已提供的值为 `use_existing`、`overwrite` 和 `rename`；不要在未查看当前描述前假定它们的具体效果。
- `overwrite` 可能破坏已有附件内容。调用前要和用户确认具体文献、附件和替换文件。
- 远程 Agent 可访问的路径不一定存在于运行 NoteExpress 的 Windows 主机上。不要擅自换成名称相似的本地文件。

## 列出或移除附件

使用 `noteexpress_list_attaches`，或查看 `noteexpress_get_ref` 返回的附件记录，取得真实附件 ID。调用 `noteexpress_remove_attach` 前，核实目标文献 UID 和该文献下准确的附件 ID，并向用户说明删除对象。移除附件属于破坏性操作；除非用户已明确确认要移除这一项，否则先征求确认。
