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

# === TIMESTAMP ===
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# === Run HTTP request via proxy ===
CURL_OUTPUT=$(curl -x $PROXY_ADDRESS -o /dev/null -s -w "%{http_code} %{time_total}" --max-time 10 $TARGET_URL)
CURL_EXIT=$?

# === Parse result ===
HTTP_STATUS=$(echo $CURL_OUTPUT | awk '{print $1}')
RESPONSE_TIME=$(echo $CURL_OUTPUT | awk '{print $2}')

# === Determine final status ===
if [[ $CURL_EXIT -eq 0 && $HTTP_STATUS -eq 200 ]]; then
    STATUS="UP"
else
    STATUS="DOWN"
fi

# === Log JSON entry ===
echo "{\"timestamp\":\"$TIMESTAMP\", \"proxy_status\":\"$STATUS\", \"http_status\":\"$HTTP_STATUS\", \"response_time_ms\":$(echo "$RESPONSE_TIME*1000" | bc)}" >> $LOG_FILE

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