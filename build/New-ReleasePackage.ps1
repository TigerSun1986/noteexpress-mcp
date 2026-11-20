#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$PackageName = "noteexpress-mcp-v$Version"
$ArchivePath = Join-Path $OutputDirectory "$PackageName.zip"

# This allowlist is the customer distribution. Tests, contributor docs, build logic, and repository metadata stay out.
$PackageItems = @(
    'README.md',
    'SKILL.md',
    'install.ps1',
    'uninstall.ps1',
    'scripts',
    'references',
    'examples'
)

foreach ($relativePath in $PackageItems) {
    $sourcePath = Join-Path $RepositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Cannot build release package; required item is missing: $relativePath"
    }
}

if (Test-Path -LiteralPath $ArchivePath) {
    throw "Release archive already exists; choose another version or output directory: $ArchivePath"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$StageRoot = [System.IO.Path]::GetFullPath((Join-Path $OutputDirectory ('.stage-' + [Guid]::NewGuid().ToString('N'))))
$OutputPrefix = $OutputDirectory.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $StageRoot.StartsWith($OutputPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create staging files outside the output directory: $StageRoot"
}

$PackageRoot = Join-Path $StageRoot $PackageName
try {
    New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null
    foreach ($relativePath in $PackageItems) {
        Copy-Item -LiteralPath (Join-Path $RepositoryRoot $relativePath) -Destination $PackageRoot -Recurse -Force
    }

    Compress-Archive -Path (Join-Path $PackageRoot '*') -DestinationPath $ArchivePath -CompressionLevel Optimal
    Write-Output "PACKAGE=$ArchivePath"
    Write-Output 'INCLUDES=README.md,SKILL.md,install.ps1,uninstall.ps1,scripts,references,examples'
    Write-Output 'EXCLUDES=tests,CONTRIBUTING.md,build,.git,.gitignore'
}
finally {
    if (Test-Path -LiteralPath $StageRoot) {
        $ResolvedStageRoot = [System.IO.Path]::GetFullPath($StageRoot)
        if ($ResolvedStageRoot.StartsWith($OutputPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $ResolvedStageRoot -Recurse -Force
        }
    }
}
