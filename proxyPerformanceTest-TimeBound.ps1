# === CONFIGURATION ===
$PROXY_ADDRESS = "http://your.proxy.ip:port"
$TARGET_URL = "https://www.google.com"
$LOG_FILE_JSON = "C:\proxy_health.log"
$LOG_FILE_CSV  = "C:\proxy_health.csv"
$DURATION_SECONDS = 600
$SLEEP_INTERVAL = 1

# === Timer Setup ===
$startTime = Get-Date
$endTime = $startTime.AddSeconds($DURATION_SECONDS)

# === OPTIONAL: Write CSV Header (Uncomment below to use CSV) ===
# if (-not (Test-Path $LOG_FILE_CSV)) {
#     "TimeGenerated,ProxyStatus,HttpStatus,ResponseTime_ms" | Out-File -Encoding utf8 -FilePath $LOG_FILE_CSV
# }

while ((Get-Date) -lt $endTime) {
    $TIMESTAMP = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $LAST_HTTP_STATUS = 0
    $RESPONSE_TIME_MS = 0
    $STATUS = "DOWN"

    try {
        $startReq = Get-Date
        $response = Invoke-WebRequest -Uri $TARGET_URL -Proxy $PROXY_ADDRESS -TimeoutSec 10 -UseBasicParsing
        $endReq = Get-Date
        $elapsed = ($endReq - $startReq).TotalSeconds
        $RESPONSE_TIME_MS = [math]::Round($elapsed * 1000, 3)
        if ($response.StatusCode -eq 200) {
            $STATUS = "UP"
        }
        $LAST_HTTP_STATUS = $response.StatusCode
    } catch {
        if ($_.Exception.Response -ne $null) {
            $LAST_HTTP_STATUS = $_.Exception.Response.StatusCode.value__
        }
    }

    # === NDJSON Log Line ===
    $logEntry = @{
        TimeGenerated   = $TIMESTAMP
        ProxyStatus     = $STATUS
        HttpStatus      = $LAST_HTTP_STATUS
        ResponseTime_ms = $RESPONSE_TIME_MS
    } | ConvertTo-Json -Compress

    Add-Content -Path $LOG_FILE_JSON -Value $logEntry

    # === CSV Log Line (Uncomment to use CSV instead) ===
    # "$TIMESTAMP,$STATUS,$LAST_HTTP_STATUS,$RESPONSE_TIME_MS" | Out-File -Append -Encoding utf8 -FilePath $LOG_FILE_CSV

    Start-Sleep -Seconds $SLEEP_INTERVAL
}
