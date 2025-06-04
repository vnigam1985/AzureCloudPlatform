# Azure Function: Proxy Monitoring (PowerShell)
# Runs every second, performs one proxy request, sends single result to Log Analytics

using namespace System.Net

param($Timer)

# === CONFIGURATION ===
$workspaceId = $env:LOG_ANALYTICS_WORKSPACE_ID
$sharedKey = $env:LOG_ANALYTICS_SHARED_KEY
$logType = "ProxyMonitoring"
$proxyUrl = $env:PROXY_URL
$targetUrl = "https://www.google.com"

# === MONITORING ===
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$responseTimeMs = 0
$bytesDownloaded = 0
$speedMbps = 0.0
$statusCode = 0
$status = "DOWN"

$cmd = "curl.exe -x `"$proxyUrl`" -o NUL -s -w \"%{http_code} %{time_total} %{size_download} %{speed_download}\" --max-time 10 $targetUrl"
$output = cmd.exe /c $cmd
$parts = $output -split ' '

if ($parts.Count -ge 4) {
    $statusCode = [int]$parts[0]
    $responseTimeMs = [math]::Round([double]$parts[1] * 1000, 3)
    $bytesDownloaded = [int]$parts[2]
    $speedMbps = [math]::Round(([double]$parts[3] * 8) / 1MB, 4)
    if ($statusCode -eq 200) {
        $status = "UP"
    }
}

# === CREATE LOG ENTRY ===
$logBody = @{
    TimeGenerated = $timestamp
    ProxyStatus = $status
    HttpStatus = $statusCode
    ResponseTime_ms = $responseTimeMs
    SizeDownloaded_MB = [math]::Round($bytesDownloaded / 1MB, 4)
    DownloadSpeed_mbps = $speedMbps
    ExecutedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

# === SEND TO LOG ANALYTICS ===
function Send-LogAnalyticsData($workspaceId, $sharedKey, $logType, $body) {
    $jsonBody = $body | ConvertTo-Json -Compress
    $dateString = (Get-Date).ToUniversalTime().ToString("R")
    $signatureString = "POST`n$($jsonBody.Length)`napplication/json`nx-ms-date:$dateString`n/api/logs"
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($signatureString)
    $decodedKey = [Convert]::FromBase64String($sharedKey)
    $hmacSha256 = New-Object System.Security.Cryptography.HMACSHA256($decodedKey)
    $signatureBytes = $hmacSha256.ComputeHash($bytesToHash)
    $signature = [Convert]::ToBase64String($signatureBytes)

    $headers = @{
        "Content-Type" = "application/json"
        "Log-Type" = $logType
        "x-ms-date" = $dateString
        "Authorization" = "SharedKey $workspaceId:$signature"
    }

    $uri = "https://$workspaceId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $jsonBody
}

Send-LogAnalyticsData -workspaceId $workspaceId -sharedKey $sharedKey -logType $logType -body $logBody
