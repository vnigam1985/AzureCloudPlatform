# === CONFIGURATION ===
$PROXY_ADDRESS = "http://your.proxy.ip:port"
$TARGET_URL = "https://www.google.com"
$LOG_FILE = "C:\proxy_health.json"
$TOTAL_REQUESTS = 20

# === TIMESTAMP ===
$TIMESTAMP = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# === INIT METRICS ===
$TOTAL_TIME = 0.0
$SUCCESS_COUNT = 0
$LAST_HTTP_STATUS = 0

# === Run 20 HTTP requests via proxy ===
for ($i = 1; $i -le $TOTAL_REQUESTS; $i++) {
    try {
        $startTime = Get-Date
        $response = Invoke-WebRequest -Uri $TARGET_URL -Proxy $PROXY_ADDRESS -TimeoutSec 10 -UseBasicParsing
        $endTime = Get-Date
        $elapsedTime = ($endTime - $startTime).TotalSeconds

        if ($response.StatusCode -eq 200) {
            $SUCCESS_COUNT++
            $TOTAL_TIME += $elapsedTime
        }

        $LAST_HTTP_STATUS = $response.StatusCode
    }
    catch {
        if ($_.Exception.Response -ne $null) {
            $LAST_HTTP_STATUS = $_.Exception.Response.StatusCode.value__
        } else {
            $LAST_HTTP_STATUS = 0
        }
    }
}

# === Calculate average response time ===
if ($SUCCESS_COUNT -gt 0) {
    $AVG_RESPONSE_TIME = [math]::Round(($TOTAL_TIME / $SUCCESS_COUNT) * 1000, 3)
    $STATUS = "UP"
} else {
    $AVG_RESPONSE_TIME = 0
    $STATUS = "DOWN"
}

# === Create compact JSON object ===
$newEntry = @{
    TimeGenerated   = $TIMESTAMP
    ProxyStatus     = $STATUS
    HttpStatus      = $LAST_HTTP_STATUS
    ResponseTime_ms = $AVG_RESPONSE_TIME
}

# === Read existing log or initialize ===
if (-not (Test-Path $LOG_FILE)) {
    $logArray = @()
} else {
    try {
        $logContent = Get-Content $LOG_FILE -Raw
        $logArray = $logContent | ConvertFrom-Json
        if ($logArray -isnot [System.Collections.IEnumerable]) {
            $logArray = @($logArray)
        }
    } catch {
        $logArray = @()
    }
}

# === Append and write compact JSON ===
$logArray = @($logArray) + $newEntry
# Write compact one-line JSON array to file
$logArray | ConvertTo-Json -Depth 3 -Compress | Set-Content -Encoding UTF8 -Path $LOG_FILE
