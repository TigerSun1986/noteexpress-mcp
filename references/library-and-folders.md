# Libraries, categories, and smart folders

Inspect the current schemas and returned identifiers before acting. Do not infer a library, category, or smart-folder ID from its display name.

## Choose a library

1. Use `noteexpress_list_libraries` to discover the available/open libraries and their real IDs.
2. If the user names a library, match it to an unambiguous returned library record. Pass `library_id` to each tool that supports it.
3. Read the live `noteexpress_get_server_status` description before using its `library_id`; the supplied task warns that this can activate the selected library.
4. Read the live `noteexpress_list_libraries` description before passing `library_id`; the supplied task also warns that this call can activate a library.
5. `noteexpress_open_library` opens a library but, according to the supplied behavior, does not itself switch the active library. Verify the current server status before operations that omit `library_id`.

Most tools may target the current library when `library_id` is omitted. Never assume a requested library became active just because it was opened or listed. If the target is ambiguous or an operation may affect the wrong active library, stop and ask the user to choose.

## Categories and smart folders

- Use `noteexpress_list_categories` for ordinary categories and `noteexpress_list_smart_folders` / `noteexpress_get_smart_folder` for smart folders.
- These are different object types. A smart-folder group ID is not automatically a valid ordinary `category_id`.
- Before `noteexpress_create_category`, `noteexpress_update_category`, `noteexpress_delete_category`, `noteexpress_link_refs`, or `noteexpress_move_refs`, check the live schema/description for allowed ID ranges and target semantics.
- `noteexpress_link_refs` adds a category association while retaining the source association. `noteexpress_move_refs` removes references from the source category as part of the move, per the supplied task description. Confirm the live semantics and exact source/target before use.
- Do not report a successful organization change until the tool confirms it. For broad changes, inspect the target references and use a dry-run if the current tool supports one.

## Safe folder sequence

For moving or linking records, resolve the actual reference UIDs and category IDs first; state whether the source association will remain; verify the intended library; then invoke only the requested operation. For category deletion or bulk moves, show the affected target and consequences and request explicit confirmation before the mutation.
