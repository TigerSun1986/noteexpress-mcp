# MCP connection and compatibility

## NoteExpress endpoint evidence

The task information supplied for this project records a successful Windows PowerShell request to:

- Process: `NoteExpress.exe` (typical path `C:\Program Files\NoteExpress\NoteExpress.exe`)
- Host and port: `127.0.0.1:49527`
- URL: `http://127.0.0.1:49527/mcp`
- Request: HTTP POST, `Content-Type: application/json`, JSON-RPC 2.0 method `tools/list`, empty `params`
- Result: `result.tools` contained 30 tool definitions with `name`, `description`, and `inputSchema`

The original response pasted into the task was not present in the repository. This package subsequently captured the live endpoint at [tool-schemas/noteexpress-tools-20261120T030400Z.json](tool-schemas/noteexpress-tools-20261120T030400Z.json). It contains one raw `tools/list` response page, all 30 exact tool definitions, plus the raw `noteexpress_version` call response. The snapshot is version-specific; use the currently registered client's live schemas for each action.

## Protocol-version boundary

The live `noteexpress_version` response reports NoteExpress `4.4.0.10931` (build `10931`), MCP protocol `2025-06-18`, and server `1.0.0`. A compatibility probe then completed the protocol's standard `initialize` request at `2025-06-18`, received a matching `protocolVersion`, sent `notifications/initialized` (HTTP 202), and received a 30-tool `tools/list` using the `MCP-Protocol-Version: 2025-06-18` header. `noteexpress_ping` also succeeded through `tools/call`.

The same endpoint also accepts the originally tested plain `tools/list` POST without initialization or protocol header. The health check retains that simpler request because it is a known, fast diagnostic path; clients that use the `2025-06-18` protocol can use the verified standard handshake. These tests establish those specific exchanges, not complete conformance or success for every tool. The current official MCP specification is revision `2026-07-28`; do not infer that this older-protocol server implements all current behavior.

Do not add an `initialize` request to the Guard based only on a general MCP assumption. The installed server explicitly reports its protocol version and the standard initialize flow has now been tested. Still do not claim full current-spec conformance based only on `tools/list`, initialize, and ping. Read `noteexpress_version` through its advertised live schema and treat its `mcp_protocol` field as the server's explicit protocol-version claim.

Official references:

- [Current MCP specification](https://modelcontextprotocol.io/specification/2026-07-28)
- [Current protocol versioning and legacy compatibility](https://modelcontextprotocol.io/specification/draft/basic/versioning)
- [2025-06-18 lifecycle](https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle)
- [2025-06-18 Streamable HTTP transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports)
- [2025-06-18 tools](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)
- [2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
- [MCP tools listing and calling](https://modelcontextprotocol.io/specification/draft/server/tools)

## Health-check behavior

Run the script on the Windows computer that hosts NoteExpress, not on an unrelated remote agent:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-ne-mcp.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-ne-mcp.ps1 -Json
```

The script inspects all `NoteExpress.exe` processes and all listener rows returned for port 49527, checks every owner PID, tests the loopback TCP endpoint, and posts the observed JSON-RPC `tools/list` request. If `Get-NetTCPConnection` is unavailable or denied, it falls back to parsing `netstat.exe -ano -p tcp`; if neither source can establish ownership, the state stays unknown. It never starts NoteExpress or terminates a process.

| Status | Exit code | Meaning |
|---|---:|---|
| `READY` | 0 | Every observed listener maps to NoteExpress and a nonempty valid tools list contains the three required guard tools. |
| `NO_PROCESS` | 1 | No NoteExpress process was found and the endpoint is closed. |
| `PROCESS_RUNNING_PORT_CLOSED` | 2 | NoteExpress is running but port 49527 is not reachable. |
| `PORT_CONFLICT` | 3 | At least one listener record belongs to another process. |
| `PORT_OWNER_UNKNOWN` | 4 | TCP is reachable but owner mapping is unavailable or unresolved; successful tool discovery does not promote this to `READY`. |
| `HTTP_UNAVAILABLE` | 5 | TCP is reachable or a listener is reported, but the MCP HTTP request cannot be completed successfully. This includes timeout and HTTP failure. |
| `MCP_INVALID_RESPONSE` | 6 | The body is not valid JSON-RPC 2.0 with the matching request ID and expected result structure. |
| `MCP_TOOLS_MISSING` | 7 | `tools/list` returned no tools or missed a required guard tool. |
| `MCP_CALL_FAILED` | 8 | `tools/list` returned a JSON-RPC error, or the optional ping probe failed. |
| `CHECK_ERROR` | 9 | The process table or the guard itself could not be inspected. |

JSON output contains independent checks for processes and paths, listener query, TCP connectivity, port owner, `tools/list`, tool shape, required tools, ping, and client tool registration. The client registration check is always `NOT_CHECKED`; the script cannot inspect an AI application's active tool registry.

### Ping probe

The initial task evidence confirmed `tools/list`; the live check later verified `tools/call` for both `noteexpress_version` and `noteexpress_ping`. The default Guard still skips ping to keep the check minimal. `-ProbePing` sends the call only if the current tools list advertises it and its schema has no required arguments. `tests/Test-Protocol.ps1` repeats the standard initialize flow and these two read-only calls against the local endpoint.

## Service, client, and skill state

Treat these as separate checks:

1. **Skill loaded:** the client discovered this `SKILL.md` and can read its references.
2. **MCP registered:** the client configured a server entry and exposes the resulting `noteexpress_*` tools to the current session.
3. **Service healthy:** the Windows host check returned a current state.

None of these states implies the other two. A `READY` health check cannot repair missing client registration, and a visible skill does not grant MCP access.

## Localhost boundary

When an agent runs on another computer, in a container, or in a cloud session, its `127.0.0.1` refers to that runtime, not to the Windows computer with NoteExpress. Confirm the connection path explicitly. Use only a secured bridge or approved host-side runner that the user controls. Never bind NoteExpress's service to a public interface or expose port 49527 to the Internet.

Client-specific setup is in `README.md`. The installer copies skill files only and does not write client MCP configuration.
