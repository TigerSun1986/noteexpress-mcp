#requires -Version 5.1
# NoteExpress MCP readiness check (fixed values, do not change).
# Windows only. NoteExpress embeds HTTP MCP at 127.0.0.1:49527 (tools: noteexpress_*).
#
# Exit codes:
#   0 = UP            port owned by NoteExpress
#   1 = NO_PROCESS    no NoteExpress process and port closed  -> install / start NoteExpress
#   2 = STARTING      NoteExpress running but port not listening yet -> wait and retry
#   3 = PORT_CONFLICT port owned by another process -> another program owns the port

$ErrorActionPreference = 'Stop'

$McpHost   = '127.0.0.1'
$McpPort   = 49527
$McpUrl    = "http://${McpHost}:${McpPort}/mcp"
$ProcName  = 'NoteExpress'
$TimeoutMs = 800

function Test-PortOpen([string]$TargetHost, [int]$TargetPort, [int]$Timeout) {
    $client = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($TargetHost, $TargetPort, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($Timeout)) {
            throw "connect timeout (${Timeout}ms)"
        }
        $client.EndConnect($iar)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($client) { $client.Close() }
    }
}

# Returns the owning PID of the LISTEN socket, 0 when nobody listens,
# or -1 when the owner cannot be determined (cmdlet missing / no access).
function Get-PortOwnerPid([int]$TargetPort) {
    try {
        $conns = @(Get-NetTCPConnection -LocalPort $TargetPort -State Listen -ErrorAction Stop)
    }
    catch {
        return -1
    }
    if ($conns.Count -eq 0) { return 0 }
    return [int]$conns[0].OwningProcess
}

$procs = @(Get-Process -Name $ProcName -ErrorAction SilentlyContinue)
$nePid = ''
$nePath = ''
if ($procs.Count -gt 0) {
    $nePid = [string]$procs[0].Id
    try { $nePath = [string]$procs[0].Path } catch { $nePath = '' }
}

$ownerPid = Get-PortOwnerPid $McpPort
$ownerKnown = $ownerPid -ge 0
$listening = $ownerPid -gt 0
$unverified = $false

if (-not $ownerKnown) {
    # Fallback: cannot map the socket to a process, so a plain TCP probe decides.
    $unverified = $true
    $listening = Test-PortOpen -TargetHost $McpHost -TargetPort $McpPort -Timeout $TimeoutMs
    $ownerPid = 0
}

$ownerIsNe = $false
if ($listening) {
    if ($ownerKnown) {
        $ownerIsNe = @($procs | Where-Object { [int]$_.Id -eq $ownerPid }).Count -gt 0
    }
    else {
        $ownerIsNe = $procs.Count -gt 0
    }
}

if ($listening -and $ownerIsNe) {
    Write-Output 'STATUS=UP'
    Write-Output "ENDPOINT=$McpUrl"
    Write-Output "NE_PID=$nePid"
    if ($ownerKnown) { Write-Output "OWNER_PID=$ownerPid" }
    if ($nePath) { Write-Output "NE_PATH=$nePath" }
    if ($unverified) { Write-Output 'NOTE=port-owner-unverified' }
    exit 0
}

if ($listening) {
    Write-Output 'STATUS=PORT_CONFLICT'
    Write-Output "ENDPOINT=$McpUrl"
    if ($ownerPid -gt 0) {
        Write-Output "OWNER_PID=$ownerPid"
        try {
            $ownerName = (Get-Process -Id $ownerPid -ErrorAction Stop).ProcessName
            if ($ownerName) { Write-Output "OWNER_NAME=$ownerName" }
        }
        catch { }
    }
    Write-Output "REASON=port $McpPort is listening but is not owned by $ProcName"
    exit 3
}

if ($procs.Count -gt 0) {
    Write-Output 'STATUS=STARTING'
    Write-Output "ENDPOINT=$McpUrl"
    Write-Output "NE_PID=$nePid"
    Write-Output "REASON=$ProcName is running but port $McpPort is not listening yet"
    exit 2
}

Write-Output 'STATUS=NO_PROCESS'
Write-Output "ENDPOINT=$McpUrl"
Write-Output "REASON=no $ProcName process and port $McpPort is closed"
exit 1
