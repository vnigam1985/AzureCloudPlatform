# Proxy Monitor Azure Function

This project deploys a PowerShell-based Azure Function in an Azure App Service Environment (ASE) to monitor a proxy by accessing five public URLs every 10 seconds. It logs metrics (Timestamp, Url, HttpResponseCode, ResponseTimeMs, ProxyStatus, ExecutedAt) to a custom Log Analytics workspace table using a system-assigned managed identity for authentication and the Logs Ingestion API.

## Prerequisites
- **Azure Subscription**: With access to an App Service Environment.
- **PowerShell**: Version 7.2 or later installed locally.
- **Azure CLI** or **Azure PowerShell module**: For deployment and configuration.
- **Azure Functions Core Tools**: Version 4.x for local development.
- **Log Analytics Workspace**: Created in Azure.
- **URLs to Monitor**: Five public URLs (e.g., `https://example.com`).
- **Basic Familiarity**: With Azure Functions, PowerShell, Azure Monitor, and managed identities.

## Setup Instructions

### Step 1: Set Up Log Analytics Workspace
1. **Create a Log Analytics Workspace**:
   - In the Azure portal, go to **Create a resource** > **Log Analytics Workspace**.
   - Select your subscription, resource group, and region.
   - Name the workspace (e.g., `ProxyMonitorWorkspace`) and create it.
   - Note the **Workspace ID** and **Workspace Resource ID** from **Overview** > **Settings** > **Agents** (e.g., `/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.OperationalInsights/workspaces/ProxyMonitorWorkspace`).

2. **Create a Data Collection Endpoint (DCE)**:
   - Go to **Monitor** > **Data Collection Endpoints** > **Create**.
   - Name the DCE (e.g., `ProxyMonitorDCE`), select the same region as your Log Analytics workspace, and create it.
   - Note the **Logs ingestion URI** (e.g., `https://<dce-name>.<region>.ingest.monitor.azure.com`) and **DCE Resource ID** from the DCE properties (e.g., `/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Insights/dataCollectionEndpoints/ProxyMonitorDCE`).

3. **Create a Data Collection Rule (DCR)**:
   - The DCR must be configured for the Logs Ingestion API to support custom logs sent via HTTP. If the **Logs Ingestion** data source is unavailable in the Azure portal, use one of the following methods to create the DCR.

   **Option 1: Create DCR via ARM Template**:
   - Save the following ARM template as `dcr-template.json`:
     ```json
     {
       "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
       "contentVersion": "1.0.0.0",
       "parameters": {
         "dcrName": { "type": "string", "defaultValue": "ProxyMonitorDCR" },
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
               "Custom-ProxyMonitorLogs_CL": {
                 "columns": [
                   { "name": "Timestamp", "type": "datetime" },
                   { "name": "Url", "type": "string" },
                   { "name": "HttpResponseCode", "type": "int" },
                   { "name": "ResponseTimeMs", "type": "double" },
                   { "name": "ProxyStatus", "type": "string" },
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
                 "streams": ["Custom-ProxyMonitorLogs_CL"],
                 "destinations": ["ProxyMonitorWorkspace"],
                 "outputStream": "Custom-ProxyMonitorLogs_CL"
               }
             ]
           }
         }
       ]
     }
     ```
   - Deploy the ARM template using Azure CLI:
     ```bash
     az deployment group create --resource-group <your-resource-group> --template-file dcr-template.json --parameters dcrName=ProxyMonitorDCR location=<your-region> workspaceResourceId=<your-workspace-resource-id> dceResourceId=<your-dce-resource-id>
     ```
     - Replace `<your-resource-group>`, `<your-region>`, `<your-workspace-resource-id>`, and `<your-dce-resource-id>` with your values.
   - Note the **DCR Immutable ID** from the DCR’s **JSON View** under `immutableId` in the Azure portal after deployment.

   **Option 2: Create DCR via PowerShell**:
   - Use the Azure PowerShell module to create the DCR:
     ```powershell
     # Install Azure PowerShell module if not already installed
     Install-Module -Name Az -AllowClobber -Scope CurrentUser

     # Connect to Azure
     Connect-AzAccount

     # Define variables
     $resourceGroup = "<your-resource-group>"
     $dcrName = "ProxyMonitorDCR"
     $location = "<your-region>"
     $workspaceResourceId = "<your-workspace-resource-id>"
     $dceResourceId = "<your-dce-resource-id>"

     # Define DCR configuration
     $dcrProperties = @{
         dataCollectionEndpointId = $dceResourceId
         streamDeclarations = @{
             "Custom-ProxyMonitorLogs_CL" = @{
                 columns = @(
                     @{ name = "Timestamp"; type = "datetime" },
                     @{ name = "Url"; type = "string" },
                     @{ name = "HttpResponseCode"; type = "int" },
                     @{ name = "ResponseTimeMs"; type = "double" },
                     @{ name = "ProxyStatus"; type = "string" },
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
                 streams = @("Custom-ProxyMonitorLogs_CL")
                 destinations = @("ProxyMonitorWorkspace")
                 outputStream = "Custom-ProxyMonitorLogs_CL"
             }
         )
     }

     # Create the DCR
     New-AzResource -ResourceGroupName $resourceGroup -Location $location -ResourceName $dcrName -ResourceType "Microsoft.Insights/dataCollectionRules" -Properties $dcrProperties -Force

     # Retrieve the DCR Immutable ID
     $dcr = Get-AzResource -ResourceGroupName $resourceGroup -ResourceName $dcrName -ResourceType "Microsoft.Insights/dataCollectionRules"
     $immutableId = $dcr.Properties.immutableId
     Write-Output "DCR Immutable ID: $immutableId"
     ```
     - Replace `<your-resource-group>`, `<your-region>`, `<your-workspace-resource-id>`, and `<your-dce-resource-id>` with your values.
     - Run the script in PowerShell after connecting to your Azure account.
     - Note the **DCR Immutable ID** from the script output or the DCR’s **JSON View** in the Azure portal.

### Step 2: Create the PowerShell Function
1. **Set Up Local Development Environment**:
   - Install Azure Functions Core Tools:
     ```bash
     npm install --pan azure-functions-core-tools@4 --unsafe-perm true
     ```
   - Create a new PowerShell function app:
     ```bash
     func init ProxyMonitorFunction --powershell
     cd ProxyMonitorFunction
     ```
   - Create a timer-triggered function (runs every 10 seconds):
     ```bash
     func new --name ProxyMonitor --template "TimerTrigger" --schedule "*/10 * * * * *"
     ```

2. **Configure the Function**:
   - Ensure `ProxyMonitor/function.json` has the correct timer trigger:
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
   - Create `ProxyMonitor/run.ps1` with the following code:
     ```powershell
     using namespace System.Net

     param($Timer)

     # Configuration
     $urls = @(
         "https://example.com",
         "https://example.org",
         "https://test.com",
         "https://sample.com",
         "https://demo.com"
     )
     $dceEndpoint = "<Your-DCE-Logs-Ingestion-URI>"
     $dcrImmutableId = "<Your-DCR-Immutable-ID>"
     $tableName = "ProxyMonitorLogs_CL"

     # Get OAuth token using managed identity
     $resource = "https://monitor.azure.com"
     $tokenUrl = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$resource"
     $headers = @{ "Metadata" = "true" }
     try {
         $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Get -Headers $headers
         $accessToken = $tokenResponse.access_token
     } catch {
         Write-Error "Failed to acquire token: $_"
         return
     }

     # Prepare logs
     $logs = @()
     foreach ($url in $urls) {
         $executedAt = (Get-Date).ToUniversalTime().ToString("o")
         try {
             $startTime = Get-Date
             $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 10
             $responseTimeMs = [math]::Round(((Get-Date) - $startTime).TotalMilliseconds, 2)
             $proxyStatus = ($response.StatusCode -eq 200) ? "Up" : "Down"
             $logs += [PSCustomObject]@{
                 Timestamp        = (Get-Date).ToUniversalTime().ToString("o")
                 Url              = $url
                 HttpResponseCode = [int]$response.StatusCode
                 ResponseTimeMs   = $responseTimeMs
                 ProxyStatus      = $proxyStatus
                 ExecutedAt       = $executedAt
             }
         } catch {
             $logs += [PSCustomObject]@{
                 Timestamp        = (Get-Date).ToUniversalTime().ToString("o")
                 Url              = $url
                 HttpResponseCode = [int]$_.Exception.Response.StatusCode
                 ResponseTimeMs   = 0
                 ProxyStatus      = "Down"
                 ExecutedAt       = $executedAt
             }
         }
     }

     # Send logs to Log Analytics
     $headers = @{
         "Authorization" = "Bearer $accessToken"
         "Content-Type"  = "application/json"
     }
     $body = $logs | ConvertTo-Json
     $uri = "$dceEndpoint/dataCollectionRules/$dcrImmutableId/streams/Custom-$tableName`?api-version=2023-01-01"
     try {
         Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
     } catch {
         Write-Error "Failed to send logs to Log Analytics: $_"
     }
     ```
   - **Replace placeholders**:
     - `<Your-DCE-Logs-Ingestion-URI>`: From the DCE properties (e.g., `https://<dce-name>.<region>.ingest.monitor.azure.com`).
     - `<Your-DCR-Immutable-ID>`: From the DCR’s **JSON View** or PowerShell script output.

3. **Test Locally** (optional, limited by managed identity):
   - Run the function locally to test HTTP requests and JSON payload:
     ```bash
     func start
     ```
   - Note: Managed identity testing requires Azure; mock the token response or skip Log Analytics calls for local testing.

### Step 3: Deploy to Azure App Service Environment
1. **Create a Function App in ASE**:
   - In the Azure portal, go to **Create a resource** > **Function App**.
   - Select your subscription and resource group.
   - Name the app (e.g., `ProxyMonitorFunctionApp`).
   - Choose **PowerShell Core** as the runtime stack (latest version, e.g., 7.4).
   - Select your **App Service Environment** as the hosting option.
   - Choose a region matching your Log Analytics workspace and DCE.
   - Select an App Service plan within the ASE (e.g., Isolated plan).
   - Create the Function App.

2. **Enable System-Assigned Managed Identity**:
   - In the Function App, go to **Settings** > **Identity**.
   - Under **System assigned**, toggle **Status** to **On** and save.
   - Note the **Object ID** of the managed identity.

3. **Grant Permissions to the Managed Identity**:
   - Navigate to the **Data Collection Rule** (`ProxyMonitorDCR`) in the Azure portal.
   - Go to **Access Control (IAM)** > **Add role assignment**.
   - Select the **Monitoring Metrics Publisher** role.
   - Assign access to **Managed identity**, select **Function App**, and choose `ProxyMonitorFunctionApp`.
   - Save the role assignment.

4. **Configure Application Settings**:
   - In the Function App, go to **Settings** > **Configuration** > **Application settings**.
   - Add:
     - `DceEndpoint`: Your DCE logs ingestion URI (e.g., `https://<dce-name>.<region>.ingest.monitor.azure.com`).
     - `DcrImmutableId`: Your DCR immutable ID.
     - `TableName`: `ProxyMonitorLogs_CL`.
   - Update `run.ps1` to use these settings:
     ```powershell
     $dceEndpoint = $env:DceEndpoint
     $dcrImmutableId = $env:DcrImmutableId
     $tableName = $env:TableName
     ```
   - Save the settings.

5. **Deploy the Function**:
   - From the project directory, deploy to Azure:
     ```bash
     func azure functionapp publish ProxyMonitorFunctionApp
     ```
   - Verify deployment in the Azure portal under **Functions**.

### Step 4: Enable Monitoring with Application Insights
1. **Enable Application Insights**:
   - In the Function App, go to **Settings** > **Application Insights**.
   - Enable Application Insights and link to your Log Analytics workspace, or create a new Application Insights resource and note the **Connection String**.

2. **Configure Diagnostic Settings**:
   - In the Function App, go to **Monitoring** > **Diagnostic settings** > **Add diagnostic setting**.
   - Select **FunctionAppLogs** and send to your Log Analytics workspace.

### Step 5: Verify and Monitor
1. **Check Function Execution**:
   - In the Azure portal, go to the Function App > **Functions** > **ProxyMonitor** > **Monitor**.
   - Verify the function runs every 10 seconds and check for errors.

2. **Query Logs in Log Analytics**:
   - In the Log Analytics workspace, go to **Logs**.
   - Run a KQL query to verify data:
     ```kql
     ProxyMonitorLogs_CL
     | where TimeGenerated > ago(1h)
     | project Timestamp, Url, HttpResponseCode, ResponseTimeMs, ProxyStatus, ExecutedAt
     | order by Timestamp desc
     ```
   - Verify all metrics appear: `Timestamp`, `Url`, `HttpResponseCode`, `ResponseTimeMs`, `ProxyStatus` (`Up` or `Down`), `ExecutedAt`.

3. **Set Up Alerts (Optional)**:
   - In the Log Analytics workspace, go to **Alerts** > **Create** > **Alert rule**.
   - Define a condition, e.g.:
     ```kql
     ProxyMonitorLogs_CL | where ProxyStatus == "Down"
     ```
   - Set actions (e.g., email or webhook) and save.

### Step 6: Optimize and Secure
1. **Optimize Performance**:
   - Monitor Log Analytics ingestion costs, as logging every 10 seconds can accumulate data. Adjust frequency (e.g., every 30 seconds) or use sampling if needed.
   - Use the **Basic** table plan for cost savings if advanced analytics aren’t required.

2. **Secure the Function**:
   - The managed identity eliminates stored credentials.
   - Restrict ASE network access using Virtual Network integration or private endpoints.

3. **Handle Failures**:
   - The script includes error handling for token acquisition and log ingestion. Add retry logic for failed requests if needed.
   - Monitor Application Insights for failures or timeouts.

## Notes
- **DCR Configuration**: The DCR is configured for the Logs Ingestion API using an ARM template or PowerShell, as the **Logs Ingestion** data source may not be available in the Azure portal.
- **Proxy Status**: Set to `Up` for HTTP 200 responses, `Down` otherwise. Adjust logic if other 2xx codes are valid.
- **ExecutedAt**: Captures the start time of each request.
- **Latency**: Log data may take 5–10 minutes to appear in Log Analytics.
- **Costs**: Monitor ingestion costs in the Azure portal.
- **ASE Considerations**: Ensure the ASE allows outbound internet access to URLs and the DCE endpoint.
- **References**: Based on Microsoft Learn documentation for Azure Functions, Log Analytics, and managed identities.

## Troubleshooting
- **Logs not appearing**: Verify DCE, DCR, and managed identity permissions. Ensure the DCR uses the `Custom-ProxyMonitorLogs_CL` stream.
- **Function errors**: Check Application Insights for token or ingestion issues.
- **Network issues**: Ensure the ASE allows outbound traffic to URLs and the DCE endpoint.
- **DCR creation issues**: If the ARM template or PowerShell script fails, verify the `workspaceResourceId` and `dceResourceId` values and check for regional restrictions.

For further assistance, refer to the [Azure Functions documentation](https://learn.microsoft.com/azure/azure-functions/) or contact your Azure administrator.