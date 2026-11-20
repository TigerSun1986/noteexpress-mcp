#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$assertions = 0
$parseFailures = New-Object System.Collections.Generic.List[string]

$scripts = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') -and $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($scriptFile in $scripts) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) { $parseFailures.Add("$($scriptFile.FullName): $($parseError.Message)") }
    }
}
$script:assertions++
if ($parseFailures.Count -gt 0) { throw "PowerShell parse errors:`n$($parseFailures -join "`n")" }

$manifest = Join-Path $repoRoot 'SKILL.md'
$manifestText = [System.IO.File]::ReadAllText($manifest)
if ($manifestText -notmatch '(?s)^---\s*\r?\n.*?\r?\n---\s*\r?\n') { throw 'SKILL.md is missing a valid YAML frontmatter block.' }
$script:assertions++
if ($manifestText -notmatch '(?m)^name:\s*noteexpress-mcp\s*$') { throw 'SKILL.md name is invalid.' }

$referenceTargets = [regex]::Matches($manifestText, 'references/[A-Za-z0-9._-]+\.md') | ForEach-Object { $_.Value } | Sort-Object -Unique
foreach ($referenceTarget in $referenceTargets) {
    $targetPath = Join-Path $repoRoot ($referenceTarget -replace '/', '\')
    $script:assertions++
    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { throw "SKILL.md points to missing reference: $referenceTarget" }
}

$examplePath = Join-Path $repoRoot 'examples\mcp-config.json'
$example = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($examplePath)) -ErrorAction Stop
$script:assertions++
if (-not $example.mcpServers.'ne-mcp'.url -or $example.mcpServers.'ne-mcp'.url -ne 'http://127.0.0.1:49527/mcp') {
    throw 'Example MCP config does not target the documented NoteExpress loopback endpoint.'
}

$schemaCapturePath = Join-Path $repoRoot 'references\tool-schemas\noteexpress-tools-20261120T030400Z.json'
if (-not (Test-Path -LiteralPath $schemaCapturePath -PathType Leaf)) { throw 'The checked-in live tools/list capture is missing.' }
$schemaCapture = ConvertFrom-Json -InputObject ([System.IO.File]::ReadAllText($schemaCapturePath)) -ErrorAction Stop
$script:assertions++
if ($schemaCapture.tool_count -ne 30 -or @($schemaCapture.tools).Count -ne 30) { throw 'Live schema capture does not contain all 30 tools.' }
$script:assertions++
if ($schemaCapture.noteexpress_version_probe.status -ne 'TOOLS_CALL_RESPONSE') { throw 'Live schema capture has no successful noteexpress_version response.' }
$versionRpc = ConvertFrom-Json -InputObject $schemaCapture.noteexpress_version_probe.raw_response -ErrorAction Stop
$versionData = ConvertFrom-Json -InputObject $versionRpc.result.content[0].text -ErrorAction Stop
$script:assertions++
if ($versionData.mcp_protocol -ne '2025-06-18') { throw 'Captured MCP protocol version does not match its raw noteexpress_version result.' }

Write-Output "PASS: Test-Package.ps1 ($script:assertions assertions; PowerShell syntax, manifest, JSON config, and live schema snapshot)"
