#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('Standard', 'Codex', 'Cursor', 'ClaudeCode', 'OpenCode', 'Pi', 'NeCode')]
    [string]$Client = 'Standard',
    [string]$TargetDirectory
)

$ErrorActionPreference = 'Stop'
$SkillDirectoryName = 'noteexpress-mcp'
$ExpectedSkillName = 'noteexpress-mcp'

if ($Client -eq 'NeCode') {
    $SkillDirectoryName = 'ne-mcp-guard'
    $ExpectedSkillName = 'ne-mcp-guard'
}

if (-not $TargetDirectory) {
    switch ($Client) {
        'ClaudeCode' { $TargetDirectory = Join-Path $HOME '.claude\skills' }
        'NeCode' {
            if (-not $env:APPDATA) { throw 'APPDATA is missing; pass -TargetDirectory explicitly.' }
            $TargetDirectory = Join-Path $env:APPDATA 'ai.necode.desktop\xdg-config\necode-desktop\skills'
        }
        default { $TargetDirectory = Join-Path $HOME '.agents\skills' }
    }
}

$TargetDirectory = [System.IO.Path]::GetFullPath($TargetDirectory)
$Destination = Join-Path $TargetDirectory $SkillDirectoryName
if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
    Write-Output "NOT_INSTALLED=$Destination"
    exit 0
}

$skillPath = Join-Path $Destination 'SKILL.md'
if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { throw "Refusing to remove a directory without SKILL.md: $Destination" }
$skillText = [System.IO.File]::ReadAllText($skillPath)
$expectedNameLine = "name: $ExpectedSkillName"
if ($skillText -notmatch ('(?m)^' + [regex]::Escape($expectedNameLine) + '\s*$')) {
    throw "Refusing to remove a skill whose frontmatter does not identify as ${ExpectedSkillName}: $Destination"
}

if ($PSCmdlet.ShouldProcess($Destination, 'Remove installed NoteExpress MCP skill files')) {
    Remove-Item -LiteralPath $Destination -Recurse -Force
    Write-Output "UNINSTALLED=$Destination"
    Write-Output 'MCP_CONFIG=UNCHANGED'
}
