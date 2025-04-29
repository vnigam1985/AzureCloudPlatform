# === CONFIGURATION ===
$proxyAddress = "http://your.proxy.ip:port"
$targetUrl = "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_92x30dp.png"  # small test file
$tempFile = "$env:TEMP\proxy_test_download.tmp"
$iterations = 10

# === SETUP PROXY ===
$webClient = New-Object System.Net.WebClient
$webClient.Proxy = New-Object System.Net.WebProxy($proxyAddress)

# === INIT METRICS ===
$latencyList = @()

Write-Host "Starting Proxy Performance Test..." -ForegroundColor Cyan
Write-Host "Proxy: $proxyAddress" 
Write-Host "Target: $targetUrl"
Write-Host "Iterations: $iterations"
Write-Host "-------------------------------------------"

# === START TEST ===
for ($i = 1; $i -le $iterations; $i++) {
    try {
        $startTime = Get-Date
        $webClient.DownloadFile($targetUrl, $tempFile)
        $endTime = Get-Date
        $latencyMs = ($endTime - $startTime).TotalMilliseconds
        $latencyList += $latencyMs

        Write-Host "Test $i Success - Latency = $([math]::Round($latencyMs, 2)) ms" -ForegroundColor Green
    } catch {
        $latencyList += 0
        Write-Host "Test $i Failed - Unable to download file" -ForegroundColor Red
    }
    
    # Optional: Wait 1 second between tests
    Start-Sleep -Seconds 1
}

# === CLEANUP ===
if (Test-Path $tempFile) {
    Remove-Item $tempFile -Force
}

# === CALCULATE AVERAGE ===
$successfulLatencies = $latencyList | Where-Object { $_ -gt 0 }
if ($successfulLatencies.Count -gt 0) {
    $averageLatency = ($successfulLatencies | Measure-Object -Average).Average
    Write-Host "-------------------------------------------"
    Write-Host "Average Latency (across $($successfulLatencies.Count) successful downloads): $([math]::Round($averageLatency, 2)) ms" -ForegroundColor Yellow
} else {
    Write-Host "No successful downloads. Proxy might be unreachable." -ForegroundColor Red
}

Write-Host "Test Completed."
