# PDF reading and attachment management

Always inspect the current tool schemas first. The limits below come from the task-provided NoteExpress schema description; recheck live descriptions because a later NoteExpress version may differ.

## Read a PDF attached to a reference

1. Resolve the reference from a real search/list result or a user-provided identifier confirmed in the target library.
2. Use `noteexpress_get_ref` or `noteexpress_list_attaches` and inspect the returned `attachments[]` records.
3. Select an entry whose live metadata identifies it as a file/PDF attachment. Pass that entry's `attachments[].id` as the PDF tool's attachment identifier, if that is what the live schema requests.
4. Call `noteexpress_extract_pdf_text` with the real reference UID and attachment ID required by its schema. Never substitute the database integer `id`, a note ID, or an invented path.
5. Summarize only text actually returned. Preserve extraction errors, page errors, truncation, and uncertainty in the answer.

The reference `uid` is a GUID. It is different from the database integer `id` and from the attachment ID. Do not guess a local file path: the MCP server runs on the NoteExpress Windows host and resolves its own files.

The supplied schema description states a 64 MiB PDF limit, a 2,000,000-character extraction hard limit, and a maximum of two PDF extraction calls in one HTTP JSON-RPC batch. Verify these constraints in the current schema/description before relying on them. Server-side PDF parsing is established; OCR support is not. For a scan, empty extraction, or partial failure, say that text was unavailable and ask for an OCR-capable source if needed. Never fill in missing document content from its title or abstract.

## Attach a file

- Use `noteexpress_attach_file` only after resolving the target reference and confirming the source path exists on the Windows computer running NoteExpress.
- The task-provided schema uses the argument name `uuid` for the reference, not `uid`. Follow the live schema and do not transpose IDs between tools.
- Check the live meaning of `on_duplicate`. The supplied values are `use_existing`, `overwrite`, and `rename`; do not assume their exact outcome without the current description.
- `overwrite` can destroy existing attachment content. Confirm the exact reference, attachment, and replacement with the user before invoking it.
- A path available to a remote agent may not exist on the Windows NoteExpress host. Do not silently substitute a similarly named local file.

## List or remove attachments

Use `noteexpress_list_attaches` or the attachment records returned by `noteexpress_get_ref` to identify real attachment IDs. Before `noteexpress_remove_attach`, verify both the target reference UID and the exact attachment ID from that reference, then describe the removal. Treat removal as destructive and ask for confirmation unless the user has already clearly confirmed that exact removal.
