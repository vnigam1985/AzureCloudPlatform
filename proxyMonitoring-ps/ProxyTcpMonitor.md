# Proxy Monitor Azure Functions

This project deploys two PowerShell-based Azure Functions in an Azure Function App (`ProxyMonitorFunctionApp`) within an App Service Environment (ASE) to monitor a proxy:
1. **ProxyMonitor**: Performs HTTP monitoring by accessing five public URLs every 10 seconds through a specified proxy URL, validating the proxy’s server certificate with CA and root CA certificates stored in the **LocalMachine** certificate store, and logging metrics to a Log Analytics table (`ProxyMonitorLogs_CL`).
2. **TcpProxyMonitor**: Performs TCP monitoring on the proxy’s host and port every 10 seconds, logging metrics to a separate Log Analytics table (`TcpProxyMonitorLogs_CL`) without certificate validation.

Both functions use a user-assigned managed identity (`ProxyMonitorIdentity`) for authentication with the Logs Ingestion API and send logs to a Log Analytics workspace (`ProxyMonitorWorkspace`) using a shared Data Collection Endpoint (DCE).

## Prerequisites
- **Azure Subscription**: With access to an App Service Environment (ASE).
- **PowerShell**: Version 7.2 or later installed locally.
- **Azure CLI** or **Azure PowerShell module**: For deployment and configuration.
- **Azure Functions Core Tools**: Version 4.x for local development.
- **Log Analytics Workspace**: Created in Azure (e.g., `ProxyMonitorWorkspace`).
- **URLs to Monitor (HTTP)**: Five public URLs (e.g., `https://example.com`).
- **Proxy URL**: The URL of the proxy to test (e.g., `https://<proxy-host>:<port>` or `http://<proxy-host>:<port>`).
- **Proxy Certificates (for HTTP function only)**:
  - CA certificate (`ca-cert.pem`): Intermediate CA certificate for the proxy’s server certificate.
  - Root CA certificate (`rootca-cert.pem`): Root CA certificate for the proxy’s server certificate.
- **OpenSSL** (optional): For converting `.pem` to `.cer` if needed for HTTP function certificates.
- **Basic Familiarity**: With Azure Functions, PowerShell, Azure Monitor, managed identities, and certificate management (for HTTP function).

## Existing Resources
The following resources are assumed to be already set up from the HTTP monitoring function (`ProxyMonitor`):
- **Function App**: `ProxyMonitorFunctionApp` in an ASE, running PowerShell Core (e.g., version 7.4).
- **Log Analytics Workspace**: `ProxyMonitorWorkspace` with Workspace ID and Resource ID (e.g., `/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.OperationalInsights/workspaces/ProxyMonitorWorkspace`).
- **Data Collection Endpoint (DCE)**: `ProxyMonitorDCE` with Logs ingestion URI (e.g., `https://<dce-name>.<region>.ingest.monitor.azure.com`) and Resource ID (e.g., `/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Insights/dataCollectionEndpoints/ProxyMonitorDCE`).
- **Data Collection Rule (DCR)**: `ProxyMonitorDCR` for HTTP monitoring, with Immutable ID (e.g., `dcr-abcdef1234567890`) and table `ProxyMonitorLogs_CL`.
- **User-Assigned Managed Identity**: `ProxyMonitorIdentity` with Client ID (e.g., `12345678-1234-1234-1234-1234567890ab`), assigned to the Function App and granted **Monitoring Metrics Publisher** role on `ProxyMonitorDCR`.
- **Certificates (for HTTP function)**: CA and root CA certificates uploaded to the **LocalMachine** certificate store, with thumbprints configured in `WEBSITE_LOAD_CERTIFICATES`, `CaCertThumbprint`, and `RootCaCertThumbprint` application settings.
- **Application Settings**:
  - `DceEndpoint`: DCE logs ingestion URI.
  - `DcrImmutableId`: Immutable ID of `ProxyMonitorDCR`.
  - `TableName`: `ProxyMonitorLogs_CL`.
  - `ManagedIdentityClientId`: Client ID of `ProxyMonitorIdentity`.
  - `ProxyUrl`: Proxy URL (e.g., `https://<proxy-host>:<port>`).
  - `CaCertThumbprint`: Thumbprint of the CA certificate.
  - `RootCaCertThumbprint`: Thumbprint of the root CA certificate.
  - `WEBSITE_LOAD_CERTIFICATES`: Comma-separated thumbprints of CA and root CA certificates.

## Setup Instructions for TCP Monitoring Function

### Step 1: Create a New Data Collection Rule (DCR) for TCP Monitoring
Create a new DCR (`TcpProxyMonitorDCR`) for the TCP monitoring function to log metrics to a new Log Analytics table (`TcpProxyMonitorLogs_CL`) using the existing DCE and workspace.

1. **Define the DCR Configuration**:
   - Table: `TcpProxyMonitorLogs_CL`
   - Columns: `Timestamp` (datetime), `Host` (string), `Port` (int), `TcpStatus` (string), `ResponseTimeMs` (double), `ExecutedAt` (datetime).

2. **Create the DCR via ARM Template**:
   - Save the following ARM template as `tcp-dcr-template.json`:
     ```json
     {
       "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
       "contentVersion": "1.0.0.0",
       "parameters": {
         "dcrName": { "type": "string", "defaultValue": "TcpProxyMonitorDCR" },
         "location": { "type": "string", "defaultValue": "<your-region>" },
         "workspaceResourceId": { "type": "string" },
         "dceResourceId": { "type": "string" }
       },
       "resources": [
         {
           "type": "Microsoft.Insights/dataCollectionRules",
           "apiVersion": "2023-03-11",
           "name": "[parameters('dcrName')]",
           "location": "[parameters('location')]",
           "properties": {
             "dataCollectionEndpointId": "[parameters('dceResourceId')]",
             "streamDeclarations": {
               "Custom-TcpProxyMonitorLogs_CL": {
                 "columns": [
                   { "name": "Timestamp", "type": "datetime" },
                   { "name": "Host", "type": "string" },
                   { "name": "Port", "type": "int" },
                   { "name": "TcpStatus", "type": "string" },
                   { "name": "ResponseTimeMs", "type": "double" },
                   { "name": "ExecutedAt", "type": "datetime" }
                 ]
               }
             },
             "destinations": {
               "logAnalytics": [
                 {
                   "name": "ProxyMonitorWorkspace",
                   "workspaceResourceId": "[parameters('workspaceResourceId')]"
                 }
               ]
             },
             "dataFlows": [
               {
                 "streams": ["Custom-TcpProxyMonitorLogs_CL"],
                 "destinations": ["ProxyMonitorWorkspace"],
                 "outputStream": "Custom-TcpProxyMonitorLogs_CL"
               }
             ]
           }
         }
       ]
     }
     ```
   - Deploy the ARM template using Azure CLI:
     ```bash
     az deployment group create --resource-group <your-resource-group> --template-file tcp-dcr-template.json --parameters dcrName=TcpProxyMonitorDCR location=<your-region> workspaceResourceId=<your-workspace-resource-id> dceResourceId=<your-dce-resource-id>
     ```
     - Replace `<your-resource-group>`, `<your-region>`, `<your-workspace-resource-id>`, and `<your-dce-resource-id>` with your existing values (e.g., `ProxyMonitorWorkspace` and `ProxyMonitorDCE`).
   - Note the **DCR Immutable ID** from the DCR’s **JSON View** under `immutableId` in the Azure portal (e.g., `dcr-1234567890abcdef`).

3. **Alternative: Create DCR via PowerShell**:
   - Use the following PowerShell script:
     ```powershell
     # Install Azure PowerShell module if not already installed
     Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force

     # Connect to Azure
     Connect-AzAccount

     # Define variables
     $resourceGroup = "<your-resource-group>" # e.g., "MyResourceGroup"
     $dcrName = "TcpProxyMonitorDCR"
     $location = "<your-region>" # e.g., "eastus"
     $workspaceResourceId = "<your-workspace-resource-id>" # e.g., "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.OperationalInsights/workspaces/ProxyMonitorWorkspace"
     $dceResourceId = "<your-dce-resource-id>" # e.g., "/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Insights/dataCollectionEndpoints/ProxyMonitorDCE"

     # Validate Resource IDs
     try {
         $workspace = Get-AzResource -ResourceId $workspaceResourceId -ErrorAction Stop
         if ($workspace.ResourceType -ne "Microsoft.OperationalInsights/workspaces") {
             throw "Invalid workspace resource ID: $workspaceResourceId"
         }
         Write-Output "Workspace validated: $workspaceResourceId"
     } catch {
         Write-Error "Failed to validate workspace resource ID: $_"
         exit
     }

     try {
         $dce = Get-AzResource -ResourceId $dceResourceId -ErrorAction Stop
         if ($dce.ResourceType -ne "Microsoft.Insights/dataCollectionEndpoints") {
             throw "Invalid DCE resource ID: $dceResourceId"
         }
         Write-Output "DCE validated: $dceResourceId"
     } catch {
         Write-Error "Failed to validate DCE resource ID: $_"
         exit
     }

     # Define DCR configuration
     $dcrProperties = @{
         dataCollectionEndpointId = $dceResourceId
         streamDeclarations = @{
             "Custom-TcpProxyMonitorLogs_CL" = @{
                 columns = @(
                     @{ name = "Timestamp"; type = "datetime" },
                     @{ name = "Host"; type = "string" },
                     @{ name = "Port"; type = "int" },
                     @{ name = "TcpStatus"; type = "string" },
                     @{ name = "ResponseTimeMs"; type = "double" },
                     @{ name = "ExecutedAt"; type = "datetime" }
                 )
             }
         }
         destinations = @{
             logAnalytics = @(
                 @{
                     name = "ProxyMonitorWorkspace"
                     workspaceResourceId = $workspaceResourceId
                 }
             )
         }
         dataFlows = @(
             @{
                 streams = @("Custom-TcpProxyMonitorLogs_CL")
                 destinations = @("ProxyMonitorWorkspace")
                 outputStream = "Custom-TcpProxyMonitorLogs_CL"
             }
         )
     }

     # Create the DCR
     try {
         $result = New-AzResource -ResourceGroupName $resourceGroup `
                                  -Location $location `
                                  -ResourceName $dcrName `
                                  -ResourceType "Microsoft.Insights/dataCollectionRules" `
                                  -Properties $dcrProperties `
                                  -Force `
                                  -ErrorAction Stop
         Write-Output "DCR created successfully: $dcrName"
     } catch {
         Write-Error "Failed to create DCR: $_"
         Write-Error "DCR Properties: $($dcrProperties | ConvertTo-Json -Depth 10)"
         exit
     }

     # Retrieve the DCR Immutable ID
     try {
         $dcr = Get-AzResource -ResourceGroupName $resourceGroup `
                               -ResourceName $dcrName `
                               -ResourceType "Microsoft.Insights/dataCollectionRules" `
                               -ErrorAction Stop
         $immutableId = $dcr.Properties.immutableId
         Write-Output "DCR Immutable ID: $immutableId"
     } catch {
         Write-Error "Failed to retrieve DCR Immutable ID: $_"
         exit
     }
     ```
     - Replace `<your-resource-group>`, `<your-region>`, `<your-workspace-resource-id>`, and `<your-dce-resource-id>` with your existing values.
     - Run the script and note the **DCR Immutable ID**.

4. **Grant Permissions to the User-Assigned Managed Identity**:
   - Navigate to the new DCR (`TcpProxyMonitorDCR`) in the Azure portal under **Monitor** > **Data Collection Rules**.
   - Go to **Access Control (IAM)** > **Add role assignment**.
   - Select the **Monitoring Metrics Publisher** role.
   - Assign access to **Managed identity**, select **User-assigned managed identity**, and choose `ProxyMonitorIdentity`.
   - Save the role assignment.
   - Verify the assignment in **Access Control (IAM)** > **View access** to ensure the managed identity has the **Monitoring Metrics Publisher** role on the new DCR.

### Step 2: Configure the Function App
1. **Add Application Settings**:
   - In the Azure portal, navigate to your Function App (`ProxyMonitorFunctionApp`) > **Settings** > **Configuration** > **Application settings**.
   - Add the following new settings:
     - `TcpDcrImmutableId`: The immutable ID of the new DCR (`TcpProxyMonitorDCR`), e.g., `dcr-1234567890abcdef`.
     - `TcpTableName`: `TcpProxyMonitorLogs_CL`.
   - Verify existing settings (for the HTTP function):
     - `DceEndpoint`: Your DCE logs ingestion URI (e.g., `https://<dce-name>.<region>.ingest.monitor.azure.com`).
     - `DcrImmutableId`: Immutable ID of `ProxyMonitorDCR` (e.g., `dcr-abcdef1234567890`).
     - `TableName`: `ProxyMonitorLogs_CL`.
     - `ManagedIdentityClientId`: Client ID of `ProxyMonitorIdentity` (e.g., `12345678-1234-1234-1234-1234567890ab`).
     - `ProxyUrl`: Proxy URL (e.g., `https://<proxy-host>:<port>` or `http://<proxy-host>:<port>`).
     - `CaCertThumbprint`: Thumbprint of the CA certificate (for HTTP function).
     - `RootCaCertThumbprint`: Thumbprint of the root CA certificate (for HTTP function).
     - `WEBSITE_LOAD_CERTIFICATES`: Comma-separated thumbprints of CA and root CA certificates (for HTTP function).
   - Save the settings.

2. **Verify User-Assigned Managed Identity**:
   - Ensure `ProxyMonitorIdentity` is assigned to the Function App (**Settings** > **Identity** > **User assigned**).
   - Confirm it has the **Monitoring Metrics Publisher** role on both `ProxyMonitorDCR` and `TcpProxyMonitorDCR`.

### Step 3: Create the TCP Monitoring Function
1. **Set Up Local Development Environment**:
   - If not already installed, install Azure Functions Core Tools:
     ```bash
     npm install -g azure-functions-core-tools@4 --unsafe-perm true
     ```
   - Navigate to your existing project directory (`ProxyMonitorFunction`), which contains the `ProxyMonitor` function.

2. **Create the TCP Monitoring Function**:
   - Create a new timer-triggered function:
     ```bash
     func new --name TcpProxyMonitor --template "TimerTrigger" --schedule "*/10 * * * * *"
     ```
   - This creates a new directory `TcpProxyMonitor` with `function.json` and `run.ps1`.

3. **Configure the Function Trigger**:
   - Ensure `TcpProxyMonitor/function.json` has the correct timer trigger (every 10 seconds):
     ```json
     {
       "bindings": [
         {
           "name": "Timer",
           "type": "timerTrigger",
           "direction": "in",
           "schedule": "*/10 * * * * *"
         }
       ]
     }
     ```

4. **Create the PowerShell Script**:
   - Create `TcpProxyMonitor/run.ps1` with the following code:
     ```powershell
     using namespace System.Net
     using namespace System.Net.Sockets

     param($Timer)

     # Configuration
     $proxyUrl = $env:ProxyUrl # e.g., "https://<proxy-host>:<port>" or "http://<proxy-host>:<port>"
     $dceEndpoint = $env:DceEndpoint
     $tcpDcrImmutableId = $env:TcpDcrImmutableId
     $tcpTableName = $env:TcpTableName
     $managedIdentityClientId = $env:ManagedIdentityClientId

     # Extract host and port from ProxyUrl
     try {
         $uri = [System.Uri]$proxyUrl
         $host = $uri.Host
         $port = $uri.Port
         if (-not $port) {
             $port = if ($uri.Scheme -eq "https") { 443 } else { 80 }
         }
     } catch {
         Write-Error "Failed to parse ProxyUrl ($proxyUrl): $_"
         return
     }

     # Get OAuth token using user-assigned managed identity with IDENTITY_ENDPOINT and IDENTITY_HEADER
     $identityEndpoint = $env:IDENTITY_ENDPOINT
     $identityHeader = $env:IDENTITY_HEADER
     $resource = "https://monitor.azure.com"
     $tokenUrl = "$identityEndpoint`?api-version=2019-08-01&resource=$resource&client_id=$managedIdentityClientId"
     $headers = @{ "X-IDENTITY-HEADER" = $identityHeader }
     try {
         $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Get -Headers $headers
         $accessToken = $tokenResponse.access_token
     } catch {
         Write-Error "Failed to acquire token using user-assigned managed identity: $_"
         return
     }

     # Perform TCP connection test
     $logs = @()
     $executedAt = (Get-Date).ToUniversalTime().ToString("o")
     try {
         $startTime = Get-Date
         $tcpClient = New-Object System.Net.Sockets.TcpClient
         $connectionTask = $tcpClient.ConnectAsync($host, $port)
         $timeout = 5000 # Timeout in milliseconds
         if ($connectionTask.Wait($timeout)) {
             $responseTimeMs = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 2)
             $tcpStatus = "Up"
         } else {
             $responseTimeMs = 0
             $tcpStatus = "Down"
             Write-Error "TCP connection timed out after $timeout ms"
         }
     } catch {
         $responseTimeMs = 0
         $tcpStatus = "Down"
         Write-Error "TCP connection failed: $_"
     } finally {
         $tcpClient.Close()
         $tcpClient.Dispose()
     }

     $logs += [PSCustomObject]@{
         Timestamp      = (Get-Date).ToUniversalTime().ToString("o")
         Host           = $host
         Port           = $port
         TcpStatus      = $tcpStatus
         ResponseTimeMs = $responseTimeMs
         ExecutedAt     = $executedAt
     }

     # Send logs to Log Analytics
     $headers = @{
         "Authorization" = "Bearer $accessToken"
         "Content-Type"  = "application/json"
     }
     $body = $logs | ConvertTo-Json
     $uri = "$dceEndpoint/dataCollectionRules/$tcpDcrImmutableId/streams/Custom-$tcpTableName`?api-version=2023-01-01"
     try {
         Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
     } catch {
         Write-Error "Failed to send logs to Log Analytics: $_"
     }
     ```

### Step 4: Deploy the TCP Monitoring Function
1. **Deploy the Function**:
   - From your project directory (`ProxyMonitorFunction`), deploy the updated Function App, which includes both `ProxyMonitor` (HTTP) and `TcpProxyMonitor` (TCP) functions:
     ```bash
     func azure functionapp publish ProxyMonitorFunctionApp
     ```
   - Verify deployment in the Azure portal under **Functions**, where both `ProxyMonitor` and `TcpProxyMonitor` should appear.

2. **Verify Function Execution**:
   - Go to **Functions** > **TcpProxyMonitor** > **Monitor**.
   - Check that the function runs every 10 seconds and review logs for errors in TCP connections or log ingestion.

### Step 5: Verify Logs in Log Analytics
1. **Query TCP Logs**:
   - In the Log Analytics workspace (`ProxyMonitorWorkspace`), go to **Logs**.
   - Run a KQL query to verify TCP monitoring data:
     ```kql
     TcpProxyMonitorLogs_CL
     | where TimeGenerated > ago(1h)
     | project Timestamp, Host, Port, TcpStatus, ResponseTimeMs, ExecutedAt
     | order by Timestamp desc
     ```
   - Verify metrics: `Timestamp`, `Host`, `Port`, `TcpStatus` (`Up` or `Down`), `ResponseTimeMs`, `ExecutedAt`.

2. **Query HTTP Logs** (to ensure existing function is unaffected):
   - Run:
     ```kql
     ProxyMonitorLogs_CL
     | where TimeGenerated > ago(1h)
     | project Timestamp, Url, HttpResponseCode, ResponseTimeMs, ProxyStatus, ExecutedAt
     | order by Timestamp desc
     ```

3. **Set Up Alerts (Optional)**:
   - In the Log Analytics workspace, go to **Alerts** > **Create** > **Alert rule**.
   - Define a condition for TCP monitoring, e.g.:
     ```kql
     TcpProxyMonitorLogs_CL | where TcpStatus == "Down"
     ```
   - Set actions (e.g., email or webhook) and save.
   - Repeat for HTTP monitoring if not already set up:
     ```kql
     ProxyMonitorLogs_CL | where ProxyStatus == "Down"
     ```

### Step 6: Enable Monitoring with Application Insights
- **Reuse Existing Application Insights**:
  - The Function App is already configured with Application Insights (from the HTTP function setup).
  - Ensure **FunctionAppLogs** are sent to the Log Analytics workspace via **Monitoring** > **Diagnostic settings**.

### Step 7: Optimize and Secure
1. **Optimize Performance**:
   - Monitor Log Analytics ingestion costs for both `ProxyMonitorLogs_CL` and `TcpProxyMonitorLogs_CL`. Adjust the timer schedule (e.g., every 30 seconds) or use sampling if costs are high.
   - Use the **Basic** table plan for `TcpProxyMonitorLogs_CL` if advanced analytics aren’t needed.

2. **Secure the Function**:
   - The user-assigned managed identity eliminates stored credentials.
   - Ensure the ASE allows outbound traffic to the proxy’s host/port (for both HTTP and TCP functions) and the DCE endpoint (`https://<dce-name>.<region>.ingest.monitor.azure.com`).
   - Restrict ASE network access using Virtual Network integration or private endpoints if needed.

3. **Handle Failures**:
   - The TCP function includes error handling for TCP connections and log ingestion. Add retry logic for failed connections if needed.
   - Monitor Application Insights for failures or timeouts.

## Notes
- **Managed Identity**: Both functions use the same **user-assigned managed identity** (`ProxyMonitorIdentity`) for authentication with the Logs Ingestion API, leveraging `IDENTITY_ENDPOINT` and `IDENTITY_HEADER`.
- **RBAC Permissions**: The `ProxyMonitorIdentity` must have the **Monitoring Metrics Publisher** role on both `ProxyMonitorDCR` (HTTP) and `TcpProxyMonitorDCR` (TCP).
- **Proxy Configuration**:
  - **HTTP Function**: Uses `System.Net.Http.HttpClient` to test HTTP connectivity through the proxy, validating the server certificate with CA and root CA certificates from the **LocalMachine** store.
  - **TCP Function**: Uses `System.Net.Sockets.TcpClient` to test TCP connectivity to the proxy’s host and port without certificate validation.
- **Proxy Status**:
  - HTTP: `ProxyStatus` is `Up` for HTTP 200 responses, `Down` otherwise.
  - TCP: `TcpStatus` is `Up` for successful connections, `Down` otherwise.
- **ExecutedAt**: Captures the start time of each request for both functions.
- **Latency**: Log data may take 5–10 minutes to appear in Log Analytics.
- **Costs**: Monitor ingestion costs for both tables in the Azure portal.
- **ASE Considerations**: Ensure the ASE allows outbound traffic to the proxy’s host/port, public URLs (for HTTP), and DCE endpoint. Check network security groups (NSGs) or firewall settings.
- **Certificates**: The TCP function does not use certificates. The HTTP function uses CA and root CA certificates in the **LocalMachine** store for server certificate validation.
- **References**: Based on Microsoft Learn documentation for Azure Functions, Azure Monitor, managed identities, and TCP connectivity.

## Troubleshooting
- **TCP Logs Not Appearing**:
  - Verify the DCE, DCR (`TcpProxyMonitorDCR`), and table (`TcpProxyMonitorLogs_CL`) configuration in the Azure portal’s **JSON View**.
  - Ensure `TcpDcrImmutableId` and `TcpTableName` are correctly set in the Function App’s application settings.
  - Check that `ProxyMonitorIdentity` has the **Monitoring Metrics Publisher** role on `TcpProxyMonitorDCR`.
- **HTTP Logs Not Appearing** (to ensure existing function is unaffected):
  - Verify `DcrImmutableId` and `TableName` settings.
  - Check `ProxyMonitorIdentity` permissions on `ProxyMonitorDCR`.
- **Token Acquisition Errors**:
  - Check Application Insights logs for errors in the `Invoke-RestMethod` call to `$identityEndpoint`.
  - Ensure `ManagedIdentityClientId` matches the Client ID of `ProxyMonitorIdentity`.
  - Confirm that `IDENTITY_ENDPOINT` and `IDENTITY_HEADER` are available (**Settings** > **Configuration** > **Environment variables**).
- **TCP Connection Errors**:
  - Check Application Insights logs for errors like “TCP connection failed” or “TCP connection timed out.”
  - Verify the `ProxyUrl` is correct (e.g., `https://<proxy-host>:<port>` or `http://<proxy-host>:<port>`).
  - Ensure the ASE’s NSGs or firewall allow outbound traffic to the proxy’s host and port.
- **HTTP Connection Errors** (to ensure existing function is unaffected):
  - Check logs for certificate-related errors (e.g., “CA certificate with thumbprint not found in LocalMachine certificate store”).
  - Verify `CaCertThumbprint`, `RootCaCertThumbprint`, and `WEBSITE_LOAD_CERTIFICATES` settings.
  - Ensure the proxy’s server certificate is valid and issued by the uploaded CA or root CA.
- **Network Issues**:
  - Ensure the ASE allows outbound traffic to the proxy’s host/port, public URLs (for HTTP), and DCE endpoint.
  - If the ASE is isolated, configure Virtual Network integration or private endpoints.

For further assistance, refer to the [Azure Functions documentation](https://learn.microsoft.com/azure/azure-functions/) or contact your Azure administrator.