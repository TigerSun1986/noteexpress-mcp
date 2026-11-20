#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$Force,
    [switch]$ProbeVersion
)

$ErrorActionPreference = 'Stop'
$Url = 'http://127.0.0.1:49527/mcp'
$TimeoutSeconds = 8

function Invoke-NeJsonRpcRaw {
    param([string]$Uri, $RequestObject, [int]$TimeoutMs = 8000)

    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'POST'
    $request.ContentType = 'application/json'
    $request.Accept = 'application/json'
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.Proxy = $null
    $body = ConvertTo-Json -InputObject $RequestObject -Depth 20 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    $request.ContentLength = $bodyBytes.Length
    $response = $null
    $stream = $null
    try {
        $stream = $request.GetRequestStream()
        $stream.Write($bodyBytes, 0, $bodyBytes.Length)
        $stream.Dispose()
        $stream = $null
        $response = $request.GetResponse()
        $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList @($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
        try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
        return [pscustomobject]@{ status = [int]$response.StatusCode; raw = $raw }
    }
    catch [System.Net.WebException] {
        $exception = $_.Exception
        if ($exception.Response) {
            $response = $exception.Response
            $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList @($response.GetResponseStream(), [System.Text.Encoding]::UTF8)
            try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
            return [pscustomobject]@{ status = [int]$response.StatusCode; raw = $raw }
        }
        throw "HTTP request to $Uri failed: $($exception.Message)"
    }
    finally {
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Close() }
    }
}

function Read-RpcEnvelope {
    param([string]$RawBody, [int]$ExpectedId)
    try { $envelope = ConvertFrom-Json -InputObject $RawBody -ErrorAction Stop }
    catch { throw 'The /mcp endpoint returned non-JSON content.' }
    if ($envelope.jsonrpc -ne '2.0') { throw 'The response did not contain jsonrpc="2.0".' }
    if ([string]$envelope.id -ne [string]$ExpectedId) { throw "The JSON-RPC response id did not match $ExpectedId." }
    if ($envelope.PSObject.Properties['error']) { throw "JSON-RPC error: $($envelope.error.message)" }
    if (-not $envelope.PSObject.Properties['result']) { throw 'The JSON-RPC response contained neither result nor error.' }
    return $envelope
}

$pages = New-Object System.Collections.Generic.List[object]
$tools = New-Object System.Collections.Generic.List[object]
$seenCursors = @{}
$cursor = $null
$pageNumber = 0
$completed = $false
while ($pageNumber -lt 100) {
    $pageNumber++
    $requestParams = @{}
    if ($null -ne $cursor) { $requestParams.cursor = $cursor }
    $rpcRequest = @{ jsonrpc = '2.0'; id = $pageNumber; method = 'tools/list'; params = $requestParams }
    $http = Invoke-NeJsonRpcRaw -Uri $Url -RequestObject $rpcRequest -TimeoutMs ($TimeoutSeconds * 1000)
    if ($http.status -lt 200 -or $http.status -ge 300) { throw "HTTP status $($http.status) from $Url." }
    $envelope = Read-RpcEnvelope -RawBody $http.raw -ExpectedId $pageNumber
    if (-not $envelope.result.PSObject.Properties['tools'] -or $envelope.result.tools -isnot [System.Array]) {
        throw 'tools/list result must contain a tools array.'
    }
    foreach ($tool in $envelope.result.tools) {
        if (-not $tool.name -or -not $tool.description -or $null -eq $tool.inputSchema -or $tool.inputSchema -isnot [pscustomobject]) {
            throw 'A tools/list entry is missing name, description, or object inputSchema.'
        }
        $tools.Add($tool)
    }
    $pages.Add([pscustomobject]@{
        request = $rpcRequest
        http_status = $http.status
        raw_response = $http.raw
    })
    $nextCursor = $envelope.result.nextCursor
    if ([string]::IsNullOrEmpty([string]$nextCursor)) { $completed = $true; break }
    if ($seenCursors.ContainsKey([string]$nextCursor)) { throw 'The server repeated a tools/list pagination cursor.' }
    $seenCursors[[string]$nextCursor] = $true
    $cursor = [string]$nextCursor
}
if (-not $completed) { throw 'tools/list exceeded the 100-page safety limit.' }
if ($tools.Count -eq 0) { throw 'tools/list returned an empty tools array.' }

$versionProbe = [pscustomobject]@{ status = 'NOT_REQUESTED'; detail = 'Only tools/list was called.'; raw_response = $null }
if ($ProbeVersion) {
    $versionTool = @($tools | Where-Object { $_.name -eq 'noteexpress_version' } | Select-Object -First 1)
    if ($versionTool.Count -eq 0) {
        $versionProbe = [pscustomobject]@{ status = 'SKIPPED'; detail = 'noteexpress_version was not advertised.'; raw_response = $null }
    }
    else {
        $required = @()
        $requiredProperty = $versionTool[0].inputSchema.PSObject.Properties['required']
        if ($null -ne $requiredProperty -and $null -ne $requiredProperty.Value) {
            $required = @($requiredProperty.Value | Where-Object { $null -ne $_ })
        }
        if ($required.Count -gt 0) {
            $versionProbe = [pscustomobject]@{ status = 'SKIPPED'; detail = 'noteexpress_version declares required arguments; no values were guessed.'; raw_response = $null }
        }
        else {
            $versionRequest = @{ jsonrpc = '2.0'; id = 1001; method = 'tools/call'; params = @{ name = 'noteexpress_version'; arguments = @{} } }
            $http = Invoke-NeJsonRpcRaw -Uri $Url -RequestObject $versionRequest -TimeoutMs ($TimeoutSeconds * 1000)
            if ($http.status -lt 200 -or $http.status -ge 300) {
                $versionProbe = [pscustomobject]@{ status = 'HTTP_ERROR'; detail = "HTTP status $($http.status)."; raw_response = $http.raw }
            }
            else {
                try {
                    $versionEnvelope = Read-RpcEnvelope -RawBody $http.raw -ExpectedId 1001
                    $versionStatus = 'TOOLS_CALL_RESPONSE'
                    if ($versionEnvelope.result.PSObject.Properties['isError'] -and $versionEnvelope.result.isError) { $versionStatus = 'TOOL_ERROR' }
                    $versionProbe = [pscustomobject]@{ status = $versionStatus; detail = 'This validates only this noteexpress_version call. Its returned value is not assumed to be an MCP protocol revision.'; raw_response = $http.raw }
                }
                catch { $versionProbe = [pscustomobject]@{ status = 'INVALID_OR_ERROR'; detail = $_.Exception.Message; raw_response = $http.raw } }
            }
        }
    }
}

if (-not $OutputPath) {
    $schemaDirectory = Join-Path $PSScriptRoot '..\references\tool-schemas'
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $OutputPath = Join-Path $schemaDirectory "noteexpress-tools-$stamp.json"
}
$fullOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $fullOutputPath) -and -not $Force) { throw "Output already exists. Use -Force to replace it: $fullOutputPath" }
$outputDirectory = Split-Path -Parent $fullOutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }

$capture = [ordered]@{
    captured_at_utc = [DateTime]::UtcNow.ToString('o')
    endpoint = $Url
    scope = 'The tested unversioned JSON-RPC tools/list request shape. This is not a claim of full conformance to a particular MCP revision.'
    page_count = $pages.Count
    tool_count = $tools.Count
    tool_names = @($tools | ForEach-Object { [string]$_.name })
    pages = @($pages.ToArray())
    tools = @($tools.ToArray())
    noteexpress_version_probe = $versionProbe
}
$json = ConvertTo-Json -InputObject $capture -Depth 30
[System.IO.File]::WriteAllText($fullOutputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "SCHEMA_SAVED=$fullOutputPath"
Write-Output "TOOL_COUNT=$($tools.Count)"
Write-Output "PAGES=$($pages.Count)"
Write-Output "VERSION_PROBE=$($versionProbe.status)"
