#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$catalogPath = Join-Path $repoRoot 'references\tools-catalog.md'
$skillPath = Join-Path $repoRoot 'SKILL.md'
$workflowPath = Join-Path $repoRoot 'references\reference-workflows.md'
$pdfPath = Join-Path $repoRoot 'references\pdf-and-attachments.md'
$libraryPath = Join-Path $repoRoot 'references\library-and-folders.md'
$safetyPath = Join-Path $repoRoot 'references\mutation-safety.md'
$troubleshootingPath = Join-Path $repoRoot 'references\troubleshooting.md'
$assertions = 0

function Assert-Contains {
    param([string]$Name, [string]$Text, [string]$Pattern)
    $script:assertions++
    if ($Text -notmatch $Pattern) { throw "ASSERT FAILED [$Name]: missing pattern '$Pattern'" }
}

foreach ($requiredPath in @($catalogPath, $skillPath, $workflowPath, $pdfPath, $libraryPath, $safetyPath, $troubleshootingPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required workflow reference missing: $requiredPath" }
}
$catalog = [System.IO.File]::ReadAllText($catalogPath)
$skill = [System.IO.File]::ReadAllText($skillPath)
$workflow = [System.IO.File]::ReadAllText($workflowPath)
$pdf = [System.IO.File]::ReadAllText($pdfPath)
$library = [System.IO.File]::ReadAllText($libraryPath)
$safety = [System.IO.File]::ReadAllText($safetyPath)
$troubleshooting = [System.IO.File]::ReadAllText($troubleshootingPath)

$expectedTools = @(
    'noteexpress_ping','noteexpress_version','noteexpress_get_server_status','noteexpress_list_libraries','noteexpress_open_library',
    'noteexpress_search_refs','noteexpress_list_refs','noteexpress_get_ref','noteexpress_list_categories','noteexpress_list_smart_folders',
    'noteexpress_get_smart_folder','noteexpress_get_note','noteexpress_create_ref','noteexpress_update_ref','noteexpress_save_stub_refs',
    'noteexpress_smart_update_refs','noteexpress_import_pdf_ref','noteexpress_import_formatted_refs','noteexpress_export_refs','noteexpress_attach_file',
    'noteexpress_list_attaches','noteexpress_remove_attach','noteexpress_extract_pdf_text','noteexpress_create_category','noteexpress_update_category',
    'noteexpress_delete_category','noteexpress_link_refs','noteexpress_move_refs','noteexpress_dedupe_refs','noteexpress_delete_refs'
)
foreach ($toolName in $expectedTools) {
    Assert-Contains "catalog contains $toolName" $catalog ([regex]::Escape($toolName))
}
$catalogNames = [regex]::Matches($catalog, '`(noteexpress_[a-z_]+)`') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$script:assertions++
if (@($catalogNames).Count -ne 30) { throw "ASSERT FAILED [catalog tool count]: expected 30 names, found $(@($catalogNames).Count)" }

# Search, pagination, real results, create, update, import/export, and citation limits.
foreach ($pattern in @('noteexpress_search_refs','summary_mode','pagination','noteexpress_get_ref','noteexpress_save_stub_refs','noteexpress_create_ref','action=list_templates','action=list_fields','action=create','noteexpress_update_ref','list_editable','noteexpress_dedupe_refs','dry_run','noteexpress_import_formatted_refs','noteexpress_import_pdf_ref','noteexpress_export_refs','Word dynamic citation','not a NoteExpress-linked field','tool or argument is missing')) {
    Assert-Contains "workflow guidance: $pattern" $workflow ([regex]::Escape($pattern))
}

# PDF identity, limits, host-path, extraction and attachment overwrite constraints.
foreach ($pattern in @('attachments\[\]\.id','GUID','database integer `id`','64 MiB','2,000,000','OCR','uuid','overwrite','Windows computer running NoteExpress','noteexpress_remove_attach')) {
    Assert-Contains "PDF/attachment guidance: $pattern" $pdf $pattern
}

# Library activation, category type safety, and move-vs-link semantics.
foreach ($pattern in @('noteexpress_list_libraries','library_id','activate','does not itself switch','smart.folder','category_id','link_refs','move_refs','retaining the source','removes references from the source','current library')) {
    Assert-Contains "library/folder guidance: $pattern" $library $pattern
}

# Destructive controls and missing-tool / connection fallback guidance.
foreach ($pattern in @('noteexpress_delete_refs','noteexpress_delete_category','most_attachments','explicit confirmation','dry-run','Do not terminate NoteExpress','Do not expose the loopback','overwriting')) {
    Assert-Contains "mutation safety: $pattern" $safety $pattern
}
foreach ($pattern in @('READY','PORT_CONFLICT','PORT_OWNER_UNKNOWN','MCP_INVALID_RESPONSE','MCP_TOOLS_MISSING','NOT_CHECKED','remote/containerized','connection-class')) {
    Assert-Contains "troubleshooting: $pattern" $troubleshooting $pattern
}

# Entry-point skill stays concise and links to all relevant references.
foreach ($reference in @('reference-workflows.md','pdf-and-attachments.md','library-and-folders.md','mutation-safety.md','tools-catalog.md','mcp-connection.md')) {
    Assert-Contains "SKILL routes to $reference" $skill ([regex]::Escape($reference))
}

Write-Output "PASS: Test-Workflows.ps1 ($script:assertions assertions; static workflow contract coverage; no NoteExpress writes)"
