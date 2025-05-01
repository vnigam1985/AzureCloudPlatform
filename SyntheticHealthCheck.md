## Synthetic Health Checks (VM-Based Monitoring)

- **Install Azure Monitor Agent** 
SSH into your VM and install the agent:
```bash
wget https://aka.ms/InstallAzureMonitorAgentLinux -O InstallAzureMonitorAgentLinux.sh
sudo bash InstallAzureMonitorAgentLinux.sh
```

- **Create the Proxy Health Check Script**
- Create a script file /opt/monitoring/proxy_health_check.sh:
```bash
#!/bin/bash

# === CONFIGURATION ===
PROXY_ADDRESS="http://your.proxy.ip:port"   # Use http:// even for HTTPS traffic
TARGET_URL="https://www.google.com"
LOG_FILE="/var/log/proxy_health.log"
TOTAL_REQUESTS=20

# === TIMESTAMP ===
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# === INIT METRICS ===
TOTAL_TIME=0
SUCCESS_COUNT=0
LAST_HTTP_STATUS=0

# === Run 20 HTTP requests via proxy ===
for i in $(seq 1 $TOTAL_REQUESTS); do
    CURL_OUTPUT=$(curl -x $PROXY_ADDRESS -o /dev/null -s -w "%{http_code} %{time_total}" --max-time 10 $TARGET_URL)
    CURL_EXIT=$?
    
    HTTP_STATUS=$(echo $CURL_OUTPUT | awk '{print $1}')
    RESPONSE_TIME=$(echo $CURL_OUTPUT | awk '{print $2}')
    
    # Convert response time to milliseconds and add to total
    if [[ $CURL_EXIT -eq 0 && $HTTP_STATUS -eq 200 ]]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT+1))
        TOTAL_TIME=$(echo "$TOTAL_TIME + $RESPONSE_TIME" | bc)
    fi

    LAST_HTTP_STATUS=$HTTP_STATUS  # Save last for logging
done

# === Calculate average response time ===
if [[ $SUCCESS_COUNT -gt 0 ]]; then
    AVG_RESPONSE_TIME=$(echo "scale=3; $TOTAL_TIME / $SUCCESS_COUNT * 1000" | bc)  # in ms
    STATUS="UP"
else
    AVG_RESPONSE_TIME=0
    STATUS="DOWN"
fi

# === Log JSON entry ===
echo "{\"timestamp\":\"$TIMESTAMP\", \"proxy_status\":\"$STATUS\", \"http_status\":\"$LAST_HTTP_STATUS\", \"avg_response_time_ms\":$AVG_RESPONSE_TIME}" >> $LOG_FILE

```
- Make the script executable: 
```bash
sudo chmod +x /opt/monitoring/proxy_health_check.sh
```

Schedule the Script using Cron
Open the crontab editor:

```bash
crontab -e
```
- Add this line to run the script every 5 minutes:

```bash
*/5 * * * * /opt/monitoring/proxy_health_check.sh
```
- Alternatively we could use below script in Windows
```ps1
# === CONFIGURATION ===
$proxyAddress = "http://your.proxy.ip:port"
$targetUrl = "https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_92x30dp.png"  # small test file
$tempFile = "$env:TEMP\proxy_test_download.tmp"
$logFile = "C:\Monitoring\proxy_health_log.json"

# === TIMESTAMP ===
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# === SETUP PROXY ===
$webClient = New-Object System.Net.WebClient
$webClient.Proxy = New-Object System.Net.WebProxy($proxyAddress)

# === MEASURE LATENCY ===
try {
    $startTime = Get-Date
    $webClient.DownloadFile($targetUrl, $tempFile)
    $endTime = Get-Date
    $latencyMs = ($endTime - $startTime).TotalMilliseconds
    $status = "UP"
    $httpStatus = 200
} catch {
    $latencyMs = 0
    $status = "DOWN"
    $httpStatus = 0
}

# === CLEANUP TEMP FILE ===
if (Test-Path $tempFile) {
    Remove-Item $tempFile -Force
}

# === LOG JSON ENTRY ===
$logEntry = @{
    timestamp       = $timestamp
    proxy_status    = $status
    http_status     = $httpStatus
    response_time_ms = [math]::Round($latencyMs, 2)
} | ConvertTo-Json -Compress

# Ensure directory exists
if (!(Test-Path "C:\Monitoring")) {
    New-Item -ItemType Directory -Path "C:\Monitoring" | Out-Null
}

# Write log entry
Add-Content -Path $logFile -Value $logEntry

```

✅ Now the health check will run every 5 minutes and write to /var/log/proxy_health.log.

- **Set Up Data Collection Rule (DCR) in Azure**

- Go to Azure Portal → Monitor → Data Collection Rules.

- Create a new DCR:

    - Target Platform: Linux

    - Target Resource: Select your Linux VM

    - Data Sources → Collect Custom Logs

    - Log File Path: /var/log/proxy_health.log

    - Destination: Send to your Log Analytics Workspace

    - Give it a name like proxy-health-dcr

- Or use below YAML to create DCR

```yaml
location: your-region
properties:
  dataSources:
    customLogs:
    - streams:
      - Custom-ProxyHealth
      filePatterns:
      - /var/log/proxy_health.log
      name: ProxyHealthLogs
  destinations:
    logAnalytics:
    - workspaceResourceId: /subscriptions/your-subscription-id/resourceGroups/your-rg-name/providers/Microsoft.OperationalInsights/workspaces/your-laworkspace
      name: LAWorkspaceDestination
  dataFlows:
  - streams:
    - Custom-ProxyHealth
    destinations:
    - LAWorkspaceDestination
```

- Replace:
    -your-region
    - your-subscription-id
    - your-rg-name
    - your-laworkspace
with your real values.

- Create the DCR using Azure CLI:

```bash
az monitor data-collection rule create --resource-group your-rg-name --name proxy-health-dcr --location your-region --rule proxy-health-dcr.yaml
```

- **Verify Log Collection**

    -  Go to Log Analytics Workspace → Logs.
    - Run a query:
```kusto
CustomLog_CL
| where SourceSystem == "Linux"
| where RawData contains "proxy_status"
| sort by TimeGenerated desc
```
✅ You should see entries like:

```json
{"timestamp":"2024-04-27T18:00:00Z", "proxy_status":"UP"}
{"timestamp":"2024-04-27T18:05:00Z", "proxy_status":"UP"}
{"timestamp":"2024-04-27T18:10:00Z", "proxy_status":"DOWN"}
```
- **How to Create Alerts**
    - Go to Azure Monitor → Alerts → Create New Alert Rule.
    - Target your Log Analytics workspace.
    - Create a condition like:
```kusto
CustomLog_CL
| where RawData contains "proxy_status\":\"DOWN"
```
    - Set alert to fire if count > 0 in last 5 minutes.

    - Attach an Action Group (Email, Teams, SMS).
    
✅ You will now get notified if proxy becomes unreachable!

- **Visualization**
    - Go to Azure Monitor → Workbooks.
    - Create a simple graph showing Proxy Status over Time based on logs.

```kusto
CustomLog_CL
| extend Status = extract(@"proxy_status\":\"(UP|DOWN)", 1, RawData)
| summarize count() by Status, bin(TimeGenerated, 5m)
| render timechart
```