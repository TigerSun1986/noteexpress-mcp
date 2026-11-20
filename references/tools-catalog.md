# NoteExpress MCP tool catalog

## Evidence and schema capture

The user's task brief supplied the 30 tool names and described a successful unversioned `tools/list` request. The original response was not present when the repository was first inspected. On 2026-11-20, this package captured the live local endpoint and checked in the complete paginated response, including each raw JSON-RPC response and each exact tool definition:

- [Live tools/list and noteexpress_version capture](tool-schemas/noteexpress-tools-20261120T030400Z.json)
- Captured endpoint: `http://127.0.0.1:49527/mcp`
- Tool count: 30; pages: 1
- The capture's `noteexpress_version` probe returned app `4.4.0.10931`, build `10931`, MCP protocol `2025-06-18`, server `1.0.0`, and 30 feature names.

Use the current AI client's live schemas for each action. The checked-in capture is a dated snapshot, not a promise that every NoteExpress release exposes the same tools. Refresh it on the NoteExpress Windows host:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tool-schema.ps1
```

The exporter follows pagination and validates the JSON-RPC envelope. `-ProbeVersion` calls only `noteexpress_version` with `{}` when advertised and its schema has no required arguments. It records the raw call response; it does not test other operations.

## Tool contracts from the live snapshot

“Required” below is the JSON Schema's `required` array. Conditional requirements and side effects are summarized from the matching live tool description. Open the JSON capture for the full exact `inputSchema` and description before constructing arguments.

| Tool | Required inputs | Key arguments, limits, defaults, or effects from the live description |
|---|---|---|
| `noteexpress_ping` | none | Read-only liveness; returns `ok`, `pong`, timestamp; does not touch the database or activate a library. |
| `noteexpress_version` | none | Returns application version/build, MCP protocol version, and registered feature list. |
| `noteexpress_get_server_status` | none | Optional `library_id`; reports signed-in user and active library; library ref count is unique whole-library total. |
| `noteexpress_list_libraries` | none | Lists currently open libraries. Passing `library_id` activates that open library before returning. |
| `noteexpress_open_library` | `library_path` | Opens a reachable `.ndb` or `.nel`; returns `library_id` but does not switch the active/working library. |
| `noteexpress_search_refs` | none in JSON Schema; description requires at least one of `title`, `author`, `doi`, `year`, `tags`, `keyword` | `summary_mode`, `page`, `page_size` (default 20, max 500), `order`, `order_by`, `recursive` (default true), optional `category_id` for regular folders. Does not search note bodies. Use `get_ref` for detail. |
| `noteexpress_list_refs` | none | Browse without filters. `category_id` omit/0/-3 means references root; positive ID must be a regular reference folder or a smart-leaf ID. Group smart folders return no items. `page_size` default 20, max 500; supports `summary_mode`, page, order, recursive. |
| `noteexpress_get_ref` | `uid` | UID is a GUID; `main_fields_only` defaults true. Returns fields, attachments, notes, and folders; jumps to the item in the NoteExpress UI. Top-level `id` is a database integer, never an attachment ID. |
| `noteexpress_list_categories` | none | Ordinary `ctRef` folder tree; includes built-in folders, not smart folders. Supports `root`, `max_depth`, `library_id`. |
| `noteexpress_list_smart_folders` | none | Smart-directory tree rooted at `-8`; nodes distinguish `group` from `smart_leaf`. Supports criteria/ref-count inclusion and depth. |
| `noteexpress_get_smart_folder` | none; exactly one of `smart_folder_id` or exact `title` | Reads criteria/count/children, not folder items. `title` matches a smart leaf. Use `list_refs` on a smart leaf; `itNote`/`itMind` may return no list items. |
| `noteexpress_get_note` | none; exactly one of `note_id` or `note_uid` | Reads note body as plain text. The exposed MCP tools do not create or update notes. |
| `noteexpress_create_ref` | none; `action` determines operation | `action=list_templates`, then `list_fields` with the real template, then `create` with Title keys from live fields. `dry_run` supported. Manually creates without SmartUpdate and jumps in UI. |
| `noteexpress_update_ref` | `action`, `uid` | Use `action=list_editable` before `action=update`; pass editable Title keys. `dry_run` supported. No SmartUpdate; editing may fail while SmartUpdate/editor guard is active. Jumps in UI. |
| `noteexpress_save_stub_refs` | `refs` | Each ref needs title and/or DOI. Queues online SmartUpdate; signed-in NoteExpress account required for online enrichment. May select first item in UI. Do not re-trigger SmartUpdate for the same UID. |
| `noteexpress_smart_update_refs` | `uids` | Existing refs only; 1–100 UIDs. Asynchronous by default; may require login. Avoid calling immediately after `save_stub_refs` for the same UID. |
| `noteexpress_import_pdf_ref` | `file_path` | Imports a new reference from a PDF on the NoteExpress Windows host; optional DOI, target folder, duplicate policy. Response `id` is a reference DB integer, not `attachment_id`; call `get_ref` to resolve PDF attachment IDs. |
| `noteexpress_import_formatted_refs` | `format` | `ris`, `bibtex`, `pubmed`, or `noteexpress`; provide `content` or host-side `file_path`. Optional `target_id` or `target_title`; max 1,000 records and 16 MiB. No built-in dedupe. |
| `noteexpress_export_refs` | `uids`, `format` | Formats `ris`, `bibtex`, `noteexpress`; `output` is `content` (default) or `file_path` on the NoteExpress host. |
| `noteexpress_attach_file` | `uuid`, `file_name` | `uuid` is the reference GUID (not argument `uid`); `file_name` is an absolute host path. Duplicate values: `use_existing`, `overwrite`, `rename`; `overwrite` needs confirmation. Per-UID SmartUpdate/editor guard applies. |
| `noteexpress_list_attaches` | `uid` | File/directory attachments have `id`; URL attachments have `url` and no ID. Use only a file's `attachments[].id` for PDF extraction/removal. |
| `noteexpress_remove_attach` | `uid`, `attachment_id` | Removes a file or directory attachment belonging to that UID; URL items cannot be removed with this tool. `attachment_id` must be the real attachment ID. |
| `noteexpress_extract_pdf_text` | `uid`, `attachment_id` | Optional `start_page`, `max_pages`, `max_chars`, `pdf_password`, `library_id`. Default extraction limit 200,000 chars; `max_chars=0` requests server hard max 2,000,000. PDF cap 64 MiB; at most two calls per HTTP JSON-RPC batch. Uses PDFium; no OCR. Can return partial text and `page_errors`; full-document empty extraction may report likely scan/unextractable text. |
| `noteexpress_create_category` | `title` | Optional `parent_id`, `library_id`; `auto_suffix` defaults true and resolves name conflicts with numeric suffix. Creates a user folder. |
| `noteexpress_update_category` | `category_id`, `title` | Renames user folder; does not change its parent. Built-in/virtual folders rejected. |
| `noteexpress_delete_category` | `category_id` | Deletes user-created folder; linked refs follow NoteExpress UI soft-delete/recycle-bin rules. Built-in/virtual folders rejected. Confirm exact target. |
| `noteexpress_link_refs` | `uids`, `to_category_id` | Adds references to a regular `ctRef` folder without removing source links; smart-folder IDs rejected. |
| `noteexpress_move_refs` | `uids`, `from_category_id`, `to_category_id` | Moves within one library; both IDs must resolve to regular `ctRef` folders (`-3` is references root); smart-folder IDs rejected. Removes the source link. |
| `noteexpress_dedupe_refs` | none | `dry_run` defaults true; `keep_policy=most_attachments` keeps the record with most PDF/file attachments (tie: newest `_modified`). `dry_run=false` soft-deletes extras to recycle bin; no metadata/attachment merge. |
| `noteexpress_delete_refs` | `uids` | Soft-delete/unlink behavior depends on `from_category_id`: omitted/0/-3 unlinks all folders and recycles; positive ID only unlinks that folder and recycles only if last link. Smart/search/recycler roots are rejected. Reports resolved/deleted/skipped/still-linked sets; blocked UID fails whole batch. |

## Cross-cutting identifier and state rules

- `uid` is a reference GUID; `uuid` is the argument name used by `noteexpress_attach_file` for that same reference GUID.
- Reference top-level `id` and list/search row `id` are database integers. They are never `attachment_id`.
- File attachment `id` comes from `attachments[]` for the target reference. URL attachments have no ID; note IDs are separate.
- Most tools without `library_id` use the active library. `get_server_status(library_id)` and `list_libraries(library_id)` may activate it; `open_library` does not switch active state.
- Folder IDs are typed: regular `ctRef` folder IDs and smart-folder group/leaf IDs are not interchangeable. Discover them with the corresponding list tool.
- Tool descriptions can contain conditional requirements not expressed in JSON Schema's `required` array. Follow both the live description and the input schema.

## Capabilities outside the 30-tool list

The live `noteexpress_create_ref` description supports `action=list_templates` and `action=list_fields`, followed by `action=create`; these are actions of the existing tool, not separate `list_templates`/`list_fields` tool names. The `initialize` response also advertises resources and prompts, but the supplied tool list contains no Word dynamic citation insertion tool. Do not claim that plain `[1]` text is an active NoteExpress citation field.
