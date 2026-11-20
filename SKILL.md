---
name: noteexpress-mcp
description: Use when searching, reading, organizing, importing, exporting, or editing references in NoteExpress through its MCP tools; also use when diagnosing a NoteExpress MCP connection. Requires this AI client to have NoteExpress MCP tools registered and to reach the Windows computer running NoteExpress.
compatibility: NoteExpress MCP runs on Windows at 127.0.0.1:49527. The bundled health check requires Windows PowerShell 5.1 or later on that same Windows host.
---

# NoteExpress MCP

This skill guides an AI client that already has access to NoteExpress MCP. It is not an MCP server and cannot force or intercept the client's tool calls.

## Establish access when needed

On first use, after a connection error, or when the user asks for diagnostics:

1. Identify where the AI agent is running. `127.0.0.1` means that machine or container. A remote agent cannot reach the Windows computer through its own loopback address.
2. If the agent can run a command on the NoteExpress Windows host, run `scripts/check-ne-mcp.ps1 -Json` from this skill directory. Run it again after a connection failure; do not launch PowerShell before every NoteExpress tool call.
3. Read each check separately. `READY` means the host process owns the observed listener and returned a valid `tools/list` response with required tools. It does not prove that this AI client registered those tools or that every tool call works.
4. Inspect the current client's available tools. If it has no `noteexpress_*` tools, explain that MCP registration is missing and direct the user to `references/mcp-connection.md`. Do not edit client configuration automatically.
5. If the agent cannot safely reach the Windows host, explain the boundary. Do not treat a local `127.0.0.1` URL on a remote agent as the user's Windows computer, and do not expose the port to the public Internet.

The health check uses the observed `tools/list` request shape and does not force an `initialize` handshake. Ping is opt-in because the supplied evidence confirms `tools/list`, not `tools/call`.

## Use the live tool schemas

Before each workflow, confirm the requested tool is currently registered and read its actual input schema. Tool availability and schemas may change with NoteExpress versions. The catalog summarizes the dated live snapshot in `references/tool-schemas/`; use the current client schema as the source of truth. Load only the relevant reference:

- Search, add, update, deduplicate, import, export, and writing: `references/reference-workflows.md`
- PDF extraction and attachments: `references/pdf-and-attachments.md`
- Libraries, categories, smart folders, and moves: `references/library-and-folders.md`
- Destructive or overwrite actions: `references/mutation-safety.md`
- Tool names and schema capture: `references/tools-catalog.md`

Follow the live schema exactly. Never invent argument names, identifiers, template names, field keys, categories, library IDs, or attachment IDs. Report real tool results and errors; do not fabricate records or PDF text.

## Protect the library

- Read and search first when that helps establish the target. Some reads can change NoteExpress's active library or visible selection.
- Perform only changes the user requested. Use `dry_run` when available for bulk operations.
- Before actual deduplication or deletion, show the target and effect and obtain explicit confirmation. Do the same before overwriting an attachment.
- `link_refs` retains the source category relation; `move_refs` removes it from the source.
- Treat NoteExpress reference UIDs and attachment IDs as different identifiers. Resolve IDs from the target reference and its file attachments.
- A numbered citation such as `[1]` is plain text unless an actual Word integration creates a dynamic NoteExpress citation field.

## Check freshness

Do not cache readiness permanently. Reuse a recent successful check during a connected session, and recheck on connection-class errors or a user-requested diagnosis. The skill being loaded, the client having MCP configured, and the server being healthy are three separate conditions.
