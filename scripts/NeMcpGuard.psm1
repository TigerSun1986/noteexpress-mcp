Set-StrictMode -Version 2.0

$script:NeMcpHost = '127.0.0.1'
$script:NeMcpPort = 49527
$script:NeMcpUrl = 'http://127.0.0.1:49527/mcp'
$script:NeProcessName = 'NoteExpress'
$script:RequiredTools = @(
    'noteexpress_ping',
    'noteexpress_version',
    'noteexpress_get_server_status'
)

function Test-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) { return $false }
    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Get-ObjectValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    if (-not (Test-ObjectProperty -Object $Object -Name $Name)) { return ,$Default }
    if ($Object -is [System.Collections.IDictionary]) { return ,$Object[$Name] }
    return ,$Object.$Name
}

function Test-NeTcpEndpoint {
    param([string]$TargetHost, [int]$TargetPort, [int]$TimeoutMs)

    $client = $null
    $waitHandle = $null
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $client.BeginConnect($TargetHost, $TargetPort, $null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle
        if (-not $waitHandle.WaitOne($TimeoutMs, $false)) { return $false }
        $client.EndConnect($asyncResult)
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($waitHandle) { $waitHandle.Close() }
        if ($client) { $client.Close() }
    }
}

function Get-NeNetstatListener {
    param([int]$LocalPort)

    $netstatCommand = Get-Command 'netstat.exe' -ErrorAction Stop
    $output = @(& $netstatCommand.Source -ano -p tcp 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "netstat.exe exited with code $LASTEXITCODE." }

    $listenerRows = @()
    foreach ($line in $output) {
        if ($line -match ('^\s*TCP\s+(.+):' + [regex]::Escape([string]$LocalPort) + '\s+\S+\s+LISTENING\s+(\d+)\s*$')) {
            $listenerRows += [pscustomobject]@{
                LocalAddress = ([string]$Matches[1]).Trim()
                LocalPort = $LocalPort
                OwningProcess = [int]$Matches[2]
            }
        }
    }
    return $listenerRows
}

function Send-NeMcpJsonRpc {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)]$RequestObject,
        [int]$TimeoutMs = 4000
    )

    $request = $null
    $requestStream = $null
    $response = $null
    $reader = $null
    $rawText = ''
    $httpStatus = $null
    $transportError = $null
    $timedOut = $false
    try {
        $request = [System.Net.HttpWebRequest]::Create($Uri)
        $request.Method = 'POST'
        $request.ContentType = 'application/json'
        $request.Accept = 'application/json'
        $request.Timeout = $TimeoutMs
        $request.ReadWriteTimeout = $TimeoutMs
        # The endpoint is loopback; avoid machine proxy configuration redirecting it.
        $request.Proxy = $null

        $body = ConvertTo-Json -InputObject $RequestObject -Depth 20 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $request.ContentLength = $bytes.Length
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bytes, 0, $bytes.Length)
        $requestStream.Close()
        $requestStream = $null

        $response = $request.GetResponse()
        $httpStatus = [int]$response.StatusCode
        $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList @($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        $rawText = $reader.ReadToEnd()
    }
    catch [System.Net.WebException] {
        $exception = $_.Exception
        $timedOut = $exception.Status -eq [System.Net.WebExceptionStatus]::Timeout
        if ($exception.Response) {
            try {
                $response = $exception.Response
                $httpStatus = [int]$response.StatusCode
                $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList @($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
                $rawText = $reader.ReadToEnd()
            }
            catch { }
        }
        if ($null -eq $httpStatus) { $transportError = $exception.Message }
    }
    catch {
        $transportError = $_.Exception.Message
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($response) { $response.Close() }
        if ($requestStream) { $requestStream.Dispose() }
    }

    return [pscustomobject]@{
        HttpStatus = $httpStatus
        RawText = $rawText
        TransportError = $transportError
        TimedOut = $timedOut
    }
}

function Invoke-NeMcpRpc {
    param(
        [string]$Uri,
        $RequestObject,
        [int]$TimeoutMs,
        [scriptblock]$RpcProvider
    )

    if ($RpcProvider) {
        return & $RpcProvider $Uri $RequestObject $TimeoutMs
    }
    return Send-NeMcpJsonRpc -Uri $Uri -RequestObject $RequestObject -TimeoutMs $TimeoutMs
}

function Read-NeMcpResponse {
    param(
        $RpcResult,
        [int]$ExpectedId
    )

    if ($null -eq $RpcResult) {
        return [pscustomobject]@{ Kind = 'HTTP_UNAVAILABLE'; Message = 'No HTTP result was returned.'; Parsed = $null }
    }

    $httpStatus = Get-ObjectValue -Object $RpcResult -Name 'HttpStatus'
    if ($null -ne $httpStatus -and ([int]$httpStatus -lt 200 -or [int]$httpStatus -ge 300)) {
        $message = "HTTP status $httpStatus."
        $transportError = Get-ObjectValue -Object $RpcResult -Name 'TransportError'
        if ($transportError) { $message += " $transportError" }
        return [pscustomobject]@{ Kind = 'HTTP_UNAVAILABLE'; Message = $message; Parsed = $null }
    }

    $transportError = Get-ObjectValue -Object $RpcResult -Name 'TransportError'
    if ($transportError) {
        return [pscustomobject]@{ Kind = 'HTTP_UNAVAILABLE'; Message = [string]$transportError; Parsed = $null }
    }

    $rawText = Get-ObjectValue -Object $RpcResult -Name 'RawText'
    if (-not $rawText) {
        return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = 'HTTP returned no JSON-RPC body.'; Parsed = $null }
    }

    try { $parsed = ConvertFrom-Json -InputObject ([string]$rawText) -ErrorAction Stop }
    catch {
        return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = 'HTTP response body is not valid JSON.'; Parsed = $null }
    }

    if (-not (Test-ObjectProperty -Object $parsed -Name 'jsonrpc') -or [string]$parsed.jsonrpc -ne '2.0') {
        return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = 'Response is missing jsonrpc="2.0".'; Parsed = $parsed }
    }
    if (-not (Test-ObjectProperty -Object $parsed -Name 'id') -or [string]$parsed.id -ne [string]$ExpectedId) {
        return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = "JSON-RPC response id does not match request id $ExpectedId."; Parsed = $parsed }
    }
    if (Test-ObjectProperty -Object $parsed -Name 'error') {
        $errorObject = Get-ObjectValue -Object $parsed -Name 'error'
        $errorMessage = Get-ObjectValue -Object $errorObject -Name 'message' 'JSON-RPC returned an error.'
        return [pscustomobject]@{ Kind = 'MCP_CALL_FAILED'; Message = [string]$errorMessage; Parsed = $parsed }
    }
    if (-not (Test-ObjectProperty -Object $parsed -Name 'result')) {
        return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = 'JSON-RPC response has neither result nor error.'; Parsed = $parsed }
    }

    return [pscustomobject]@{ Kind = 'OK'; Message = 'Valid JSON-RPC response.'; Parsed = $parsed }
}

function Get-NeMcpToolList {
    param(
        [string]$Uri,
        [int]$TimeoutMs,
        [scriptblock]$RpcProvider
    )

    $allTools = New-Object System.Collections.Generic.List[object]
    $cursor = $null
    $seenCursors = @{}
    $pages = 0
    $maxPages = 100
    $completed = $false

    while ($pages -lt $maxPages) {
        $pages++
        $requestId = $pages
        $params = @{}
        if ($null -ne $cursor) { $params.cursor = $cursor }
        $requestObject = @{ jsonrpc = '2.0'; id = $requestId; method = 'tools/list'; params = $params }

        try { $rpcResult = Invoke-NeMcpRpc -Uri $Uri -RequestObject $requestObject -TimeoutMs $TimeoutMs -RpcProvider $RpcProvider }
        catch {
            return [pscustomobject]@{ Kind = 'HTTP_UNAVAILABLE'; Message = $_.Exception.Message; Pages = $pages; Tools = @(); RpcResponses = @() }
        }
        $responseState = Read-NeMcpResponse -RpcResult $rpcResult -ExpectedId $requestId
        if ($responseState.Kind -ne 'OK') {
            return [pscustomobject]@{ Kind = $responseState.Kind; Message = $responseState.Message; Pages = $pages; Tools = @(); RpcResponses = @($responseState.Parsed) }
        }

        $resultObject = $responseState.Parsed.result
        if (-not (Test-ObjectProperty -Object $resultObject -Name 'tools')) {
            return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = 'tools/list result is missing the tools array.'; Pages = $pages; Tools = @(); RpcResponses = @($responseState.Parsed) }
        }
        $pageTools = Get-ObjectValue -Object $resultObject -Name 'tools'
        if ($null -eq $pageTools -or ($pageTools -isnot [System.Array] -and $pageTools -isnot [System.Collections.IList])) {
            return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = 'tools/list result.tools is not an array.'; Pages = $pages; Tools = @(); RpcResponses = @($responseState.Parsed) }
        }
        foreach ($tool in $pageTools) {
            $name = Get-ObjectValue -Object $tool -Name 'name'
            $description = Get-ObjectValue -Object $tool -Name 'description'
            $inputSchema = Get-ObjectValue -Object $tool -Name 'inputSchema'
            if (-not ($name -is [string]) -or [string]::IsNullOrWhiteSpace($name) -or
                -not ($description -is [string]) -or $null -eq $inputSchema -or
                ($inputSchema -isnot [System.Collections.IDictionary] -and $inputSchema -isnot [pscustomobject])) {
                return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = 'A tools/list entry is missing a string name/description or object inputSchema.'; Pages = $pages; Tools = @(); RpcResponses = @($responseState.Parsed) }
            }
            $allTools.Add($tool)
        }

        $nextCursor = Get-ObjectValue -Object $resultObject -Name 'nextCursor'
        if ($null -eq $nextCursor -or [string]::IsNullOrEmpty([string]$nextCursor)) { $completed = $true; break }
        $cursorKey = [string]$nextCursor
        if ($seenCursors.ContainsKey($cursorKey)) {
            return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = 'tools/list repeated a pagination cursor.'; Pages = $pages; Tools = @($allTools.ToArray()); RpcResponses = @($responseState.Parsed) }
        }
        $seenCursors[$cursorKey] = $true
        $cursor = $cursorKey
    }

    if (-not $completed) {
        return [pscustomobject]@{ Kind = 'MCP_INVALID_RESPONSE'; Message = "tools/list exceeded the $maxPages-page safety limit."; Pages = $pages; Tools = @($allTools.ToArray()); RpcResponses = @() }
    }
    if ($allTools.Count -eq 0) {
        return [pscustomobject]@{ Kind = 'MCP_TOOLS_MISSING'; Message = 'tools/list returned an empty tools array.'; Pages = $pages; Tools = @(); RpcResponses = @() }
    }

    return [pscustomobject]@{ Kind = 'OK'; Message = 'tools/list pages were read successfully.'; Pages = $pages; Tools = @($allTools.ToArray()); RpcResponses = @() }
}

function Add-NeMcpCheck {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [string]$Status,
        [string]$Detail,
        $Data = $null
    )
    $check = [ordered]@{ name = $Name; status = $Status; detail = $Detail }
    if ($null -ne $Data) { $check.data = $Data }
    $Checks.Add([pscustomobject]$check)
}

function Invoke-NeMcpGuard {
    [CmdletBinding()]
    param(
        [switch]$ProbePing,
        [string]$Endpoint = $script:NeMcpUrl,
        [int]$TimeoutMs = 4000,
        [scriptblock]$ProcessProvider,
        [scriptblock]$ListenerProvider,
        [scriptblock]$TcpProbeProvider,
        [scriptblock]$RpcProvider
    )

    $checks = New-Object 'System.Collections.Generic.List[object]'
    $processSnapshot = @()
    $processQueryError = $null
    try {
        if ($ProcessProvider) { $processSnapshot = @(& $ProcessProvider) }
        else { $processSnapshot = @(Get-Process -ErrorAction Stop) }
    }
    catch { $processQueryError = $_.Exception.Message }

    if ($processQueryError) {
        Add-NeMcpCheck $checks 'processes' 'ERROR' "Could not enumerate processes: $processQueryError"
        $noteExpressProcesses = @()
    }
    else {
        $noteExpressProcesses = @($processSnapshot | Where-Object { $_.ProcessName -ieq $script:NeProcessName })
        if ($noteExpressProcesses.Count -eq 0) {
            Add-NeMcpCheck $checks 'processes' 'FAIL' 'No NoteExpress.exe process was found.'
        }
        else {
            $processData = @()
            foreach ($process in $noteExpressProcesses) {
                $path = $null
                $pathError = $null
                try { $path = [string]$process.Path } catch { $pathError = $_.Exception.Message }
                if (-not $path -and -not $pathError) { $pathError = 'Executable path was not available.' }
                $processData += [pscustomobject]@{ pid = [int]$process.Id; name = [string]$process.ProcessName; path = $path; path_status = if ($path) { 'READABLE' } else { 'UNKNOWN' }; path_detail = $pathError }
            }
            Add-NeMcpCheck $checks 'processes' 'PASS' "Found $($noteExpressProcesses.Count) NoteExpress.exe process(es)." $processData
        }
    }

    $listenerQuerySucceeded = $false
    $listenerQueryError = $null
    $listeners = @()
    try {
        if ($ListenerProvider) { $listeners = @(& $ListenerProvider $script:NeMcpPort) }
        else {
            if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { throw 'Get-NetTCPConnection is unavailable.' }
            $listeners = @(Get-NetTCPConnection -LocalPort $script:NeMcpPort -State Listen -ErrorAction Stop)
        }
        $listenerQuerySucceeded = $true
        $listenerData = @($listeners | ForEach-Object {
            [pscustomobject]@{ local_address = [string]$_.LocalAddress; local_port = [int]$_.LocalPort; owner_pid = [int]$_.OwningProcess }
        })
        Add-NeMcpCheck $checks 'listeners' 'PASS' "Listener query succeeded; found $($listeners.Count) listener record(s) across all local addresses." $listenerData
    }
    catch {
        $primaryListenerError = $_.Exception.Message
        if (-not $ListenerProvider) {
            try {
                $listeners = @(Get-NeNetstatListener -LocalPort $script:NeMcpPort)
                $listenerQuerySucceeded = $true
                $listenerData = @($listeners | ForEach-Object {
                    [pscustomobject]@{ local_address = [string]$_.LocalAddress; local_port = [int]$_.LocalPort; owner_pid = [int]$_.OwningProcess }
                })
                Add-NeMcpCheck $checks 'listeners' 'PASS' "Get-NetTCPConnection failed; read all listener rows from netstat.exe instead. Found $($listeners.Count) listener record(s)." $listenerData
            }
            catch {
                $listenerQueryError = "$primaryListenerError; netstat fallback failed: $($_.Exception.Message)"
                Add-NeMcpCheck $checks 'listeners' 'UNKNOWN' "Could not determine listening socket ownership: $listenerQueryError"
            }
        }
        else {
            $listenerQueryError = $primaryListenerError
            Add-NeMcpCheck $checks 'listeners' 'UNKNOWN' "Could not determine listening socket ownership: $listenerQueryError"
        }
    }

    $tcpOpen = $false
    try {
        if ($TcpProbeProvider) { $tcpOpen = [bool](& $TcpProbeProvider $script:NeMcpHost $script:NeMcpPort $TimeoutMs) }
        else { $tcpOpen = Test-NeTcpEndpoint -TargetHost $script:NeMcpHost -TargetPort $script:NeMcpPort -TimeoutMs ([Math]::Min($TimeoutMs, 1500)) }
        if ($tcpOpen) { Add-NeMcpCheck $checks 'tcp_connectivity' 'PASS' "TCP connection to $($script:NeMcpHost):$($script:NeMcpPort) succeeded." }
        else { Add-NeMcpCheck $checks 'tcp_connectivity' 'FAIL' "TCP connection to $($script:NeMcpHost):$($script:NeMcpPort) failed." }
    }
    catch {
        $tcpOpen = $false
        Add-NeMcpCheck $checks 'tcp_connectivity' 'ERROR' $_.Exception.Message
    }

    $ownerStatus = 'CLOSED'
    $ownerPids = @()
    $unresolvedOwnerRecords = @()
    $foreignOwners = @()
    if ($listeners.Count -gt 0) {
        foreach ($listener in $listeners) {
            $ownerPid = 0
            try { $ownerPid = [int]$listener.OwningProcess } catch { }
            if ($ownerPid -le 0) {
                $unresolvedOwnerRecords += [pscustomobject]@{ local_address = [string]$listener.LocalAddress; owner_pid = $null; process_name = $null; reason = 'No owning PID was returned.' }
                continue
            }
            if ($ownerPids -notcontains $ownerPid) { $ownerPids += $ownerPid }
            $ownerProcess = $null
            try { $ownerProcess = @($processSnapshot | Where-Object { [int]$_.Id -eq $ownerPid } | Select-Object -First 1)[0] } catch { }
            if ($null -eq $ownerProcess) {
                $unresolvedOwnerRecords += [pscustomobject]@{ local_address = [string]$listener.LocalAddress; owner_pid = $ownerPid; process_name = $null; reason = 'Owner PID could not be matched to an accessible process snapshot.' }
                continue
            }
            $ownerName = [string]$ownerProcess.ProcessName
            if ($ownerName -ine $script:NeProcessName) {
                $foreignOwners += [pscustomobject]@{ local_address = [string]$listener.LocalAddress; owner_pid = $ownerPid; process_name = $ownerName }
            }
        }

        if ($foreignOwners.Count -gt 0) { $ownerStatus = 'CONFLICT' }
        elseif ($unresolvedOwnerRecords.Count -gt 0 -or $processQueryError) { $ownerStatus = 'UNKNOWN' }
        else { $ownerStatus = 'NOTEEXPRESS' }
    }
    elseif ($tcpOpen) {
        $ownerStatus = 'UNKNOWN'
        $unresolvedOwnerRecords += [pscustomobject]@{ local_address = $script:NeMcpHost; owner_pid = $null; process_name = $null; reason = 'TCP is reachable but no listener owner record is available.' }
    }

    switch ($ownerStatus) {
        'NOTEEXPRESS' { Add-NeMcpCheck $checks 'port_owner' 'PASS' "Every one of the $($listeners.Count) listener record(s) maps to a NoteExpress.exe PID." @{ owner_pids = $ownerPids; listener_count = $listeners.Count } }
        'CONFLICT' { Add-NeMcpCheck $checks 'port_owner' 'FAIL' 'At least one listener record belongs to a process other than NoteExpress.exe.' @{ foreign_owners = $foreignOwners; owner_pids = $ownerPids; listener_count = $listeners.Count } }
        'UNKNOWN' { Add-NeMcpCheck $checks 'port_owner' 'UNKNOWN' 'TCP is reachable, but the port owner could not be confirmed. A running NoteExpress process is not used as a fallback.' @{ unresolved = $unresolvedOwnerRecords; owner_pids = $ownerPids; listener_count = $listeners.Count } }
        default { Add-NeMcpCheck $checks 'port_owner' 'SKIP' 'No listener was observed.' }
    }

    $tools = @()
    $toolNames = @()
    $toolListKind = 'SKIP'
    $toolListMessage = 'Skipped because the endpoint did not accept a TCP connection.'
    $toolListPages = 0
    $protocolIdentityConfirmed = $false
    if ($tcpOpen) {
        $toolList = Get-NeMcpToolList -Uri $Endpoint -TimeoutMs $TimeoutMs -RpcProvider $RpcProvider
        $toolListKind = $toolList.Kind
        $toolListMessage = $toolList.Message
        $toolListPages = [int]$toolList.Pages
        $tools = @($toolList.Tools)
        $toolNames = @($tools | ForEach-Object { [string]$_.name })
        if ($toolList.Kind -eq 'OK' -or $toolList.Kind -eq 'MCP_TOOLS_MISSING') {
            $protocolIdentityConfirmed = $true
            Add-NeMcpCheck $checks 'tools_list' 'PASS' "Valid JSON-RPC tools/list response received across $toolListPages page(s)." @{ pages = $toolListPages; tool_count = $tools.Count }
            if ($tools.Count -eq 0) { Add-NeMcpCheck $checks 'tool_schemas' 'FAIL' 'The tools array is empty.' }
            else { Add-NeMcpCheck $checks 'tool_schemas' 'PASS' "Validated name, description, and object inputSchema for $($tools.Count) tool(s)." }
        }
        elseif ($toolList.Kind -eq 'HTTP_UNAVAILABLE') {
            Add-NeMcpCheck $checks 'tools_list' 'FAIL' $toolList.Message
            Add-NeMcpCheck $checks 'tool_schemas' 'SKIP' 'No valid tools/list result was available.'
        }
        elseif ($toolList.Kind -eq 'MCP_CALL_FAILED') {
            Add-NeMcpCheck $checks 'tools_list' 'FAIL' "JSON-RPC tools/list returned an error: $($toolList.Message)"
            Add-NeMcpCheck $checks 'tool_schemas' 'SKIP' 'No valid tools/list result was available.'
        }
        else {
            Add-NeMcpCheck $checks 'tools_list' 'FAIL' $toolList.Message
            Add-NeMcpCheck $checks 'tool_schemas' 'FAIL' 'The tools/list response did not meet the expected JSON-RPC structure.'
        }

        if ($toolNames.Count -gt 0) {
            $missingTools = @($script:RequiredTools | Where-Object { $toolNames -notcontains $_ })
            if ($missingTools.Count -eq 0) { Add-NeMcpCheck $checks 'required_tools' 'PASS' 'All required guard tools are present.' $script:RequiredTools }
            else { Add-NeMcpCheck $checks 'required_tools' 'FAIL' "Missing required tool(s): $($missingTools -join ', ')." @{ required = $script:RequiredTools; missing = $missingTools } }
        }
        elseif ($toolListKind -eq 'MCP_TOOLS_MISSING') {
            Add-NeMcpCheck $checks 'required_tools' 'FAIL' 'No tools were returned.' $script:RequiredTools
        }
        else {
            Add-NeMcpCheck $checks 'required_tools' 'SKIP' 'Required tools could not be checked because tools/list failed.' $script:RequiredTools
        }
    }
    else {
        Add-NeMcpCheck $checks 'tools_list' 'SKIP' $toolListMessage
        Add-NeMcpCheck $checks 'tool_schemas' 'SKIP' $toolListMessage
        Add-NeMcpCheck $checks 'required_tools' 'SKIP' $toolListMessage $script:RequiredTools
    }

    $pingStatus = 'SKIP'
    $pingDetail = 'Ping was not requested. The guard does not assume noteexpress_ping calls are supported.'
    if ($ProbePing) {
        if ($toolNames -notcontains 'noteexpress_ping') {
            $pingDetail = 'noteexpress_ping is absent from tools/list; no call was sent.'
        }
        else {
            $pingTool = @($tools | Where-Object { $_.name -eq 'noteexpress_ping' } | Select-Object -First 1)[0]
            $inputSchema = Get-ObjectValue -Object $pingTool -Name 'inputSchema'
            $required = Get-ObjectValue -Object $inputSchema -Name 'required' @()
            if (@($required).Count -gt 0) {
                $pingDetail = 'Ping declares required arguments, so the guard did not guess values.'
            }
            else {
                try {
                    $pingRequest = @{ jsonrpc = '2.0'; id = 1001; method = 'tools/call'; params = @{ name = 'noteexpress_ping'; arguments = @{} } }
                    $pingRpc = Invoke-NeMcpRpc -Uri $Endpoint -RequestObject $pingRequest -TimeoutMs $TimeoutMs -RpcProvider $RpcProvider
                    $pingResponse = Read-NeMcpResponse -RpcResult $pingRpc -ExpectedId 1001
                    if ($pingResponse.Kind -eq 'MCP_CALL_FAILED') {
                        $pingStatus = 'FAIL'; $pingDetail = "tools/call returned a JSON-RPC error: $($pingResponse.Message)"
                    }
                    elseif ($pingResponse.Kind -ne 'OK') {
                        $pingStatus = 'FAIL'; $pingDetail = "Ping response was invalid: $($pingResponse.Message)"
                    }
                    elseif ((Test-ObjectProperty -Object $pingResponse.Parsed.result -Name 'isError') -and [bool]$pingResponse.Parsed.result.isError) {
                        $pingStatus = 'FAIL'; $pingDetail = 'MCP tool result reported isError=true.'
                    }
                    else {
                        $pingStatus = 'PASS'; $pingDetail = 'A tools/call request for noteexpress_ping returned a non-error JSON-RPC result.'
                    }
                }
                catch { $pingStatus = 'FAIL'; $pingDetail = $_.Exception.Message }
            }
        }
    }
    Add-NeMcpCheck $checks 'ping' $pingStatus $pingDetail
    Add-NeMcpCheck $checks 'client_tool_registration' 'NOT_CHECKED' 'This script cannot inspect the AI client tool registry. The current client must separately expose noteexpress_* tools.'

    $finalStatus = 'CHECK_ERROR'
    $finalMessage = 'The checks could not establish readiness.'
    $exitCode = 9
    if ($processQueryError) {
        $finalStatus = 'CHECK_ERROR'; $finalMessage = 'Could not inspect the local process table.'; $exitCode = 9
    }
    elseif ($ownerStatus -eq 'CONFLICT') {
        $finalStatus = 'PORT_CONFLICT'; $finalMessage = 'The endpoint is listening, but at least one listener belongs to another process.'; $exitCode = 3
    }
    elseif (-not $tcpOpen -and $listeners.Count -eq 0 -and $noteExpressProcesses.Count -gt 0) {
        $finalStatus = 'PROCESS_RUNNING_PORT_CLOSED'; $finalMessage = 'NoteExpress is running but port 49527 is not reachable.'; $exitCode = 2
    }
    elseif (-not $tcpOpen -and $listeners.Count -eq 0 -and $noteExpressProcesses.Count -eq 0) {
        $finalStatus = 'NO_PROCESS'; $finalMessage = 'No NoteExpress process was found and the MCP endpoint is closed.'; $exitCode = 1
    }
    elseif (-not $tcpOpen -and $listeners.Count -gt 0) {
        $finalStatus = 'HTTP_UNAVAILABLE'; $finalMessage = 'A listener was reported, but the required loopback endpoint could not be reached.'; $exitCode = 5
    }
    elseif ($toolListKind -eq 'HTTP_UNAVAILABLE') {
        $finalStatus = 'HTTP_UNAVAILABLE'; $finalMessage = 'TCP is reachable, but the MCP HTTP request failed.'; $exitCode = 5
    }
    elseif ($toolListKind -eq 'MCP_CALL_FAILED') {
        $finalStatus = 'MCP_CALL_FAILED'; $finalMessage = 'The server returned a JSON-RPC error for tools/list.'; $exitCode = 8
    }
    elseif ($toolListKind -eq 'MCP_INVALID_RESPONSE') {
        $finalStatus = 'MCP_INVALID_RESPONSE'; $finalMessage = 'The endpoint response did not match the expected JSON-RPC tools/list structure.'; $exitCode = 6
    }
    elseif ($toolListKind -eq 'MCP_TOOLS_MISSING') {
        $finalStatus = 'MCP_TOOLS_MISSING'; $finalMessage = 'The server returned an empty tools list.'; $exitCode = 7
    }
    elseif ($toolNames.Count -gt 0 -and @($script:RequiredTools | Where-Object { $toolNames -notcontains $_ }).Count -gt 0) {
        $finalStatus = 'MCP_TOOLS_MISSING'; $finalMessage = 'The MCP tools list is missing one or more required NoteExpress guard tools.'; $exitCode = 7
    }
    elseif ($ProbePing -and $pingStatus -eq 'FAIL') {
        $finalStatus = 'MCP_CALL_FAILED'; $finalMessage = 'The optional noteexpress_ping probe failed.'; $exitCode = 8
    }
    elseif ($ownerStatus -eq 'UNKNOWN') {
        $finalStatus = 'PORT_OWNER_UNKNOWN'; $finalMessage = 'MCP tools were discovered, but the listening process could not be verified as NoteExpress.'; $exitCode = 4
    }
    elseif ($ownerStatus -eq 'NOTEEXPRESS') {
        $finalStatus = 'READY'; $finalMessage = 'NoteExpress owns every observed listener and its MCP tools/list response is valid.'; $exitCode = 0
    }

    return [pscustomobject]@{
        status = $finalStatus
        exit_code = $exitCode
        message = $finalMessage
        endpoint = $Endpoint
        protocol_identity_confirmed = $protocolIdentityConfirmed
        process_owner_confirmed = ($ownerStatus -eq 'NOTEEXPRESS')
        tool_count = $tools.Count
        tool_names = $toolNames
        checks = @($checks.ToArray())
        checked_at_utc = [DateTime]::UtcNow.ToString('o')
    }
}

Export-ModuleMember -Function Invoke-NeMcpGuard
