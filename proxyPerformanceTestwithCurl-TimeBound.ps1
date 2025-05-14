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

    # Run curl and capture output
    $curlCmd = "curl.exe -x `"$PROXY_ADDRESS`" -o NUL -s -w `"%%{http_code} %%{time_total} %%{size_download} %%{speed_download}`" --max-time 10 $TARGET_URL"
    $output = cmd.exe /c $curlCmd
    $parts = $output -split ' '

    if ($parts.Count -lt 4) {
        # Invalid response (e.g., timeout)
        $HttpStatus = 0
        $ResponseTimeMs = 0
        $SizeMB = 0
        $SpeedMbps = 0
        $Status = "DOWN"
        $DownCount++
    }
    else {
        $HttpStatus = [int]$parts[0]
        $ResponseTimeMs = [math]::Round([double]$parts[1] * 1000, 3)
        $SizeDownloaded = [int]$parts[2]
        $SpeedDownloadBps = [double]$parts[3]

        $SizeMB = [math]::Round($SizeDownloaded / 1MB, 4)
        $SpeedMbps = [math]::Round(($SpeedDownloadBps * 8) / 1MB, 4)

        $Status = if ($HttpStatus -eq 200) { $UpCount++; "UP" } else { $DownCount++; "DOWN" }

        $TotalResponseTime += $ResponseTimeMs
        $TotalBytesDownloaded += $SizeDownloaded
        $TotalSpeedMbps += $SpeedMbps

        if ($ResponseTimeMs -lt $MinResponseTime) { $MinResponseTime = $ResponseTimeMs }
        if ($ResponseTimeMs -gt $MaxResponseTime) { $MaxResponseTime = $ResponseTimeMs }
    }

    $TotalRuns++

    # === NDJSON Log Line ===
    $logEntry = @{
        TimeGenerated       = $TIMESTAMP
        ProxyStatus         = $Status
        HttpStatus          = $HttpStatus
        ResponseTime_ms     = $ResponseTimeMs
        SizeDownloaded_MB   = $SizeMB
        DownloadSpeed_mbps  = $SpeedMbps
    } | ConvertTo-Json -Compress

    Add-Content -Path $LOG_FILE_JSON -Value $logEntry

    # === CSV Log Line (Optional) ===
    # "$TIMESTAMP,$Status,$HttpStatus,$ResponseTimeMs,$SizeMB,$SpeedMbps" | Out-File -Append -Encoding utf8 -FilePath $LOG_FILE_CSV

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
