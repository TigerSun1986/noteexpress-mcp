# Troubleshooting

Run `scripts/check-ne-mcp.ps1 -Json` only on the Windows host where NoteExpress runs, on first use, after a connection-class failure, or when the user requests a diagnosis. Its JSON has a separate entry for each check; `NOT_CHECKED` is not success.

## Guard states

| State | Meaning | Next step |
|---|---|---|
| `READY` | A NoteExpress process owns the observed listener and `/mcp` returned valid `tools/list` with required tools. | Inspect the AI client's registered tools separately. This does not prove every `tools/call` works. |
| `NO_PROCESS` | No NoteExpress process was found. | Ask the user to open NoteExpress if they want to use it. Do not start an unknown executable. |
| `PROCESS_RUNNING_PORT_CLOSED` | NoteExpress is running but the expected endpoint did not accept TCP. | Check whether the MCP service is enabled/starting in NoteExpress. Recheck after startup; do not change the port. |
| `PORT_CONFLICT` | Listener evidence includes a non-NoteExpress process or conflicting ownership. | Report owners; never kill a process or treat a successful HTTP response alone as proof of owner. |
| `PORT_OWNER_UNKNOWN` | Listener ownership could not be confirmed. | The MCP response may independently identify as MCP, but process ownership remains unverified. |
| `HTTP_UNAVAILABLE` | TCP/HTTP request failed, returned a non-success status, or timed out. | Retry after a short wait if startup/shutdown is plausible, then report the transport error. |
| `MCP_INVALID_RESPONSE` | Response was not valid matching JSON-RPC 2.0 with a result. | Report that the endpoint response could not be validated; do not call it healthy. |
| `MCP_TOOLS_MISSING` | `tools/list` was empty/malformed or lacked required tools. | Capture the live schema and check NoteExpress version/service state. |
| `MCP_CALL_FAILED` | JSON-RPC returned an error or optional ping reported failure. | Show the returned error. `tools/list` can still be healthy independently. |
| `CHECK_ERROR` | The diagnostic itself failed. | Include the script error; do not infer service state. |

Exit codes are: READY `0`, NO_PROCESS `1`, PROCESS_RUNNING_PORT_CLOSED `2`, PORT_CONFLICT `3`, PORT_OWNER_UNKNOWN `4`, HTTP_UNAVAILABLE `5`, MCP_INVALID_RESPONSE `6`, MCP_TOOLS_MISSING `7`, MCP_CALL_FAILED `8`, CHECK_ERROR `9`.

## Separate the three access conditions

1. The skill may be installed and loaded.
2. The AI client may or may not have the `ne-mcp` server registered.
3. The running NoteExpress endpoint may or may not be reachable from the agent runtime.

Check each independently. A local `127.0.0.1` on a remote/containerized client points to that runtime, not the user's Windows host. Use an approved, secured host bridge if one exists. Do not publish port 49527.

## Refresh tool definitions

Use `scripts/export-tool-schema.ps1` to capture the live paginated `tools/list` response. The capture validates schema availability but does not establish success for arbitrary tool calls. `-ProbeVersion` makes only the advertised `noteexpress_version` call when its schema allows empty arguments. Follow `mcp-connection.md` for protocol-version evidence and compatibility limits.
