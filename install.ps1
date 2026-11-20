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

function Test-NoteExpressInstalled {
    $runningProcess = Get-Process -Name 'NoteExpress' -ErrorAction SilentlyContinue
    if ($runningProcess) { return $true }

    $programRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($programRoot in $programRoots) {
        $candidate = Join-Path $programRoot 'NoteExpress\NoteExpress.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true }
    }

    $uninstallLocations = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($location in $uninstallLocations) {
        $installedApps = Get-ItemProperty -Path $location -ErrorAction SilentlyContinue
        foreach ($installedApp in $installedApps) {
            if ($installedApp.DisplayName -match '^\s*NoteExpress(?:\b|$)') { return $true }
        }
    }

    return $false
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
    if (Test-NoteExpressInstalled) {
        Write-Output 'NOTEEXPRESS=DETECTED'
    }
    else {
        Write-Output 'NOTEEXPRESS=NOT_DETECTED'
        if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            Write-Output '提醒：当前 Windows 电脑未检测到 NoteExpress。请访问 https://www.inoteexpress.com/ 下载适用于这台电脑且包含 MCP 服务的版本。安装并启动 NoteExpress 后，再确认 MCP 服务已启用并配置 AI 客户端。'
        }
        else {
            Write-Output '提醒：NoteExpress MCP 需要在 Windows 主机上运行。请访问 https://www.inoteexpress.com/ 在运行 NoteExpress 的 Windows 电脑上安装适用且包含 MCP 服务的版本，再配置 AI 客户端连接该主机。'
        }
    }
    Write-Output 'NEXT=verify the skill is visible and register ne-mcp in the chosen client if needed'
}
else {
    Write-Output "WOULD_INSTALL=$Destination"
}
