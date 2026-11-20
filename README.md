# NoteExpress MCP Skill

A reusable Agent Skills package for working with the MCP service embedded in NoteExpress. The package contains a small Windows host health check and detailed, on-demand workflow references. It does not implement another MCP server and does not modify NoteExpress.

## What is verified

The task supplied a PowerShell check showing that `POST http://127.0.0.1:49527/mcp` with a JSON-RPC 2.0 `tools/list` request returned 30 entries. This package captured the live endpoint on 2026-11-20; the complete raw response, exact schemas, and `noteexpress_version` result are in `references/tool-schemas/noteexpress-tools-20261120T030400Z.json`. Refresh the snapshot with the included exporter before relying on it with another NoteExpress release.

The live version tool reports NoteExpress 4.4.0.10931, build 10931, MCP protocol 2025-06-18, and server 1.0.0. A local read-only compatibility probe verified `initialize` → `notifications/initialized` → version-header `tools/list` and `noteexpress_ping` via `tools/call`. This does not validate every tool. The Guard's default `tools/list` path remains the observed fast check; `-ProbePing` is optional.

## Package contents

- `SKILL.md` — concise routing, connection, and safety instructions.
- `scripts/check-ne-mcp.ps1` — PowerShell 5.1 host diagnostic; exits with a state-specific code and supports `-Json`.
- `scripts/NeMcpGuard.psm1` — testable implementation used by the health check.
- `scripts/export-tool-schema.ps1` — captures raw, paginated `tools/list` responses and parsed schemas. Optional `-ProbeVersion` calls only `noteexpress_version`, and only with no required arguments.
- `references/` — focused workflows, limits, client setup, safety, and troubleshooting.
- `examples/mcp-config.json` — a minimal Cursor/Pi-style `mcpServers` URL entry. Claude Code's JSON entry also needs `"type": "http"`; OpenCode uses `mcp.servers` with `type: "remote"` instead.
- `tests/` — dependency-free Guard, workflow, package, installer, and live protocol tests.

## Requirements and limits

NoteExpress's embedded MCP service is a Windows service endpoint at `127.0.0.1:49527`. The health-check script requires Windows PowerShell 5.1 or PowerShell 7 on the Windows host where NoteExpress is running. On another operating system, the skill instructions remain portable, but that script cannot inspect the Windows process table. Run it only through a trusted host command or a secure bridge that actually executes on that Windows computer.

The local health check verifies one `tools/list` exchange. It does not inspect the AI client's MCP registry, make all 30 tools appear in the current conversation, or prove that each tool can complete a call. The script emits `client_tool_registration: NOT_CHECKED` to preserve that distinction.

## Install the skill

The installer copies the skill files only. It never edits MCP or other client configuration. The default user-level destination is `~/.agents/skills/noteexpress-mcp`, shared by Codex, Cursor, OpenCode, and Pi installations that discover that directory.

```powershell
# Shared Agent Skills directory (Codex, Cursor, OpenCode, Pi)
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# Claude Code's user skill directory
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Client ClaudeCode

# Choose another skills root; the installer appends noteexpress-mcp
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -TargetDirectory 'D:\AgentSkills'

# Keep the previous NeCode Windows path and skill ID
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Client NeCode
```

If the target already exists, inspect it first. Pass `-Force` to replace the package's matching files. The installer does not remove user-added files, update MCP settings, or terminate NoteExpress. Run with `-WhatIf` to preview the destination.

To uninstall, use the same client or target directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -Client ClaudeCode
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -TargetDirectory 'D:\AgentSkills'
```

The uninstaller verifies the skill frontmatter before deleting that skill folder. It leaves all client MCP configuration untouched. It supports `-WhatIf` and prompts before removal.

## Register NoteExpress MCP separately

Installing or loading a skill does not configure an MCP server. Choose the configuration route for the client and environment where the agent runs. Review and apply the setting yourself; the installer does not edit it.

### Codex

On the Windows computer running NoteExpress, use Codex's CLI or `config.toml`:

```powershell
codex mcp add ne-mcp --url http://127.0.0.1:49527/mcp
codex mcp list
```

Or add this entry to the existing `~/.codex/config.toml`, preserving unrelated settings:

```toml
[mcp_servers.ne-mcp]
url = "http://127.0.0.1:49527/mcp"
```

### Claude Code

```powershell
claude mcp add --transport http --scope user ne-mcp http://127.0.0.1:49527/mcp
claude mcp list
```

Use `/mcp` in the session to inspect connection status and available tools.

### Cursor

Cursor accepts MCP JSON in a project `.cursor/mcp.json` or user `~/.cursor/mcp.json`. Add this entry to the existing `mcpServers` object without replacing unrelated servers:

```json
{
  "mcpServers": {
    "ne-mcp": {
      "url": "http://127.0.0.1:49527/mcp"
    }
  }
}
```

### OpenCode

OpenCode uses an `mcp.servers` object in `opencode.json` or `opencode.jsonc`, and supports `opencode mcp add`:

```powershell
opencode mcp add ne-mcp --url http://127.0.0.1:49527/mcp
opencode mcp list
```

OpenCode currently has configurable MCP protocol behavior. The NoteExpress endpoint's standard `2025-06-18` handshake was tested directly, but OpenCode's own client integration was not. If it fails, inspect OpenCode's connection error and `references/mcp-connection.md`; do not change protocol mode based on assumption.

### Pi

Pi supports a `mcpServers` JSON configuration and CLI registration:

```powershell
pi mcp add ne-mcp --url http://127.0.0.1:49527/mcp
pi mcp list
```

Pi registers the MCP tools under its own tool namespace. Use the names and schemas the current Pi session actually exposes.

### NeCode

`install.ps1 -Client NeCode` preserves the former Windows skills directory and `ne-mcp-guard` skill ID. The old path came from the original repository installer; NeCode's current documentation does not publish that exact path, so verify the installed skill in NeCode's skills UI. Its client configuration and embedded MCP settings are not changed by this package.

## Client capability map

| Client | Skill directory used by the installer | MCP setup |
|---|---|---|
| Codex | `~/.agents/skills/noteexpress-mcp` | `codex mcp add` or `~/.codex/config.toml` |
| Cursor | `~/.agents/skills/noteexpress-mcp` | `~/.cursor/mcp.json` or `.cursor/mcp.json` |
| Claude Code | `~/.claude/skills/noteexpress-mcp` | `claude mcp add --transport http` |
| OpenCode | `~/.agents/skills/noteexpress-mcp` | `opencode mcp add`; direct protocol probe passed, OpenCode client integration unverified |
| Pi | `~/.agents/skills/noteexpress-mcp` | `pi mcp add` |
| NeCode | Previous `%APPDATA%\ai.necode.desktop\xdg-config\necode-desktop\skills\ne-mcp-guard` location | Keep using the NeCode UI/configuration for MCP; current exact path is unverified |

Agent Skills compatibility means the client can discover the `SKILL.md` directory; it does not establish that its MCP client is configured, that it can run PowerShell, or that it can reach the Windows computer. A remote agent's loopback URL points to the remote runtime itself. Use a secured and supported host bridge when needed; never publish NoteExpress's loopback port to the Internet.

Official client documentation used for the path and setup table:

- [Agent Skills format](https://agentskills.io/specification)
- [Codex skills](https://learn.chatgpt.com/docs/build-skills) and [Codex MCP setup](https://developers.openai.com/learn/docs-mcp)
- [Cursor skills](https://cursor.com/docs/skills) and [Cursor MCP setup](https://cursor.com/docs/mcp)
- [Claude Code skills](https://code.claude.com/docs/en/skills) and [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [OpenCode skills](https://opencode.ai/docs/skills) and [OpenCode MCP](https://opencode.ai/docs/mcp-servers)
- [Pi skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md) and [Pi MCP](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md)

## Capture the live tool schema

The package includes a dated 30-tool capture under `references/tool-schemas/`. To retrieve and save a newer server snapshot:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tool-schema.ps1
```

It writes a timestamped JSON capture under `references/tool-schemas/`. To additionally request the advertised `noteexpress_version` tool with empty arguments (only if its schema permits):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tool-schema.ps1 -ProbeVersion
```

That optional call tests only `noteexpress_version`; it is not a claim that other tool calls succeed. The checked-in response explicitly reports `mcp_protocol: 2025-06-18`; consult `references/mcp-connection.md` for the protocol compatibility results.

## Run tests

The mock, workflow, package, and installer tests require PowerShell 5.1 or PowerShell 7 and do not require Pester or NoteExpress. `Test-Protocol.ps1` additionally requires the local NoteExpress MCP endpoint to be running:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Workflows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Package.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Protocol.ps1
```

The guard test injects process/socket fixtures and a mock JSON-RPC provider. Workflow tests check documented behavior contracts; install tests use an isolated temporary directory. `Test-Protocol.ps1` is a live, read-only compatibility test that requires NoteExpress to be running on this Windows host; it sends initialize, tools/list, noteexpress_version, and ping only. No library records are created or changed.
