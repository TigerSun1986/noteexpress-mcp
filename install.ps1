#requires -Version 5.1
# Install ne-mcp-guard into the local NeCode skills directory (fixed path, no arguments).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
# Exit codes: 0 = installed (or already installed); 1 = failed.

$ErrorActionPreference = 'Stop'

if (-not $env:APPDATA) {
    Write-Output 'ERROR=APPDATA environment variable is missing'
    exit 1
}

$SkillName = 'ne-mcp-guard'
$Source    = $PSScriptRoot
$Dest      = Join-Path $env:APPDATA "ai.necode.desktop\xdg-config\necode-desktop\skills\$SkillName"

foreach ($rel in @('SKILL.md', 'scripts\check-ne-mcp.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Source $rel))) {
        Write-Output "ERROR=package incomplete, missing $rel"
        exit 1
    }
}

function Get-CanonicalPath([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        return (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
    }
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

# Already running from the installed location: copying onto itself locks files.
if ([string]::Equals((Get-CanonicalPath $Source), (Get-CanonicalPath $Dest), 'OrdinalIgnoreCase')) {
    Write-Output "SKIP=already installed at $Dest"
    exit 0
}

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$items = @(Get-ChildItem -LiteralPath $Source -Force)

$copied = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $items | Copy-Item -Destination $Dest -Recurse -Force -ErrorAction Stop
        $copied = $true
        break
    }
    catch {
        if ($attempt -eq 3) {
            Write-Output "ERROR=copy failed after 3 attempts: $($_.Exception.Message)"
            Write-Output "PARTIAL=$Dest (delete it and retry)"
            exit 1
        }
        Start-Sleep -Milliseconds 300
    }
}

if (-not $copied) {
    Write-Output 'ERROR=copy did not run'
    exit 1
}

Write-Output "INSTALLED=$Dest"
Write-Output 'NEXT=restart the NeCode session to activate the skill'
exit 0
