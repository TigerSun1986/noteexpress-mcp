#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$ProbePing
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'NeMcpGuard.psm1'
try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    $result = Invoke-NeMcpGuard -ProbePing:$ProbePing
}
catch {
    $failure = [pscustomobject]@{
        status = 'CHECK_ERROR'
        exit_code = 9
        message = $_.Exception.Message
        endpoint = 'http://127.0.0.1:49527/mcp'
        protocol_identity_confirmed = $false
        process_owner_confirmed = $false
        tool_count = 0
        tool_names = @()
        checks = @([pscustomobject]@{ name = 'script'; status = 'ERROR'; detail = $_.Exception.Message })
        checked_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    $result = $failure
}

if ($Json) {
    ConvertTo-Json -InputObject $result -Depth 12
}
else {
    Write-Output "STATUS=$($result.status)"
    Write-Output "EXIT_CODE=$($result.exit_code)"
    Write-Output "ENDPOINT=$($result.endpoint)"
    Write-Output "MESSAGE=$($result.message)"
    if ($result.protocol_identity_confirmed) { Write-Output 'PROTOCOL_IDENTITY=CONFIRMED' }
    if ($result.process_owner_confirmed) { Write-Output 'PROCESS_OWNER=NOTEEXPRESS' }
    if ($result.tool_count -gt 0) { Write-Output "TOOL_COUNT=$($result.tool_count)" }
    foreach ($check in $result.checks) {
        Write-Output ("CHECK={0} RESULT={1} DETAIL={2}" -f $check.name, $check.status, ($check.detail -replace '[\r\n]+', ' '))
    }
}

exit [int]$result.exit_code
