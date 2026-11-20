# 文献库、分类与智能文件夹

执行操作前，先查看当前 schema 和实际返回的标识符。不要根据显示名称推测文献库、分类或智能文件夹 ID。

## 选择文献库

1. 使用 `noteexpress_list_libraries` 查找当前打开的文献库及其真实 ID。
2. 如果用户指定了文献库，将其与工具返回的明确文献库记录匹配。对支持该参数的工具传入 `library_id`。
3. 使用 `library_id` 前，阅读实时 `noteexpress_get_server_status` 描述；任务信息提示该操作可能会激活指定文献库。
4. 传入 `library_id` 前，阅读实时 `noteexpress_list_libraries` 描述；任务信息也提示该调用可能激活文献库。
5. 根据已提供的行为，`noteexpress_open_library` 会打开文献库，但本身不会切换当前活动文献库。对省略 `library_id` 的操作，应先确认当前服务端状态。

大多数工具在省略 `library_id` 时会操作当前文献库。不能仅因某个文献库已被打开或列出，就假定它已经成为活动文献库。如果目标不明确，或操作可能影响错误的活动文献库，应暂停并请用户选择。

## 分类和智能文件夹

- 普通分类使用 `noteexpress_list_categories`；智能文件夹使用 `noteexpress_list_smart_folders` 和 `noteexpress_get_smart_folder`。
- 两者是不同类型的对象。智能文件夹组 ID 不一定是有效的普通 `category_id`。
- 调用 `noteexpress_create_category`、`noteexpress_update_category`、`noteexpress_delete_category`、`noteexpress_link_refs` 或 `noteexpress_move_refs` 前，应查看实时 schema/描述中允许的 ID 范围和目标语义。
- `noteexpress_link_refs` 会新增分类关联，同时保留来源关联。根据任务提供的描述，`noteexpress_move_refs` 会将文献从来源分类中移除。操作前请核实实时语义以及准确的来源和目标。
- 在工具确认前，不要报告整理操作已成功。涉及较大范围时，先检查目标文献；如果当前工具支持 dry-run，先运行预览。

## 安全整理顺序

移动或关联记录时，先解析真实的文献 UID 和分类 ID，说明来源关联是否会保留，并确认目标文献库；然后只执行用户要求的操作。删除分类或批量移动前，应展示受影响的目标和后果，并取得用户明确确认。
