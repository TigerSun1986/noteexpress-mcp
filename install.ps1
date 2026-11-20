#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [ValidateSet('Standard', 'Codex', 'Cursor', 'ClaudeCode', 'OpenCode', 'Pi', 'NeCode')]
    [string]$Client = 'Standard',
    [string]$TargetDirectory,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$SourceDirectory = $PSScriptRoot
$SkillDirectoryName = 'noteexpress-mcp'
$SkillFrontmatterName = 'noteexpress-mcp'

if ($Client -eq 'NeCode') {
    # Preserve the former NeCode folder and skill ID even with a custom skills root.
    $SkillDirectoryName = 'ne-mcp-guard'
    $SkillFrontmatterName = 'ne-mcp-guard'
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

$PackageItems = @('SKILL.md', 'scripts', 'references', 'examples', 'README.md')
foreach ($relativePath in $PackageItems) {
    $sourcePath = Join-Path $SourceDirectory $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Package is incomplete; missing $relativePath." }
}

$TargetDirectory = [System.IO.Path]::GetFullPath($TargetDirectory)
$Destination = Join-Path $TargetDirectory $SkillDirectoryName
if (Test-Path -LiteralPath $Destination) {
    if (-not $Force) { throw "Target already exists. Review it, then pass -Force to replace package files: $Destination" }
}

if ($PSCmdlet.ShouldProcess($Destination, 'Install NoteExpress MCP skill files')) {
    if (-not (Test-Path -LiteralPath $TargetDirectory)) {
        New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }
    foreach ($relativePath in $PackageItems) {
        Copy-Item -LiteralPath (Join-Path $SourceDirectory $relativePath) -Destination $Destination -Recurse -Force
    }

    if ($SkillFrontmatterName -ne 'noteexpress-mcp') {
        $skillPath = Join-Path $Destination 'SKILL.md'
        $skillText = [System.IO.File]::ReadAllText($skillPath)
        $skillText = [regex]::Replace($skillText, '(?m)^name:\s*noteexpress-mcp\s*$', 'name: ne-mcp-guard', 1)
        [System.IO.File]::WriteAllText($skillPath, $skillText, [System.Text.UTF8Encoding]::new($false))
    }

    Write-Output "INSTALLED=$Destination"
    Write-Output 'MCP_CONFIG=UNCHANGED'
    Write-Output 'NEXT=verify the skill is visible and register ne-mcp in the chosen client if needed'
}
else {
    Write-Output "WOULD_INSTALL=$Destination"
}
