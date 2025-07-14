# Proxy Monitor Azure Function

This project deploys a PowerShell-based Azure Function in an Azure App Service Environment (ASE) to monitor a proxy by accessing five public URLs every 10 seconds through a specified proxy URL. It logs metrics (Timestamp, Url, HttpResponseCode, ResponseTimeMs, ProxyStatus, ExecutedAt) to a custom Log Analytics workspace table using a user-assigned managed identity for authentication and the Logs Ingestion API.

## Prerequisites
- **Azure Subscription**: With access to an App Service Environment.
- **PowerShell**: Version 7.2 or later installed locally.
- **Azure CLI** or **Azure PowerShell module**: For deployment and configuration.
- **Azure Functions Core Tools**: Version 4.x for local development.
- **Log Analytics Workspace**: Created in Azure.
- **URLs to Monitor**: Five public URLs (e.g., `https://example.com`).
- **Proxy URL**: The URL of the proxy to test (e.g., `http://<proxy-host>:<port>`).
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
   - The DCR must be configured for the Logs Ingestion API to support custom logs sent via HTTP. Since the **Logs Ingestion** data source may not be available in the Azure portal, use one of the following methods to create the DCR.

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
     Install-Module -Name Az -AllowClobber -Scope CurrentUser -Force

     # Connect to Azure
     Connect-AzAccount

     # Define variables
     $resourceGroup = "<your-resource-group>" # e.g., "MyResourceGroup"
     $dcrName = "ProxyMonitorDCR"
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
     - Replace `<your-resource-group>`, `<your-region>`, `<your-workspace-resource-id>`, and `<your-dce-resource-id>` with your values.
     - Run the script in PowerShell after connecting to your Azure account.
     - Note the **DCR Immutable ID** from the script output or the DCR’s **JSON View** in the Azure portal.

### Step 2: Create and Configure User-Assigned Managed Identity
1. **Create a User-Assigned Managed Identity**:
   - In the Azure portal, go to **Create a resource** > **Managed Identity** > **User-assigned managed identity**.
   - Select your subscription, resource group, and region (same as the Function App).
   - Name the identity (e.g., `ProxyMonitorIdentity`) and create it.
   - Note the **Client ID** from the identity’s **Overview** page (e.g., `12345678-1234-1234-1234-1234567890ab`).

2. **Assign the User-Assigned Managed Identity to the Function App**:
   - After creating the Function App (see Step 3), go to **Settings** > **Identity** > **User assigned** > **Add**.
   - Select the `ProxyMonitorIdentity` and save.

3. **Grant Permissions to the User-Assigned Managed Identity**:
   - Navigate to the **Data Collection Rule** (`ProxyMonitorDCR`) in the Azure portal under **Monitor** > **Data Collection Rules**.
   - Go to **Access Control (IAM)** > **Add role assignment**.
   - Select the **Monitoring Metrics Publisher** role.
   - Assign access to **Managed identity**, select **User-assigned managed identity**, and choose `ProxyMonitorIdentity`.
   - Save the role assignment.
   - Verify the assignment in **Access Control (IAM)** > **View access** to ensure the managed identity has the **Monitoring Metrics Publisher** role.

### Step 3: Create the PowerShell Function
1. **Set Up Local Development Environment**:
   - Install Azure Functions Core Tools:
     ```bash
     npm install -g azure-functions-core-tools@4 --unsafe-perm true
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
     $managedIdentityClientId = "<Your-User-Assigned-Managed-Identity-Client-ID>"
     $proxyUrl = "<your-proxy-url>" # e.g., "http://<proxy-host>:<port>"

     # Get OAuth token using user-assigned managed identity
     $resource = "https://monitor.azure.com"
     $tokenUrl = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$resource&client_id=$managedIdentityClientId"
     $headers = @{ "Metadata" = "true" }
     try {
         $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Get -Headers $headers
         $accessToken = $tokenResponse.access_token
     } catch {
         Write-Error "Failed to acquire token using user-assigned managed identity: $_"
         return
     }

     # Prepare logs
     $logs = @()
     foreach ($url in $urls) {
         $executedAt = (Get-Date).ToUniversalTime().ToString("o")
         try {
             $startTime = Get-Date
             $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 10 -Proxy $proxyUrl
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
     - `<Your-User-Assigned-Managed-Identity-Client-ID>`: The Client ID of the `ProxyMonitorIdentity` (e.g., `12345678-1234-1234-1234-1234567890ab`).
     - `<your-proxy-url>`: The URL of the proxy to test (e.g., `http://<proxy-host>:<port>`).

3. **Test Locally** (optional, limited by managed identity):
   - Run the function locally to test HTTP requests and JSON payload:
     ```bash
     func start
     ```
   - Note: Managed identity testing requires Azure; mock the token response or skip Log Analytics calls for local testing. You can test the proxy configuration locally by setting `$proxyUrl` to your proxy URL.

### Step 4: Deploy to Azure App Service Environment
1. **Create a Function App in ASE**:
   - In the Azure portal, go to **Create a resource** > **Function App**.
   - Select your subscription and resource group.
   - Name the app (e.g., `ProxyMonitorFunctionApp`).
   - Choose **PowerShell Core** as the runtime stack (latest version, e.g., 7.4).
   - Select your **App Service Environment** as the hosting option.
   - Choose a region matching your Log Analytics workspace and DCE.
   - Select an App Service plan within the ASE (e.g., Isolated plan).
   - Create the Function App.

2. **Assign the User-Assigned Managed Identity**:
   - In the Function App, go to **Settings** > **Identity** > **User assigned** > **Add**.
   - Select the `ProxyMonitorIdentity` and save.
   - Verify the identity is listed under **User assigned** identities.

3. **Grant Permissions to the User-Assigned Managed Identity**:
   - Navigate to the **Data Collection Rule** (`ProxyMonitorDCR`) in the Azure portal under **Monitor** > **Data Collection Rules**.
   - Go to **Access Control (IAM)** > **Add role assignment**.
   - Select the **Monitoring Metrics Publisher** role.
   - Assign access to **Managed identity**, select **User-assigned managed identity**, and choose `ProxyMonitorIdentity`.
   - Save the role assignment.
   - Verify the assignment in **Access Control (IAM)** > **View access** to ensure the managed identity has the **Monitoring Metrics Publisher** role.

4. **Configure Application Settings**:
   - In the Function App, go to **Settings** > **Configuration** > **Application settings**.
   - Add:
     - `DceEndpoint`: Your DCE logs ingestion URI (e.g., `https://<dce-name>.<region>.ingest.monitor.azure.com`).
     - `DcrImmutableId`: Your DCR immutable ID.
     - `TableName`: `ProxyMonitorLogs_CL`.
     - `ManagedIdentityClientId`: The Client ID of the `ProxyMonitorIdentity` (e.g., `12345678-1234-1234-1234-1234567890ab`).
     - `ProxyUrl`: The URL of the proxy to test (e.g., `http://<proxy-host>:<port>`).
   - Update `run.ps1` to use these settings:
     ```powershell
     $dceEndpoint = $env:DceEndpoint
     $dcrImmutableId = $env:DcrImmutableId
     $tableName = $env:TableName
     $managedIdentityClientId = $env:ManagedIdentityClientId
     $proxyUrl = $env:ProxyUrl
     ```
   - Save the settings.

5. **Deploy the Function**:
   - From the project directory, deploy to Azure:
     ```bash
     func azure functionapp publish ProxyMonitorFunctionApp
     ```
   - Verify deployment in the Azure portal under **Functions**.

### Step 5: Enable Monitoring with Application Insights
1. **Enable Application Insights**:
   - In the Function App, go to **Settings** > **Application Insights**.
   - Enable Application Insights and link to your Log Analytics workspace, or create a new Application Insights resource and note the **Connection String**.

2. **Configure Diagnostic Settings**:
   - In the Function App, go to **Monitoring** > **Diagnostic settings** > **Add diagnostic setting**.
   - Select **FunctionAppLogs** and send to your Log Analytics workspace.

### Step 6: Verify and Monitor
1. **Check Function Execution**:
   - In the Azure portal, go to the Function App > **Functions** > **ProxyMonitor** > **Monitor**.
   - Verify the function runs every 10 seconds and check for errors, especially in token acquisition or log ingestion.

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

### Step 7: Optimize and Secure
1. **Optimize Performance**:
   - Monitor Log Analytics ingestion costs, as logging every 10 seconds can accumulate data. Adjust frequency (e.g., every 30 seconds) or use sampling if needed.
   - Use the **Basic** table plan for cost savings if advanced analytics aren’t required.

2. **Secure the Function**:
   - The user-assigned managed identity eliminates stored credentials.
   - Restrict ASE network access using Virtual Network integration or private endpoints.
   - If the proxy requires authentication, add credentials securely via application settings (contact your Azure administrator for guidance).

3. **Handle Failures**:
   - The script includes error handling for token acquisition and log ingestion. Add retry logic for failed requests if needed.
   - Monitor Application Insights for failures or timeouts.

## Notes
- **Managed Identity**: The PowerShell function uses a **user-assigned managed identity** (`ProxyMonitorIdentity`) to authenticate with the Logs Ingestion API. The identity’s Client ID is specified in the application settings (`ManagedIdentityClientId`).
- **RBAC Permissions**: The **Monitoring Metrics Publisher** role on the DCR (`ProxyMonitorDCR`) is required for the user-assigned managed identity to send logs.
- **Proxy Configuration**: The function routes requests through the proxy URL specified in the `ProxyUrl` setting. Ensure the proxy is accessible from the ASE and does not require authentication unless configured.
- **Proxy Status**: Set to `Up` for HTTP 200 responses, `Down` otherwise. Adjust logic if other 2xx codes are valid.
- **ExecutedAt**: Captures the start time of each request.
- **Latency**: Log data may take 5–10 minutes to appear in Log Analytics.
- **Costs**: Monitor ingestion costs in the Azure portal.
- **ASE Considerations**: Ensure the ASE allows outbound internet access to the proxy URL, the five public URLs, and the DCE endpoint.
- **References**: Based on Microsoft Learn documentation for Azure Functions, Log Analytics, and managed identities.

## Troubleshooting
- **Logs not appearing**:
  - Verify the DCE, DCR, and user-assigned managed identity permissions.
  - Ensure the DCR uses the `Custom-ProxyMonitorLogs_CL` stream.
  - Check that the `ManagedIdentityClientId` matches the Client ID of `ProxyMonitorIdentity`.
- **Token acquisition errors**:
  - Check Application Insights logs for errors in the `Invoke-RestMethod` call to `http://169.254.169.254/metadata/identity/oauth2/token`.
  - Ensure the user-assigned managed identity is assigned to the Function App and has the **Monitoring Metrics Publisher** role on the DCR.
  - Verify the `ManagedIdentityClientId` is correctly set in the application settings.
- **Proxy errors**:
  - Check Application Insights logs for errors in `Invoke-WebRequest` calls.
  - Ensure the proxy URL is correct and accessible from the ASE.
  - If the proxy requires authentication, add `-ProxyCredential` to `Invoke-WebRequest` and store credentials securely in application settings.
- **Function errors**: Check Application Insights for token or ingestion issues.
- **Network issues**: Ensure the ASE allows outbound traffic to the proxy URL, public URLs, and DCE endpoint.
- **DCR issues**: Verify the DCR’s **JSON View** in the Azure portal to confirm the `streamDeclarations` and `dataFlows` are correctly set.

For further assistance, refer to the [Azure Functions documentation](https://learn.microsoft.com/azure/azure-functions/) or contact your Azure administrator.