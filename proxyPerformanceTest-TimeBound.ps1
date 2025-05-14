# === CONFIGURATION ===
$PROXY_ADDRESS = "http://your.proxy.ip:port"
$TARGET_URL = "https://www.google.com"
$LOG_FILE_JSON = "C:\proxy_health.log"
$LOG_FILE_CSV = "C:\proxy_health.csv"
$DURATION_SECONDS = 600
$SLEEP_INTERVAL = 1

# === METRICS INITIALIZATION ===
$TotalRuns = 0
$UpCount = 0
$DownCount = 0
$TotalResponseTime = 0.0
$MinResponseTime = [Double]::MaxValue
$MaxResponseTime = 0.0
$TotalBytesDownloaded = 0
$TotalSpeedMbps = 0.0

# === OPTIONAL: CSV HEADER ===
# if (-not (Test-Path $LOG_FILE_CSV)) {
#     "TimeGenerated,ProxyStatus,HttpStatus,ResponseTime_ms,SizeDownloaded_MB,DownloadSpeed_mbps" | Out-File -Encoding utf8 -FilePath $LOG_FILE_CSV
# }

# === TIMER SETUP ===
$startTime = Get-Date
$endTime = $startTime.AddSeconds($DURATION_SECONDS)

while ((Get-Date) -lt $endTime) {
    $TIMESTAMP = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $LAST_HTTP_STATUS = 0
    $RESPONSE_TIME_MS = 0
    $STATUS = "DOWN"
    $SIZE_DOWNLOADED = 0
    $SIZE_MB = 0
    $SPEED_MBPS = 0

    try {
        $startReq = Get-Date
        $response = Invoke-WebRequest -Uri $TARGET_URL -Proxy $PROXY_ADDRESS -TimeoutSec 10 -UseBasicParsing
        $endReq = Get-Date

        $elapsed = ($endReq - $startReq).TotalSeconds
        $RESPONSE_TIME_MS = [math]::Round($elapsed * 1000, 3)
        $LAST_HTTP_STATUS = $response.StatusCode

        if ($response.StatusCode -eq 200) {
            $STATUS = "UP"
            $UpCount++
        } else {
            $DownCount++
        }

        $SIZE_DOWNLOADED = $response.RawContentLength
        $SIZE_MB = [math]::Round($SIZE_DOWNLOADED / 1MB, 4)

        if ($elapsed -gt 0) {
            $SPEED_MBPS = [math]::Round((($SIZE_DOWNLOADED * 8) / $elapsed) / 1MB, 4)
        }
    }
    catch {
        $DownCount++
        if ($_.Exception.Response -ne $null) {
            $LAST_HTTP_STATUS = $_.Exception.Response.StatusCode.value__
        }
    }

    # Update metrics
    $TotalRuns++
    $TotalResponseTime += $RESPONSE_TIME_MS
    $TotalBytesDownloaded += $SIZE_DOWNLOADED
    $TotalSpeedMbps += $SPEED_MBPS

    if ($RESPONSE_TIME_MS -lt $MinResponseTime) { $MinResponseTime = $RESPONSE_TIME_MS }
    if ($RESPONSE_TIME_MS -gt $MaxResponseTime) { $MaxResponseTime = $RESPONSE_TIME_MS }

    # === NDJSON Log Line ===
    $logEntry = @{
        TimeGenerated       = $TIMESTAMP
        ProxyStatus         = $STATUS
        HttpStatus          = $LAST_HTTP_STATUS
        ResponseTime_ms     = $RESPONSE_TIME_MS
        SizeDownloaded_MB   = $SIZE_MB
        DownloadSpeed_mbps  = $SPEED_MBPS
    } | ConvertTo-Json -Compress

    Add-Content -Path $LOG_FILE_JSON -Value $logEntry

    # === CSV Log Line (Optional) ===
    # "$TIMESTAMP,$STATUS,$LAST_HTTP_STATUS,$RESPONSE_TIME_MS,$SIZE_MB,$SPEED_MBPS" | Out-File -Append -Encoding utf8 -FilePath $LOG_FILE_CSV

    Start-Sleep -Seconds $SLEEP_INTERVAL
}

# === FINAL SUMMARY ===
$AvgResponseTime = if ($TotalRuns -gt 0) { [math]::Round($TotalResponseTime / $TotalRuns, 2) } else { 0 }
$TotalDownloadedMB = [math]::Round($TotalBytesDownloaded / 1MB, 2)
$AvgDownloadSpeedMbps = if ($TotalRuns -gt 0) { [math]::Round($TotalSpeedMbps / $TotalRuns, 2) } else { 0 }

# === PRINT CSV SUMMARY TO SHELL ===
"`nSummary:"
"TotalRuns,UpCount,DownCount,MinResponseTime_ms,MaxResponseTime_ms,AvgResponseTime_ms,TotalDownloaded_MB,AvgDownloadSpeed_mbps"
"$TotalRuns,$UpCount,$DownCount,$MinResponseTime,$MaxResponseTime,$AvgResponseTime,$TotalDownloadedMB,$AvgDownloadSpeedMbps"
