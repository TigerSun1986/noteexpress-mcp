#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\scripts\NeMcpGuard.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

$script:assertions = 0
function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    $script:assertions++
    if ($Expected -ne $Actual) { throw "ASSERT FAILED [$Name]: expected '$Expected', got '$Actual'" }
}
function Assert-True {
    param([string]$Name, [bool]$Condition)
    $script:assertions++
    if (-not $Condition) { throw "ASSERT FAILED [$Name]" }
}
function New-MockProcess {
    param([int]$Id, [string]$Name, [string]$Path)
    return [pscustomobject]@{ Id = $Id; ProcessName = $Name; Path = $Path }
}
function New-MockListener {
    param([string]$Address, [int]$OwnerPid)
    return [pscustomobject]@{ LocalAddress = $Address; LocalPort = 49527; OwningProcess = $OwnerPid }
}

$script:toolNames = @(
    'noteexpress_ping','noteexpress_version','noteexpress_get_server_status','noteexpress_list_libraries','noteexpress_open_library',
    'noteexpress_search_refs','noteexpress_list_refs','noteexpress_get_ref','noteexpress_list_categories','noteexpress_list_smart_folders',
    'noteexpress_get_smart_folder','noteexpress_get_note','noteexpress_create_ref','noteexpress_update_ref','noteexpress_save_stub_refs',
    'noteexpress_smart_update_refs','noteexpress_import_pdf_ref','noteexpress_import_formatted_refs','noteexpress_export_refs','noteexpress_attach_file',
    'noteexpress_list_attaches','noteexpress_remove_attach','noteexpress_extract_pdf_text','noteexpress_create_category','noteexpress_update_category',
    'noteexpress_delete_category','noteexpress_link_refs','noteexpress_move_refs','noteexpress_dedupe_refs','noteexpress_delete_refs'
)

function New-MockTool {
    param([string]$Name)
    return @{ name = $Name; description = "Mock endpoint definition for $Name"; inputSchema = @{ type = 'object'; properties = @{} } }
}
function New-MockMcpProvider {
    param([string]$Mode, [System.Collections.Generic.List[object]]$RequestLog)
    $capturedMode = $Mode
    $capturedNames = @($script:toolNames)
    $capturedRequestLog = $RequestLog
    return {
        param($Uri, $RequestObject, $TimeoutMs)
        $capturedRequestLog.Add($RequestObject)
        if ($RequestObject.method -eq 'tools/call') {
            $response = @{ jsonrpc = '2.0'; id = $RequestObject.id; result = @{ content = @(@{ type = 'text'; text = 'mock pong' }); isError = $false } }
            return [pscustomobject]@{ HttpStatus = 200; RawText = (ConvertTo-Json -InputObject $response -Compress -Depth 20); TransportError = $null; TimedOut = $false }
        }
        if ($capturedMode -eq 'timeout') {
            return [pscustomobject]@{ HttpStatus = $null; RawText = ''; TransportError = "Request timed out after $TimeoutMs ms."; TimedOut = $true }
        }
        if ($capturedMode -eq 'http500') {
            return [pscustomobject]@{ HttpStatus = 500; RawText = 'server error'; TransportError = $null; TimedOut = $false }
        }
        if ($capturedMode -eq 'nonjson') {
            return [pscustomobject]@{ HttpStatus = 200; RawText = '<html>not MCP</html>'; TransportError = $null; TimedOut = $false }
        }
        if ($capturedMode -eq 'rpcerror') {
            $response = @{ jsonrpc = '2.0'; id = $RequestObject.id; error = @{ code = -32601; message = 'Method not found' } }
            return [pscustomobject]@{ HttpStatus = 200; RawText = (ConvertTo-Json -InputObject $response -Compress -Depth 20); TransportError = $null; TimedOut = $false }
        }
        if ($capturedMode -eq 'wrongid') {
            $response = @{ jsonrpc = '2.0'; id = 999; result = @{ tools = @() } }
            return [pscustomobject]@{ HttpStatus = 200; RawText = (ConvertTo-Json -InputObject $response -Compress -Depth 20); TransportError = $null; TimedOut = $false }
        }
        if ($capturedMode -eq 'badjsonrpc') {
            return [pscustomobject]@{ HttpStatus = 200; RawText = '{"id":1,"result":{"tools":[]}}'; TransportError = $null; TimedOut = $false }
        }

        if ($capturedMode -eq 'empty') { $tools = @() }
        elseif ($capturedMode -eq 'missing') {
            $tools = @((New-MockTool 'noteexpress_version'), (New-MockTool 'noteexpress_get_server_status'))
        }
        elseif ($capturedMode -eq 'paged') {
            if (-not $RequestObject.params.cursor) {
                $tools = @($capturedNames[0..14] | ForEach-Object { New-MockTool $_ })
                $result = @{ tools = $tools; nextCursor = 'page-2' }
            }
            else {
                $tools = @($capturedNames[15..29] | ForEach-Object { New-MockTool $_ })
                $result = @{ tools = $tools }
            }
            $response = @{ jsonrpc = '2.0'; id = $RequestObject.id; result = $result }
            return [pscustomobject]@{ HttpStatus = 200; RawText = (ConvertTo-Json -InputObject $response -Compress -Depth 20); TransportError = $null; TimedOut = $false }
        }
        else { $tools = @($capturedNames | ForEach-Object { New-MockTool $_ }) }

        $response = @{ jsonrpc = '2.0'; id = $RequestObject.id; result = @{ tools = $tools } }
        return [pscustomobject]@{ HttpStatus = 200; RawText = (ConvertTo-Json -InputObject $response -Compress -Depth 20); TransportError = $null; TimedOut = $false }
    }.GetNewClosure()
}

function Invoke-MockGuardCase {
    param(
        [string]$Mode = 'ready',
        [object[]]$Processes = @(),
        [object[]]$Listeners = @(),
        [bool]$TcpOpen = $true,
        [switch]$ListenerQueryError,
        [switch]$ProbePing,
        [int]$TimeoutMs = 250,
        [System.Collections.Generic.List[object]]$RequestLog = (New-Object System.Collections.Generic.List[object])
    )

    $capturedProcesses = @($Processes)
    $capturedListeners = @($Listeners)
    $capturedTcpOpen = $TcpOpen
    $processProvider = { return $capturedProcesses }.GetNewClosure()
    if ($ListenerQueryError) { $listenerProvider = { throw 'mock owner query denied' }.GetNewClosure() }
    else { $listenerProvider = { param($port) return $capturedListeners }.GetNewClosure() }
    $tcpProvider = { param($hostName, $port, $timeout) return $capturedTcpOpen }.GetNewClosure()
    $rpcProvider = New-MockMcpProvider -Mode $Mode -RequestLog $RequestLog

    $result = Invoke-NeMcpGuard -Endpoint 'http://mock.invalid/mcp' -TimeoutMs $TimeoutMs -ProcessProvider $processProvider -ListenerProvider $listenerProvider -TcpProbeProvider $tcpProvider -RpcProvider $rpcProvider -ProbePing:$ProbePing
    return $result
}

# No NoteExpress process, port closed.
$result = Invoke-MockGuardCase -TcpOpen:$false
Assert-Equal 'NO_PROCESS status' 'NO_PROCESS' $result.status
Assert-Equal 'NO_PROCESS exit code' 1 $result.exit_code
Assert-Equal 'closed endpoint skips tools/list' 0 $result.tool_count

# Process exists but the local MCP endpoint is not listening.
$result = Invoke-MockGuardCase -Processes @((New-MockProcess 11 'NoteExpress' 'C:\Program Files\NoteExpress\NoteExpress.exe')) -TcpOpen:$false
Assert-Equal 'PROCESS_RUNNING_PORT_CLOSED status' 'PROCESS_RUNNING_PORT_CLOSED' $result.status
Assert-Equal 'PROCESS_RUNNING_PORT_CLOSED exit code' 2 $result.exit_code

# A second address owned by another process must not be hidden by the first record.
$processes = @((New-MockProcess 11 'NoteExpress' 'C:\NE.exe'), (New-MockProcess 22 'OtherApp' 'C:\Other\other.exe'))
$listeners = @((New-MockListener '127.0.0.1' 11), (New-MockListener '::1' 22))
$result = Invoke-MockGuardCase -Processes $processes -Listeners $listeners
Assert-Equal 'PORT_CONFLICT status' 'PORT_CONFLICT' $result.status
Assert-Equal 'PORT_CONFLICT exit code' 3 $result.exit_code
Assert-Equal 'all listener rows inspected' 2 (@($result.checks | Where-Object { $_.name -eq 'port_owner' }).data.listener_count)

# If owner lookup fails, a reachable endpoint may prove MCP identity but never NoteExpress ownership.
$result = Invoke-MockGuardCase -Processes @((New-MockProcess 11 'NoteExpress' $null)) -ListenerQueryError
Assert-Equal 'PORT_OWNER_UNKNOWN status' 'PORT_OWNER_UNKNOWN' $result.status
Assert-Equal 'PORT_OWNER_UNKNOWN exit code' 4 $result.exit_code
Assert-True 'MCP identity can be confirmed separately' $result.protocol_identity_confirmed
Assert-True 'process ownership is not falsely confirmed' (-not $result.process_owner_confirmed)

# Multiple NoteExpress processes and IPv4/IPv6 listener records are all evaluated.
$processes = @((New-MockProcess 11 'NoteExpress' $null), (New-MockProcess 12 'NoteExpress' $null))
$listeners = @((New-MockListener '127.0.0.1' 11), (New-MockListener '::1' 12))
$result = Invoke-MockGuardCase -Mode thirty -Processes $processes -Listeners $listeners
Assert-Equal 'multiple valid owners status' 'READY' $result.status
Assert-Equal 'all NoteExpress processes reported' 2 (@($result.checks | Where-Object { $_.name -eq 'processes' }).data.Count)
Assert-Equal 'unreadable paths reported' 'UNKNOWN' (@($result.checks | Where-Object { $_.name -eq 'processes' }).data[0].path_status)
Assert-Equal 'thirty advertised tools' 30 $result.tool_count
Assert-Equal 'READY exit code' 0 $result.exit_code

# MCP/HTTP failure modes.
$processes = @((New-MockProcess 11 'NoteExpress' 'C:\NE.exe'))
$listeners = @((New-MockListener '127.0.0.1' 11))
$result = Invoke-MockGuardCase -Mode nonjson -Processes $processes -Listeners $listeners
Assert-Equal 'non-JSON body' 'MCP_INVALID_RESPONSE' $result.status
$result = Invoke-MockGuardCase -Mode badjsonrpc -Processes $processes -Listeners $listeners
Assert-Equal 'wrong JSON-RPC version' 'MCP_INVALID_RESPONSE' $result.status
$result = Invoke-MockGuardCase -Mode wrongid -Processes $processes -Listeners $listeners
Assert-Equal 'mismatched request id' 'MCP_INVALID_RESPONSE' $result.status
$result = Invoke-MockGuardCase -Mode rpcerror -Processes $processes -Listeners $listeners
Assert-Equal 'JSON-RPC error' 'MCP_CALL_FAILED' $result.status
$result = Invoke-MockGuardCase -Mode empty -Processes $processes -Listeners $listeners
Assert-Equal 'empty tools list' 'MCP_TOOLS_MISSING' $result.status
$result = Invoke-MockGuardCase -Mode missing -Processes $processes -Listeners $listeners
Assert-Equal 'required tools absent' 'MCP_TOOLS_MISSING' $result.status
$result = Invoke-MockGuardCase -Mode timeout -Processes $processes -Listeners $listeners -TimeoutMs 150
Assert-Equal 'HTTP request timeout' 'HTTP_UNAVAILABLE' $result.status
Assert-Equal 'HTTP timeout exit code' 5 $result.exit_code
$result = Invoke-MockGuardCase -Mode http500 -Processes $processes -Listeners $listeners
Assert-Equal 'HTTP non-success status' 'HTTP_UNAVAILABLE' $result.status

# Pagination and optional ping use only the advertised mock schema; no real NoteExpress calls occur.
$requestLog = New-Object System.Collections.Generic.List[object]
$result = Invoke-MockGuardCase -Mode paged -Processes $processes -Listeners $listeners -RequestLog $requestLog
Assert-Equal 'paginated tool count' 30 $result.tool_count
Assert-Equal 'pagination follows cursor' 2 $requestLog.Count
Assert-Equal 'second page sends cursor' 'page-2' $requestLog[1].params.cursor
Assert-Equal 'no initialize is forced' 'tools/list' $requestLog[0].method

$requestLog = New-Object System.Collections.Generic.List[object]
$result = Invoke-MockGuardCase -Mode ready -Processes $processes -Listeners $listeners -ProbePing -RequestLog $requestLog
$pingRequests = @($requestLog | Where-Object { $_.method -eq 'tools/call' })
Assert-Equal 'optional ping request count' 1 $pingRequests.Count
Assert-Equal 'optional ping name' 'noteexpress_ping' $pingRequests[0].params.name
Assert-Equal 'mock ping succeeds' 'PASS' (@($result.checks | Where-Object { $_.name -eq 'ping' }).status)

# Every result retains independent checks, including the client registration boundary.
$json = ConvertTo-Json -InputObject $result -Depth 12 -Compress
$decoded = ConvertFrom-Json -InputObject $json
Assert-True 'checks survive JSON output' (@($decoded.checks | Where-Object { $_.name -eq 'client_tool_registration' -and $_.status -eq 'NOT_CHECKED' }).Count -eq 1)
Assert-True 'ping is marked independently' (@($decoded.checks | Where-Object { $_.name -eq 'ping' }).Count -eq 1)

Write-Output "PASS: Test-Guard.ps1 ($script:assertions assertions; in-process Mock MCP RPC provider)"
