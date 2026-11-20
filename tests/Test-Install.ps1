#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$installPath = Join-Path $repoRoot 'install.ps1'
$uninstallPath = Join-Path $repoRoot 'uninstall.ps1'
$testRoot = Join-Path $PSScriptRoot '.tmp-install-test'
$assertions = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    $script:assertions++
    if (-not $Condition) { throw "ASSERT FAILED [$Name]" }
}

$testRoot = [System.IO.Path]::GetFullPath($testRoot)
if (-not $testRoot.StartsWith([System.IO.Path]::GetFullPath($PSScriptRoot), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use a test path outside the test directory: $testRoot"
}
if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }

$originalAppData = $env:APPDATA
try {
    $skillsRoot = Join-Path $testRoot 'standard-skills'
    $destination = Join-Path $skillsRoot 'noteexpress-mcp'

    & $installPath -TargetDirectory $skillsRoot -WhatIf | Out-Null
    Assert-True 'WhatIf did not create destination' (-not (Test-Path -LiteralPath $destination))

    & $installPath -TargetDirectory $skillsRoot | Out-Null
    Assert-True 'install creates skill manifest' (Test-Path -LiteralPath (Join-Path $destination 'SKILL.md'))
    Assert-True 'install copies health check' (Test-Path -LiteralPath (Join-Path $destination 'scripts\check-ne-mcp.ps1'))
    Assert-True 'install copies references' (Test-Path -LiteralPath (Join-Path $destination 'references\pdf-and-attachments.md'))
    Assert-True 'install copies example config' (Test-Path -LiteralPath (Join-Path $destination 'examples\mcp-config.json'))

    $blockedOverwrite = $false
    try { & $installPath -TargetDirectory $skillsRoot | Out-Null }
    catch { $blockedOverwrite = $true }
    Assert-True 'existing install requires Force' $blockedOverwrite

    $userFile = Join-Path $destination 'user-added.keep'
    [System.IO.File]::WriteAllText($userFile, 'keep')
    & $installPath -TargetDirectory $skillsRoot -Force | Out-Null
    Assert-True 'Force preserves unrelated user file' (Test-Path -LiteralPath $userFile)

    & $uninstallPath -TargetDirectory $skillsRoot -WhatIf | Out-Null
    Assert-True 'uninstall WhatIf preserves skill' (Test-Path -LiteralPath $destination)
    & $uninstallPath -TargetDirectory $skillsRoot -Confirm:$false | Out-Null
    Assert-True 'uninstall removes only skill folder' (-not (Test-Path -LiteralPath $destination))
    Assert-True 'uninstall preserves sibling files' (Test-Path -LiteralPath $skillsRoot -PathType Container)

    $neAppData = Join-Path $testRoot 'fake-appdata'
    $env:APPDATA = $neAppData
    $neDestination = Join-Path $neAppData 'ai.necode.desktop\xdg-config\necode-desktop\skills\ne-mcp-guard'
    & $installPath -Client NeCode | Out-Null
    $neSkillText = [System.IO.File]::ReadAllText((Join-Path $neDestination 'SKILL.md'))
    Assert-True 'NeCode compatibility alias path exists' (Test-Path -LiteralPath (Join-Path $neDestination 'SKILL.md'))
    Assert-True 'NeCode compatibility skill ID is preserved' ($neSkillText -match '(?m)^name:\s*ne-mcp-guard\s*$')
    & $uninstallPath -Client NeCode -Confirm:$false | Out-Null
    Assert-True 'NeCode uninstall removes alias folder' (-not (Test-Path -LiteralPath $neDestination))

    $customNeRoot = Join-Path $testRoot 'custom-necode-skills'
    $customNeDestination = Join-Path $customNeRoot 'ne-mcp-guard'
    & $installPath -Client NeCode -TargetDirectory $customNeRoot | Out-Null
    $customNeText = [System.IO.File]::ReadAllText((Join-Path $customNeDestination 'SKILL.md'))
    Assert-True 'custom NeCode skills root preserves compatibility alias' ($customNeText -match '(?m)^name:\s*ne-mcp-guard\s*$')
    & $uninstallPath -Client NeCode -TargetDirectory $customNeRoot -Confirm:$false | Out-Null
    Assert-True 'custom NeCode uninstall removes alias folder' (-not (Test-Path -LiteralPath $customNeDestination))
}
finally {
    if ($null -eq $originalAppData) { Remove-Item Env:APPDATA -ErrorAction SilentlyContinue }
    else { $env:APPDATA = $originalAppData }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Output "PASS: Test-Install.ps1 ($script:assertions assertions; isolated workspace install/uninstall paths)"
