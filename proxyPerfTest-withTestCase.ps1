# === CONFIGURATION ===
$PROXY_ADDRESS = "http://your.proxy.ip:port"
$TARGET_URL = "https://www.google.com"
$SUMMARY_LOG = "C:\proxy_summary_log.csv"
$RunId = 0

# === CSV HEADER ===
if (-not (Test-Path $SUMMARY_LOG)) {
    "RunId,DurationSec,SleepTimeSec,TotalRuns,UpCount,DownCount,MinResponseTime_ms,MaxResponseTime_ms,AvgResponseTime_ms,TotalDownloaded_MB,AvgDownloadSpeed_mbps" | Out-File -Encoding utf8 -FilePath $SUMMARY_LOG
}

function Run-ProxyTest {
    param(
        [int]$Duration,
        [int]$SleepTime
    )

    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($Duration)

    # === Metrics ===
    $TotalRuns = 0
    $UpCount = 0
    $DownCount = 0
    $TotalResponseTime = 0.0
    $MinResponseTime = [Double]::MaxValue
    $MaxResponseTime = 0.0
    $TotalBytesDownloaded = 0
    $TotalSpeedMbps = 0.0

    $iterationStart = Get-Date
    $runTimes = @()

    while ((Get-Date) -lt $endTime) {
        $now = Get-Date
        $elapsed = $now - $startTime

        # === Estimate Total Iterations ===
        $remainingTime = ($endTime - $now).TotalSeconds
        $percentComplete = ($elapsed.TotalSeconds / $Duration) * 100
        $avgRunTime = if ($runTimes.Count -gt 0) { ($runTimes | Measure-Object -Average).Average } else { 0 }
        $etaSec = [int]($avgRunTime * (($endTime - $now).TotalSeconds / ($SleepTime + $avgRunTime)))

        $eta = (Get-Date).AddSeconds($etaSec) - $now

        # === Live Console Feedback ===
        Write-Host "`r⏳ [$TotalRuns] Elapsed: $([int]$elapsed.TotalSeconds)s | ETA: $([int]$eta.TotalSeconds)s remaining... " -NoNewline

        $TIMESTAMP = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $curlCmd = "curl.exe -x `"$PROXY_ADDRESS`" -o NUL -s -w `"%{http_code} %{time_total} %{size_download} %{speed_download}`" --max-time 10 $TARGET_URL"
        $output = cmd.exe /c $curlCmd
        $parts = $output -split ' '

        if ($parts.Count -lt 4) {
            $HttpStatus = 0
            $ResponseTimeMs = 0
            $SizeMB = 0
            $SpeedMbps = 0
            $DownCount++
        }
        else {
            $HttpStatus = [int]$parts[0]
            $ResponseTimeMs = [math]::Round([double]$parts[1] * 1000, 3)
            $SizeDownloaded = [int]$parts[2]
            $SpeedDownloadBps = [double]$parts[3]

            $SizeMB = [math]::Round($SizeDownloaded / 1MB, 4)
            $SpeedMbps = [math]::Round(($SpeedDownloadBps * 8) / 1MB, 4)

            if ($HttpStatus -eq 200) {
                $UpCount++
            } else {
                $DownCount++
            }

            $TotalResponseTime += $ResponseTimeMs
            $TotalBytesDownloaded += $SizeDownloaded
            $TotalSpeedMbps += $SpeedMbps

            if ($ResponseTimeMs -lt $MinResponseTime) { $MinResponseTime = $ResponseTimeMs }
            if ($ResponseTimeMs -gt $MaxResponseTime) { $MaxResponseTime = $ResponseTimeMs }
        }

        # Track execution time per loop
        $runDuration = (Get-Date) - $iterationStart
        $runTimes += $runDuration.TotalSeconds
        $iterationStart = Get-Date

        $TotalRuns++
        Start-Sleep -Seconds $SleepTime
    }

    # === Final Calculations ===
    $AvgResponseTime = if ($TotalRuns -gt 0) { [math]::Round($TotalResponseTime / $TotalRuns, 2) } else { 0 }
    $TotalDownloadedMB = [math]::Round($TotalBytesDownloaded / 1MB, 2)
    $AvgDownloadSpeedMbps = if ($TotalRuns -gt 0) { [math]::Round($TotalSpeedMbps / $TotalRuns, 2) } else { 0 }

    # === Increment Run ID and Write to Summary CSV ===
    $Global:RunId++
    "`n✅ Completed RunId: $RunId | Duration: $Duration sec | TotalRuns: $TotalRuns"

    "$RunId,$Duration,$SleepTime,$TotalRuns,$UpCount,$DownCount,$MinResponseTime,$MaxResponseTime,$AvgResponseTime,$TotalDownloadedMB,$AvgDownloadSpeedMbps" | Out-File -Append -Encoding utf8 -FilePath $SUMMARY_LOG
}
# === TEST PLAN ===

# === TEST CASE DEFINITION (Duration + SleepTime) ===
$testCases = @(
    @{ Repeats = 10; Duration = 60;   SleepTime = 1 },
    @{ Repeats = 5;  Duration = 600;  SleepTime = 5 },
    @{ Repeats = 2;  Duration = 3600; SleepTime = 10 },
    @{ Repeats = 1;  Duration = 86400; SleepTime = 10 },
    @{ Repeats = 1;  Duration = 172800; SleepTime = 10 }
)

# === EXECUTE TEST PLAN ===
foreach ($case in $testCases) {
    for ($i = 1; $i -le $case.Repeats; $i++) {
        Write-Host "`n➡️  Running Test Case: Duration=$($case.Duration)s, Sleep=$($case.SleepTime)s (Run $i of $($case.Repeats))"
        Run-ProxyTest -Duration $case.Duration -SleepTime $case.SleepTime
    }
}
