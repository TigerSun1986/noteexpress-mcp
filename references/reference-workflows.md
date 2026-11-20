# 文献操作流程

开始工作流前，先确认当前 AI 客户端提供所需的 `noteexpress_*` 工具，并查看实时 schema。如果缺少所需工具或参数，应说明限制；只有实时 schema 支持时才采用替代方式。仅在首次使用、发生连接类错误或用户要求诊断时，运行 Windows Guard。不要在每次 MCP 调用前重复执行 PowerShell 预检查。

## 检索文献

例如用户提出“查找 NoteExpress 中有关人工智能的文献”：

1. 按 `mcp-connection.md` 中的说明检查连接。
2. 只有当前客户端确实列出了 `noteexpress_search_refs`，才调用该工具。
3. 根据实际 schema 使用受支持的条件，例如关键词、标题、作者、DOI、年份或标签。不要猜测参数名。
4. 如果当前 schema 支持 `summary_mode=true`，且用户只需要检索摘要，优先使用该模式。
5. 按工具公布的分页字段或游标继续读取，直到达到用户要求的结果范围。保留每页实际返回的记录；不要虚构总数或缺失记录。
6. 只对已返回的文献 UID 使用 `noteexpress_get_ref` 获取详情。
7. 如实报告 NoteExpress 返回内容，包括空结果或不完整的检索。分页未完成时，不要编造引文，也不要声称已穷尽所有结果。

## 浏览和读取记录

- 用户要求浏览指定文献库或分类，或列出一页记录时，使用 `noteexpress_list_refs`。先查看 schema，确认实际的分页和筛选参数。
- 只有在 UID 由 NoteExpress 工具返回，或由用户提供并已在目标文献库中确认时，才使用 `noteexpress_get_ref`。
- 只有取得真实的笔记标识符后，才使用 `noteexpress_get_note` 读取笔记。当前提供的工具列表没有创建或更新笔记的工具。
- 传入 `library_id`、分类 ID 或智能文件夹标识符前，先阅读 `library-and-folders.md`。

## 新增文献

先查看当前可用的相关工具，并使用受支持的检索或查重方式，避免重复新增。

| 用户提供的信息 | 任务说明中的候选方式 |
|---|---|
| 只有标题或 DOI | `noteexpress_save_stub_refs` |
| 结构化字段和已知模板 | 先解析实时模板与字段定义，再使用 `noteexpress_create_ref` |
| RIS、BibTeX、PubMed 或其他受支持的格式化内容 | `noteexpress_import_formatted_refs` |
| 位于 NoteExpress Windows 主机上的本地 PDF 文件 | `noteexpress_import_pdf_ref` |

实时 `noteexpress_create_ref` 描述提供了 `action=list_templates`、`action=list_fields` 和 `action=create`。按此顺序多次调用同一个工具，每次只传入前一步实际返回的模板和字段。不要臆造模板名或内部字段键。如果新版 NoteExpress 移除了这些操作，应说明哪条新增文献路径因此不可用。

`noteexpress_save_stub_refs` 可能会排队执行 SmartUpdate。检查实时工具描述并报告返回状态；除非服务端确认，否则不要声称元数据补全已经完成。

## 更新文献

1. 解析并确认目标文献 UID。
2. 只有当前 schema 或描述明确支持 `action="list_editable"` 时，才用 `noteexpress_update_ref` 执行该操作。
3. 根据返回的 Title 键选择可编辑字段。不要从用户看到的标签推断内部字段名。
4. 如果实时 schema 支持 dry-run 或验证操作，先预览再应用更改。
5. 执行用户要求的更改，并准确报告已修改字段或被阻止的 UID。

## 文献去重

1. 如果当前工具列表公布了 `noteexpress_dedupe_refs`，先检查它的实时输入 schema 和描述。
2. 支持 `dry_run` 时先运行预览，展示重复组和拟采用的保留规则。
3. 在用户明确确认具体目标范围和规则前，不要执行真实清理。
4. 当前抓取的工具描述显示，`keep_policy="most_attachments"` 会保留 PDF/文件附件最多的记录；附件数相同时保留 `_modified` 较新的记录。该操作不会合并元数据或附件。执行前请核实已安装服务端的当前描述。
5. 用户确认后，只执行已审核的操作，并报告工具结果。如果不支持 dry-run，应说明删除影响并先征求确认。

## 导入和导出

- 只有当实时 schema 接受相应格式和输入结构时，才使用 `noteexpress_import_formatted_refs`。不要把文件转换成工具未公布支持的格式。
- 对位于 NoteExpress Windows 电脑上的本地 PDF 文件，使用 `noteexpress_import_pdf_ref`。远程 Agent 不应假设自己的文件路径能被服务端访问。
- 使用 `noteexpress_export_refs` 前，先确定准确的文献范围、目标路径或格式，以及 schema 规定的覆盖行为。如实报告返回的文件路径或错误。
- 导入请求超时且结果不明时，先检查首次请求是否已经新增记录，再考虑重试，以免重复导入。

## 写作和引文

撰写文献综述或参考文献表时，使用 NoteExpress 实际返回的标题、作者、年份、DOI、摘要和其他元数据。字段缺失时应明确标示不确定之处。当前提供的 30 个工具中没有明确的 Word 动态引文插入工具。`[1]` 这样的纯文本不属于链接到 NoteExpress 的引文域。如果用户要求通过 Word 插件插入引文，先确认是否存在另一个已实际注册的集成；否则提供注明为普通文本的引文或参考文献，不要伪装成动态引文。
