#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ProtocolVersion = '2025-06-18',
    [int]$TimeoutMs = 5000
)

$ErrorActionPreference = 'Stop'
$endpoint = 'http://127.0.0.1:49527/mcp'
$sessionId = $null
$assertions = 0

function Assert-True {
    param([string]$Name, [bool]$Condition)
    $script:assertions++
    if (-not $Condition) { throw "ASSERT FAILED [$Name]" }
}

function Invoke-NeHttpMessage {
    param(
        [string]$Method,
        $Message,
        [hashtable]$Headers = @{}
    )

    $request = [System.Net.HttpWebRequest]::Create($endpoint)
    $request.Method = $Method
    $request.ContentType = 'application/json'
    $request.Accept = 'application/json, text/event-stream'
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.Proxy = $null
    foreach ($headerName in $Headers.Keys) {
        if ($headerName -eq 'Accept') { $request.Accept = [string]$Headers[$headerName] }
        else { $request.Headers[[string]$headerName] = [string]$Headers[$headerName] }
    }

    if ($null -ne $Message) {
        $json = ConvertTo-Json -InputObject $Message -Depth 20 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }

    $response = $null
    try { $response = $request.GetResponse() }
    catch [System.Net.WebException] {
        if ($_.Exception.Response) { $response = $_.Exception.Response }
        else { throw "HTTP $Method to $endpoint failed: $($_.Exception.Message)" }
    }

    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $responseHeaders = @{}
        foreach ($key in $response.Headers.AllKeys) { $responseHeaders[$key] = $response.Headers[$key] }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $body; Headers = $responseHeaders }
    }
    finally { $response.Close() }
}

function Get-JsonRpcResult {
    param($HttpResponse, [int]$ExpectedId, [string]$TestName)
    Assert-True "$TestName HTTP success" ($HttpResponse.StatusCode -ge 200 -and $HttpResponse.StatusCode -lt 300)
    Assert-True "$TestName response body present" (-not [string]::IsNullOrWhiteSpace($HttpResponse.Body))
    try { $rpc = ConvertFrom-Json -InputObject $HttpResponse.Body -ErrorAction Stop }
    catch { throw "ASSERT FAILED [$TestName JSON]: $($_.Exception.Message)" }
    Assert-True "$TestName JSON-RPC version" ($rpc.jsonrpc -eq '2.0')
    Assert-True "$TestName response id" ([string]$rpc.id -eq [string]$ExpectedId)
    if ($rpc.PSObject.Properties['error']) { throw "ASSERT FAILED [$TestName]: JSON-RPC error $($rpc.error.code): $($rpc.error.message)" }
    Assert-True "$TestName has result" ($null -ne $rpc.result)
    return $rpc.result
}

try {
    # Preserve and verify the exact unversioned tools/list form observed in the task.
    $legacy = Invoke-NeHttpMessage -Method 'POST' -Message @{ jsonrpc = '2.0'; id = 71999; method = 'tools/list'; params = @{} }
    $legacyResult = Get-JsonRpcResult -HttpResponse $legacy -ExpectedId 71999 -TestName 'unversioned tools/list'
    Assert-True 'unversioned tools array' ($legacyResult.tools -is [System.Array] -and $legacyResult.tools.Count -gt 0)

    $initialize = @{
        jsonrpc = '2.0'
        id = 71001
        method = 'initialize'
        params = @{
            protocolVersion = $ProtocolVersion
            capabilities = @{}
            clientInfo = @{ name = 'noteexpress-mcp-compat-test'; version = '1.0.0' }
        }
    }
    $initHttp = Invoke-NeHttpMessage -Method 'POST' -Message $initialize
    $initResult = Get-JsonRpcResult -HttpResponse $initHttp -ExpectedId 71001 -TestName 'initialize'
    Assert-True 'negotiated protocol version' ($initResult.protocolVersion -eq $ProtocolVersion)
    Assert-True 'server info returned' ($null -ne $initResult.serverInfo -and $initResult.serverInfo.name -eq 'NoteExpress-MCP')
    $sessionHeader = $initHttp.Headers.Keys | Where-Object { $_ -ieq 'Mcp-Session-Id' } | Select-Object -First 1
    if ($sessionHeader) { $sessionId = [string]$initHttp.Headers[$sessionHeader] }

    $protocolHeaders = @{ 'MCP-Protocol-Version' = $ProtocolVersion }
    if ($sessionId) { $protocolHeaders['Mcp-Session-Id'] = $sessionId }
    $initializedHttp = Invoke-NeHttpMessage -Method 'POST' -Headers $protocolHeaders -Message @{ jsonrpc = '2.0'; method = 'notifications/initialized' }
    Assert-True 'initialized notification HTTP success' ($initializedHttp.StatusCode -ge 200 -and $initializedHttp.StatusCode -lt 300)
    Assert-True 'initialized notification status' ($initializedHttp.StatusCode -eq 202)

    $tools = New-Object System.Collections.Generic.List[object]
    $cursor = $null
    $seenCursors = @{}
    $page = 0
    do {
        $page++
        if ($page -gt 100) { throw 'tools/list exceeded the 100-page safety limit.' }
        $params = @{}
        if ($cursor) { $params.cursor = $cursor }
        $listHttp = Invoke-NeHttpMessage -Method 'POST' -Headers $protocolHeaders -Message @{ jsonrpc = '2.0'; id = (71001 + $page); method = 'tools/list'; params = $params }
        $listResult = Get-JsonRpcResult -HttpResponse $listHttp -ExpectedId (71001 + $page) -TestName "versioned tools/list page $page"
        Assert-True "tools/list page $page has array" ($listResult.tools -is [System.Array])
        foreach ($tool in $listResult.tools) { $tools.Add($tool) }
        $cursor = [string]$listResult.nextCursor
        if ($cursor) {
            if ($seenCursors.ContainsKey($cursor)) { throw 'tools/list repeated a pagination cursor.' }
            $seenCursors[$cursor] = $true
        }
    } while ($cursor)

    $toolNames = @($tools | ForEach-Object { [string]$_.name })
    Assert-True 'versioned tools/list returned tools' ($tools.Count -gt 0)
    foreach ($requiredName in @('noteexpress_ping', 'noteexpress_version', 'noteexpress_get_server_status')) {
        Assert-True "required tool $requiredName" ($toolNames -contains $requiredName)
    }

    $versionTool = @($tools | Where-Object { $_.name -eq 'noteexpress_version' } | Select-Object -First 1)[0]
    $requiredArgs = @()
    $requiredProperty = $versionTool.inputSchema.PSObject.Properties['required']
    if ($requiredProperty -and $requiredProperty.Value) { $requiredArgs = @($requiredProperty.Value) }
    Assert-True 'version tool allows empty arguments' ($requiredArgs.Count -eq 0)
    $versionHttp = Invoke-NeHttpMessage -Method 'POST' -Headers $protocolHeaders -Message @{ jsonrpc = '2.0'; id = 71901; method = 'tools/call'; params = @{ name = 'noteexpress_version'; arguments = @{} } }
    $versionResult = Get-JsonRpcResult -HttpResponse $versionHttp -ExpectedId 71901 -TestName 'noteexpress_version'
    Assert-True 'version tool non-error result' (-not $versionResult.isError)
    $versionText = @($versionResult.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
    try { $versionData = ConvertFrom-Json -InputObject $versionText -ErrorAction Stop }
    catch { throw "Version result text was not JSON: $($_.Exception.Message)" }
    Assert-True 'version reports negotiated protocol' ($versionData.mcp_protocol -eq $ProtocolVersion)

    $pingTool = @($tools | Where-Object { $_.name -eq 'noteexpress_ping' } | Select-Object -First 1)[0]
    $pingRequired = @()
    $pingRequiredProperty = $pingTool.inputSchema.PSObject.Properties['required']
    if ($pingRequiredProperty -and $pingRequiredProperty.Value) { $pingRequired = @($pingRequiredProperty.Value) }
    Assert-True 'ping allows empty arguments' ($pingRequired.Count -eq 0)
    $pingHttp = Invoke-NeHttpMessage -Method 'POST' -Headers $protocolHeaders -Message @{ jsonrpc = '2.0'; id = 71902; method = 'tools/call'; params = @{ name = 'noteexpress_ping'; arguments = @{} } }
    $pingResult = Get-JsonRpcResult -HttpResponse $pingHttp -ExpectedId 71902 -TestName 'noteexpress_ping'
    Assert-True 'ping non-error result' (-not $pingResult.isError)

    Write-Output "PASS: Test-Protocol.ps1 ($script:assertions assertions; protocol $ProtocolVersion; $($tools.Count) tools; read-only calls only)"
}
finally {
    if ($sessionId) {
        try {
            $delete = Invoke-NeHttpMessage -Method 'DELETE' -Headers @{ 'Mcp-Session-Id' = $sessionId }
            Write-Output "SESSION_DELETE_HTTP=$($delete.StatusCode)"
        }
        catch { Write-Output "SESSION_DELETE_SKIPPED=$($_.Exception.Message)" }
    }
}
