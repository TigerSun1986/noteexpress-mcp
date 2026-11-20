# Reference workflows

Before a workflow, confirm that the current AI client exposes the needed `noteexpress_*` tools and inspect their live schemas. If a required tool or argument is missing, explain the limitation and use a fallback only when its live schema supports it. Run the Windows Guard only on first use, after a connection-class error, or for a user-requested diagnosis. Do not repeat a PowerShell preflight before every MCP call.

## Search references

For a request such as “Find NoteExpress references about artificial intelligence”:

1. Check access as described in `mcp-connection.md`.
2. Call `noteexpress_search_refs` only if the live client lists it.
3. Use the actual schema to select supported constraints such as keyword, title, author, DOI, year, or tags. Do not send guessed parameter names.
4. Prefer `summary_mode=true` when the current schema supports it and the user only needs a search summary.
5. Follow the advertised pagination fields/cursor until the requested result range is reached. Keep each page's actual returned records; do not invent a total or a missing record.
6. Use `noteexpress_get_ref` for details only on returned reference UIDs.
7. Report what NoteExpress returned, including an empty result or an incomplete search. Never fabricate citations or claim the search was exhaustive if pagination was not completed.

## Browse and read records

- Use `noteexpress_list_refs` when the user asks to browse a known library/category or list a page of records. Read its schema for the actual page and filter parameters.
- Use `noteexpress_get_ref` only with a UID returned by a NoteExpress tool or supplied by the user and confirmed in that library.
- Use `noteexpress_get_note` for a note only when a real note identifier is obtained from NoteExpress. The supplied tool list has no note-create or note-update tool.
- Read `library-and-folders.md` before passing a `library_id` or a category/smart-folder identifier.

## Add a reference

First inspect the relevant current tools and use a supported search or duplicate-check method to avoid creating a duplicate.

| Input supplied | Candidate route from the task brief |
|---|---|
| Title or DOI only | `noteexpress_save_stub_refs` |
| Structured fields and known template | `noteexpress_create_ref`, only after resolving the live template and field definitions |
| RIS, BibTeX, PubMed, or another supported formatted source | `noteexpress_import_formatted_refs` |
| A local PDF file on the NoteExpress Windows host | `noteexpress_import_pdf_ref` |

The live `noteexpress_create_ref` description exposes `action=list_templates`, `action=list_fields`, and `action=create`. Call that same tool for each action in order, passing only a template and fields returned by the preceding action. Do not invent a template name or internal field key. If a later NoteExpress version removes these actions, explain which creation route is blocked.

`noteexpress_save_stub_refs` may queue SmartUpdate work; check its live description and report the returned status. Do not claim metadata enrichment is complete unless the server confirms it.

## Update a reference

1. Resolve and verify the target reference UID.
2. Use `noteexpress_update_ref` with `action="list_editable"` only if the current schema/description documents that action.
3. Select the editable field by the returned Title key. Do not infer internal field names from user-facing labels.
4. If the live schema supports a dry-run/validation action, use it before applying the edit.
5. Apply the change the user requested and report the exact fields changed or any blocked UIDs.

## Deduplicate

1. Use `noteexpress_dedupe_refs` if advertised and inspect its current input schema and description.
2. Run `dry_run` first when supported; show the duplicate groups and the proposed keep policy.
3. Do not execute a real cleanup until the user explicitly confirms the exact target set and policy.
4. In the captured live description, `keep_policy="most_attachments"` keeps the record with the most PDF/file attachments; ties keep the newest `_modified`. It does not merge metadata or attachments. Verify the installed server's current description.
5. After confirmation, execute only the reviewed operation and report the tool result. If no dry-run is supported, describe the deletion impact and ask before proceeding.

## Import and export

- Choose `noteexpress_import_formatted_refs` only for a format and input shape the live schema accepts. Do not convert a file to a format the tool does not advertise.
- Choose `noteexpress_import_pdf_ref` for a local PDF path that exists on the NoteExpress Windows computer. An agent running elsewhere must not assume its local path is visible to the server.
- Use `noteexpress_export_refs` only after resolving the exact reference set, destination/format, and any overwrite behavior from its schema. Report the returned output path or error.
- Do not retry an import after an ambiguous timeout until checking whether the first request created records; avoid duplicate imports.

## Writing and citations

Use real title, author, year, DOI, abstract, and other metadata returned by NoteExpress to support a literature review or bibliography. Keep uncertainty visible when fields are missing. The supplied 30 tools include no explicit Word dynamic citation insertion tool. Plain text such as `[1]` is not a NoteExpress-linked field. If the user requests Word plugin insertion, verify that a separate, actually registered integration exists before claiming it can be done. Otherwise offer correctly labeled reference text or bibliography output, not a fake dynamic citation.
