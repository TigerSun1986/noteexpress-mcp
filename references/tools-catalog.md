# NoteExpress MCP 工具目录

## 证据与 schema 快照

用户提供的任务说明列出了 30 个工具，并描述了一次成功的、未指定协议版本的 `tools/list` 请求。首次检查仓库时，原始响应并未保存在仓库中。2026-11-20，本包抓取了本机实时端点，并保存了完整的分页响应，包括每项原始 JSON-RPC 响应和每个工具的精确定义：

- [实时 tools/list 和 noteexpress_version 快照](tool-schemas/noteexpress-tools-20261120T030400Z.json)
- 抓取端点：`http://127.0.0.1:49527/mcp`
- 工具数量：30；分页数：1
- 快照中的 `noteexpress_version` 返回应用版本 `4.4.0.10931`、构建号 `10931`、MCP 协议 `2025-06-18`、服务端版本 `1.0.0`，以及 30 个功能名称。

每项操作都应使用当前 AI 客户端的实时 schema。仓库中保存的是带日期的快照，不保证其他 NoteExpress 版本提供完全相同的工具。请在 NoteExpress 所在的 Windows 主机上更新快照：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tool-schema.ps1
```

导出脚本会处理分页并验证 JSON-RPC 外层结构。只有当 `noteexpress_version` 已公布，且其 schema 没有必需参数时，`-ProbeVersion` 才会以 `{}` 调用该工具。脚本会保存原始调用响应；不会测试其他操作。

## 实时快照中的工具约定

下表中的“必需输入”来自 JSON Schema 的 `required` 数组。条件性要求和副作用则根据对应工具的实时描述总结。构造参数前，请打开 JSON 快照核对完整、精确的 `inputSchema` 和描述。

| 工具 | 必需输入 | 实时描述中的重要参数、限制、默认值或影响 |
|---|---|---|
| `noteexpress_ping` | 无 | 只读存活检查；返回 `ok`、`pong` 和时间戳；不会访问数据库或激活文献库。 |
| `noteexpress_version` | 无 | 返回应用版本/构建号、MCP 协议版本和已注册功能列表。 |
| `noteexpress_get_server_status` | 无 | 可选 `library_id`；报告登录用户和活动文献库；文献库文献数是全库去重后的总数。 |
| `noteexpress_list_libraries` | 无 | 列出当前已打开的文献库。传入 `library_id` 会先激活对应的已打开文献库，再返回结果。 |
| `noteexpress_open_library` | `library_path` | 打开可访问的 `.ndb` 或 `.nel` 文件；返回 `library_id`，但不会切换活动/工作文献库。 |
| `noteexpress_search_refs` | JSON Schema 中无必需项；描述要求至少提供 `title`、`author`、`doi`、`year`、`tags`、`keyword` 之一 | `summary_mode`、`page`、`page_size`（默认 20，最大 500）、`order`、`order_by`、`recursive`（默认 `true`）；普通分类可选传入 `category_id`。不会检索笔记正文。需要详情时使用 `get_ref`。 |
| `noteexpress_list_refs` | 无 | 可不加过滤条件直接浏览。省略 `category_id` 或传入 `0`/`-3` 表示文献根目录；正数必须是普通文献分类 ID 或智能文件夹叶节点 ID。智能文件夹组不会返回条目。`page_size` 默认 20，最大 500；支持 `summary_mode`、页码、排序和递归。 |
| `noteexpress_get_ref` | `uid` | UID 是 GUID；`main_fields_only` 默认 `true`。返回字段、附件、笔记和所属文件夹，并会在 NoteExpress 界面中跳转到该条目。顶层 `id` 是数据库整数，绝不是附件 ID。 |
| `noteexpress_list_categories` | 无 | 返回普通 `ctRef` 分类树，包含内置分类，不含智能文件夹。支持 `root`、`max_depth`、`library_id`。 |
| `noteexpress_list_smart_folders` | 无 | 返回以 `-8` 为根的智能目录树；节点区分 `group` 和 `smart_leaf`。支持包含筛选条件、文献数和深度。 |
| `noteexpress_get_smart_folder` | 无；`smart_folder_id` 和准确的 `title` 必须且只能提供一个 | 读取筛选条件、数量和子节点，不读取文件夹内文献。`title` 用于匹配智能文件夹叶节点。对智能叶节点使用 `list_refs`；`itNote`/`itMind` 可能没有列表项。 |
| `noteexpress_get_note` | 无；`note_id` 和 `note_uid` 必须且只能提供一个 | 以纯文本读取笔记正文。当前 MCP 工具不支持创建或更新笔记。 |
| `noteexpress_create_ref` | 无；实际操作由 `action` 决定 | 依次使用 `action=list_templates`、传入真实模板的 `action=list_fields`，再用实时字段返回的 Title 键执行 `action=create`。支持 `dry_run`。手动创建，不触发 SmartUpdate，并会在界面中跳转到记录。 |
| `noteexpress_update_ref` | `action`、`uid` | 先使用 `action=list_editable`，再执行 `action=update`；传入可编辑字段对应的 Title 键。支持 `dry_run`。不触发 SmartUpdate；SmartUpdate 或编辑器保护状态启用时可能无法编辑。会在界面中跳转到记录。 |
| `noteexpress_save_stub_refs` | `refs` | 每条文献需要标题和/或 DOI。会排队执行在线 SmartUpdate；在线补全需要 NoteExpress 账户已登录。可能会在界面中选中第一条记录。相同 UID 不要重复触发 SmartUpdate。 |
| `noteexpress_smart_update_refs` | `uids` | 仅用于已有文献；接受 1–100 个 UID。默认异步执行，可能要求登录。不要在 `save_stub_refs` 后立刻对同一 UID 再调用。 |
| `noteexpress_import_pdf_ref` | `file_path` | 从 NoteExpress Windows 主机上的 PDF 新增文献；可选 DOI、目标分类和重复项策略。响应中的 `id` 是文献数据库整数，不是 `attachment_id`；调用 `get_ref` 解析 PDF 附件 ID。 |
| `noteexpress_import_formatted_refs` | `format` | 支持 `ris`、`bibtex`、`pubmed` 或 `noteexpress`；提供 `content` 或主机侧 `file_path`。可选 `target_id` 或 `target_title`；最多 1,000 条记录、16 MiB。不内置去重。 |
| `noteexpress_export_refs` | `uids`、`format` | 支持 `ris`、`bibtex`、`noteexpress` 格式；`output` 可为 `content`（默认值），或 NoteExpress 主机上的 `file_path`。 |
| `noteexpress_attach_file` | `uuid`、`file_name` | `uuid` 是文献 GUID（参数名不是 `uid`）；`file_name` 是主机上的绝对路径。重复项策略为 `use_existing`、`overwrite`、`rename`；覆盖前须确认。该 UID 受 SmartUpdate/编辑器保护状态影响。 |
| `noteexpress_list_attaches` | `uid` | 文件/目录附件有 `id`；URL 附件只有 `url`，没有 ID。PDF 提取或移除时，只能使用文件的 `attachments[].id`。 |
| `noteexpress_remove_attach` | `uid`、`attachment_id` | 移除属于该 UID 的文件或目录附件；不能用此工具移除 URL 条目。`attachment_id` 必须是实际附件 ID。 |
| `noteexpress_extract_pdf_text` | `uid`、`attachment_id` | 可选 `start_page`、`max_pages`、`max_chars`、`pdf_password`、`library_id`。默认提取上限 200,000 字符；`max_chars=0` 表示请求服务端硬上限 2,000,000。PDF 上限 64 MiB；每个 HTTP JSON-RPC 批次最多两次调用。使用 PDFium，不支持 OCR。可能返回部分文本和 `page_errors`；整份文档没有提取到文本时，可能提示它是扫描件或无法提取。 |
| `noteexpress_create_category` | `title` | 可选 `parent_id`、`library_id`；`auto_suffix` 默认 `true`，发生重名时会自动添加数字后缀。创建用户分类。 |
| `noteexpress_update_category` | `category_id`、`title` | 重命名用户分类，不改变父级。内置分类/虚拟分类不允许修改。 |
| `noteexpress_delete_category` | `category_id` | 删除用户创建的分类；关联文献遵循 NoteExpress 界面的软删除/回收站规则。内置分类/虚拟分类不允许删除。操作前确认准确目标。 |
| `noteexpress_link_refs` | `uids`、`to_category_id` | 将文献关联到普通 `ctRef` 分类，同时保留来源关联；不接受智能文件夹 ID。 |
| `noteexpress_move_refs` | `uids`、`from_category_id`、`to_category_id` | 在同一文献库内移动；两个分类 ID 都必须是普通 `ctRef` 分类（`-3` 表示文献根目录）；不接受智能文件夹 ID。移动后会移除来源关联。 |
| `noteexpress_dedupe_refs` | 无 | `dry_run` 默认 `true`；`keep_policy=most_attachments` 会保留 PDF/文件附件最多的记录（并列时保留 `_modified` 最新者）。`dry_run=false` 会把多余记录软删除到回收站；不会合并元数据或附件。 |
| `noteexpress_delete_refs` | `uids` | 软删除/取消关联行为取决于 `from_category_id`：省略、`0` 或 `-3` 会取消所有分类关联并移入回收站；正数只取消该分类关联，且只有在没有其他关联时才移入回收站。拒绝智能搜索/回收站根目录。会报告已解析、已删除、已跳过和仍有关联的记录集合；遇到被阻止的 UID 时整批失败。 |

## 通用标识符和状态规则

- `uid` 是文献 GUID；`noteexpress_attach_file` 使用参数名 `uuid` 表示同一个文献 GUID。
- 文献顶层 `id` 以及列表/搜索结果行中的 `id` 都是数据库整数，绝不是 `attachment_id`。
- 文件附件的 `id` 来自目标文献的 `attachments[]`。URL 附件没有 ID；笔记 ID 也与附件 ID 不同。
- 大多数未传 `library_id` 的工具会操作活动文献库。`get_server_status(library_id)` 和 `list_libraries(library_id)` 可能会激活指定文献库；`open_library` 不会切换活动文献库。
- 文件夹 ID 有类型区别：普通 `ctRef` 分类 ID 与智能文件夹组/叶节点 ID 不能互换。请使用对应的列表工具查询。
- 工具描述可能包含 JSON Schema `required` 数组未表达的条件性要求。两者都必须遵循。

## 30 个工具列表之外的能力

实时 `noteexpress_create_ref` 描述支持 `action=list_templates` 和 `action=list_fields`，之后再执行 `action=create`；这些是现有工具的不同操作，不是独立的 `list_templates`/`list_fields` 工具。`initialize` 响应还公布了资源和提示，但已提供的工具列表中没有用于 Word 动态引文插入的工具。不要声称普通文本 `[1]` 是有效的 NoteExpress 引文域。
