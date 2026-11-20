# Mutation and destructive-operation safety

Use the current client-exposed tool schema and description for every operation. A tool name alone does not establish its arguments, defaults, or side effects.

## General rules

- Treat a user's specific request to create or update records as authorization for that requested change, after resolving exact targets and validating fields.
- Prefer search/read first to establish the record set. When available, use `dry_run` before a bulk or otherwise high-impact operation and show the returned plan.
- Do not broaden the target set, change the active library, invent IDs, or retry an ambiguous timed-out mutation until checking whether it already took effect.
- Report exactly what the server confirms, including partial results, blocked records, and errors.

## Ask for confirmation before these actions

Before executing, provide the exact target and expected effect and obtain explicit confirmation for:

- `noteexpress_delete_refs` or `noteexpress_delete_category`;
- actual duplicate cleanup through `noteexpress_dedupe_refs`;
- overwriting an existing attachment with `noteexpress_attach_file`;
- any bulk operation whose target set or effect is unclear.

For deduplication, run `dry_run` first when supported. Show duplicate groups and the proposed keep policy. The supplied description of `most_attachments` selects a record with more attachments; it does not establish that metadata or attachments from another record will be merged. Confirm the current server description.

If the current schema does not offer a dry-run for a destructive operation, describe that limitation and get confirmation for the exact operation before proceeding. A generic earlier request such as “clean things up” does not confirm a specific deletion set.

## Never perform these actions automatically

- Do not terminate NoteExpress or another process using port 49527.
- Do not change the NoteExpress port, launch an unknown executable, or reinstall NoteExpress.
- Do not expose the loopback MCP endpoint to the public Internet.
- Do not silently change the active library or claim a local path exists on the Windows server.
- Do not represent a plain-text citation as a dynamic Word citation field.
