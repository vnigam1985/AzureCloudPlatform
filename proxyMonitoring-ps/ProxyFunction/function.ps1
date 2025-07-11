using namespace System.Net

param($Timer)

# === CONFIGURATION ===
$workspaceId = $env:LOG_ANALYTICS_WORKSPACE_ID
$sharedKey = $env:LOG_ANALYTICS_SHARED_KEY
$logType = "ProxyMonitoring"
$proxyUrl = $env:PROXY_URL
$targetUrls = @(
    "https://www.google.com",
    "https://www.microsoft.com",
    "https://www.github.com",
    "https://www.stackoverflow.com",
    "https://www.bing.com"
)

function Build-Signature {
    param($workspaceId, $sharedKey, $dateString, $contentLength, $method, $contentType, $resource)
    $stringToHash = "$method`n$contentLength`n$contentType`nx-ms-date:$dateString`n$resource"
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = $keyBytes
    $hashedBytes = $hmac.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($hashedBytes)
    return "SharedKey $workspaceId:$encodedHash"
}

function Send-LogAnalyticsData {
    param($bodyJson)
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $dateString = (Get-Date).ToUniversalTime().ToString("R")
    $contentLength = $bodyJson.Length
    $signature = Build-Signature -workspaceId $workspaceId -sharedKey $sharedKey -dateString $dateString -contentLength $contentLength -method $method -contentType $contentType -resource $resource

    $uri = "https://$workspaceId.ods.opinsights.azure.com$resource?api-version=2016-04-01"
    $headers = @{
        "Content-Type" = $contentType
        "Authorization" = $signature
        "Log-Type" = $logType
        "x-ms-date" = $dateString
    }

    Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $bodyJson
}

foreach ($url in $targetUrls) {
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $executedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $status = "Failure"
    $statusCode = 0
    $responseTimeMs = 0

    try {
        $start = Get-Date
        $response = Invoke-WebRequest -Uri $url -Proxy $proxyUrl -TimeoutSec 10 -UseBasicParsing
        $end = Get-Date
        $responseTimeMs = [math]::Round(($end - $start).TotalMilliseconds, 3)
        $statusCode = $response.StatusCode
        if ($statusCode -eq 200) {
            $status = "Success"
        }
    } catch {
        $status = "Failure"
        $responseTimeMs = 0
        $statusCode = 0
    }

    $logBody = @{
        TimeGenerated = $timestamp
        TargetUrl = $url
        ProxyStatus = $status
        HttpStatus = $statusCode
        ResponseTime_ms = $responseTimeMs
        ExecutedAt = $executedAt
    }

    $jsonBody = $logBody | ConvertTo-Json -Compress
    Send-LogAnalyticsData -bodyJson $jsonBody
}