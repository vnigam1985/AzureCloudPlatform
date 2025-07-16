# Proxy Monitor Azure Function

This project deploys a PowerShell-based Azure Function in an Azure App Service Environment (ASE) to monitor a proxy by accessing five public URLs every 10 seconds through a specified proxy URL, which requires CA and root CA certificates in `.pem` format for server certificate validation. It logs metrics (Timestamp, Url, HttpResponseCode, ResponseTimeMs, ProxyStatus, ExecutedAt) to a custom Log Analytics workspace table using a user-assigned managed identity for authentication and the Logs Ingestion API.

## Prerequisites
- **Azure Subscription**: With access to an App Service Environment.
- **PowerShell**: Version 7.2 or later installed locally.
- **Azure CLI** or **Azure PowerShell module**: For deployment and configuration.
- **Azure Functions Core Tools**: Version 4.x for local development.
- **Log Analytics Workspace**: Created in Azure.
- **URLs to Monitor**: Five public URLs (e.g., `https://example.com`).
- **Proxy URL**: The URL of the proxy to test (e.g., `https://<proxy-host>:<port>`).
- **Proxy Certificates**:
  - CA certificate (`ca-cert.pem`): Intermediate CA certificate for the proxy’s server certificate.
  - Root CA certificate (`rootca-cert.pem`): Root CA certificate for the proxy’s server certificate.
- **OpenSSL** (optional): For converting `.pem` to `.cer` if needed.
- **Basic Familiarity**: With Azure Functions, PowerShell, Azure Monitor, managed identities, and certificate management.

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

### Step 3: Upload Proxy Certificates
1. **Convert .pem to .cer (if needed)**:
   - Azure Function Apps may require certificates in `.cer` (DER) format. If uploading `.pem` files fails, convert them to `.cer` using OpenSSL or PowerShell.
   - **Using OpenSSL**:
     ```bash
     # Install OpenSSL if needed (e.g., choco install openssl on Windows)
     openssl x509 -in ca-cert.pem -out ca-cert.cer -outform DER
     openssl x509 -in rootca-cert.pem -out rootca-cert.cer -outform DER
     ```
   - **Using PowerShell**:
     ```powershell
     # Convert ca-cert.pem to ca-cert.cer
     $pemContent = Get-Content -Path "ca-cert.pem" -Raw
     $certBase64 = ($pemContent -replace "-----BEGIN CERTIFICATE-----", "" -replace "-----END CERTIFICATE-----", "" -replace "\s", "")
     $certBytes = [System.Convert]::FromBase64String($certBase64)
     [System.IO.File]::WriteAllBytes("ca-cert.cer", $certBytes)

     # Convert rootca-cert.pem to rootca-cert.cer
     $pemContent = Get-Content -Path "rootca-cert.pem" -Raw
     $certBase64 = ($pemContent -replace "-----BEGIN CERTIFICATE-----", "" -replace "-----END CERTIFICATE-----", "" -replace "\s", "")
     $certBytes = [System.Convert]::FromBase64String($certBase64)
     [System.IO.File]::WriteAllBytes("rootca-cert.cer", $certBytes)
     ```
   - Use the `.cer` files for uploading if conversion is needed. If `.pem` files are accepted, skip this step.

2. **Upload CA Certificate**:
   - Navigate to your Function App (`ProxyMonitorFunctionApp`) > **Settings** > **Certificates**.
   - Under **Certificates**, click **Upload certificate**.
   - Select `ca-cert.pem` (or `ca-cert.cer` if converted) and click **Upload**. No password is required.
   - Note the certificate’s **Thumbprint** (visible in the certificate list).

3. **Upload Root CA Certificate**:
   - Repeat for `rootca-cert.pem` (or `rootca-cert.cer`).
   - Select the file, click **Upload**, and note the **Thumbprint**.

4. **Configure Certificate Loading**:
   - Go to **Settings** > **Configuration** > **Application settings**.
   - Add:
     - `WEBSITE_LOAD_CERTIFICATES`: The thumbprints of the CA and root CA certificates, comma-separated (e.g., `1234567890ABCDEF1234567890ABCDEF12345678,ABCDEF1234567890ABCDEF1234567890ABCDEF12`).
     - `CaCertThumbprint`: The thumbprint of the CA certificate (e.g., `1234567890ABCDEF1234567890ABCDEF12345678`).
     - `RootCaCertThumbprint`: The thumbprint of the root CA certificate (e.g., `ABCDEF1234567890ABCDEF1234567890ABCDEF12`).
   - Save the settings.

### Step 4: Create the PowerShell Function
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
     using namespace System.Net.Http
     using namespace System.Security.Cryptography.X509Certificates

     param($Timer)

     # Configuration
     $urls = @(
         "https://example.com",
         "https://example.org",
         "https://test.com",
         "https://sample.com",
         "https://demo.com"
     )
     $dceEndpoint = $env:DceEndpoint
     $dcrImmutableId = $env:DcrImmutableId
     $tableName = $env:TableName
     $managedIdentityClientId = $env:ManagedIdentityClientId
     $proxyUrl = $env:ProxyUrl # e.g., "https://<proxy-host>:<port>"
     $caCertThumbprint = $env:CaCertThumbprint
     $rootCaCertThumbprint = $env:RootCaCertThumbprint

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

     # Load CA and root CA certificates from certificate store
     try {
         $certStore = New-Object X509Store -ArgumentList "My", "CurrentUser"
         $certStore.Open("ReadOnly")
         $caCert = $certStore.Certificates | Where-Object { $_.Thumbprint -eq $caCertThumbprint }
         $rootCaCert = $certStore.Certificates | Where-Object { $_.Thumbprint -eq $rootCaCertThumbprint }
         if (-not $caCert) {
             Write-Error "CA certificate with thumbprint $caCertThumbprint not found in certificate store"
             return
         }
         if (-not $rootCaCert) {
             Write-Error "Root CA certificate with thumbprint $rootCaCertThumbprint not found in certificate store"
             return
         }
     } catch {
         Write-Error "Failed to load certificates: $_"
         return
     } finally {
         $certStore.Close()
     }

     # Create custom certificate validation callback
     $certChain = New-Object X509Chain
     $certChain.ChainPolicy.ExtraStore.Add($caCert) | Out-Null
     $certChain.ChainPolicy.ExtraStore.Add($rootCaCert) | Out-Null
     $certChain.ChainPolicy.VerificationFlags = [X509VerificationFlags]::NoFlag
     $certChain.ChainPolicy.RevocationMode = [X509RevocationMode]::NoCheck

     $handler = New-Object HttpClientHandler
     $handler.Proxy = New-Object System.Net.WebProxy -ArgumentList $proxyUrl
     $handler.ServerCertificateCustomValidationCallback = {
         param($request, $certificate, $chain, $sslPolicyErrors)
         if ($sslPolicyErrors -eq [System.Net.Security.SslPolicyErrors]::None) {
             return $true
         }
         $chainElement = New-Object X509ChainElement -ArgumentList $certificate
         $status = $certChain.Build($chainElement.Certificate)
         return $status
     }
     $httpClient = New-Object HttpClient -ArgumentList $handler

     # Prepare logs
     $logs = @()
     foreach ($url in $urls) {
         $executedAt = (Get-Date).ToUniversalTime().ToString("o")
         try {
             $startTime = Get-Date
             $response = $httpClient.GetAsync($url).Result
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
             $statusCode = if ($_.Exception.InnerException.Response) { [int]$_.Exception.InnerException.Response.StatusCode } else { 0 }
             $logs += [PSCustomObject]@{
                 Timestamp        = (Get-Date).ToUniversalTime().ToString("o")
                 Url              = $url
                 HttpResponseCode = $statusCode
                 ResponseTimeMs   = 0
                 ProxyStatus      = "Down"
                 ExecutedAt       = $executedAt
             }
         }
     }

     # Dispose of HttpClient
     $httpClient.Dispose()

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

3. **Test Locally** (optional, limited by managed identity and certificates):
   - Run the function locally to test HTTP requests and JSON payload:
     ```bash
     func start
     ```
   - Note: Managed identity testing (`IDENTITY_ENDPOINT` and `IDENTITY_HEADER`) and certificate loading require Azure, as they depend on the Function App’s certificate store and environment variables. Mock the token response and certificate validation for local testing, or focus on testing the proxy logic.

### Step 5: Deploy to Azure App Service Environment
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
     - `ProxyUrl`: The URL of the proxy to test (e.g., `https://<proxy-host>:<port>`).
     - `CaCertThumbprint`: The thumbprint of the CA certificate (e.g., `1234567890ABCDEF1234567890ABCDEF12345678`).
     - `RootCaCertThumbprint`: The thumbprint of the root CA certificate (e.g., `ABCDEF1234567890ABCDEF1234567890ABCDEF12`).
     - `WEBSITE_LOAD_CERTIFICATES`: The thumbprints of the CA and root CA certificates, comma-separated (e.g., `1234567890ABCDEF1234567890ABCDEF12345678,ABCDEF1234567890ABCDEF1234567890ABCDEF12`).
   - Save the settings.

5. **Deploy the Function**:
   - From the project directory, deploy to Azure:
     ```bash
     func azure functionapp publish ProxyMonitorFunctionApp
     ```
   - Verify deployment in the Azure portal under **Functions**.

### Step 6: Enable Monitoring with Application Insights
1. **Enable Application Insights**:
   - In the Function App, go to **Settings** > **Application Insights**.
   - Enable Application Insights and link to your Log Analytics workspace, or create a new Application Insights resource and note the **Connection String**.

2. **Configure Diagnostic Settings**:
   - In the Function App, go to **Monitoring** > **Diagnostic settings** > **Add diagnostic setting**.
   - Select **FunctionAppLogs** and send to your Log Analytics workspace.

### Step 7: Verify and Monitor
1. **Check Function Execution**:
   - In the Azure portal, go to the Function App > **Functions** > **ProxyMonitor** > **Monitor**.
   - Verify the function runs every 10 seconds and check for errors, especially in certificate loading or HTTP requests.

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

### Step 8: Optimize and Secure
1. **Optimize Performance**:
   - Monitor Log Analytics ingestion costs, as logging every 10 seconds can accumulate data. Adjust frequency (e.g., every 30 seconds) or use sampling if needed.
   - Use the **Basic** table plan for cost savings if advanced analytics aren’t required.

2. **Secure the Function**:
   - The user-assigned managed identity eliminates stored credentials.
   - Restrict ASE network access using Virtual Network integration or private endpoints.
   - Ensure the CA and root CA certificates are securely stored and not exposed.

3. **Handle Failures**:
   - The script includes error handling for certificate loading, HTTP requests, and log ingestion. Add retry logic for failed requests if needed.
   - Monitor Application Insights for failures or timeouts.

## Notes
- **Managed Identity**: The PowerShell function uses a **user-assigned managed identity** (`ProxyMonitorIdentity`) to authenticate with the Logs Ingestion API. The token is acquired using `IDENTITY_ENDPOINT` and `IDENTITY_HEADER` environment variables.
- **RBAC Permissions**: The **Monitoring Metrics Publisher** role on the DCR (`ProxyMonitorDCR`) is required for the user-assigned managed identity to send logs.
- **Proxy Configuration**: The function routes requests through the proxy URL specified in the `ProxyUrl` setting. The CA and root CA certificates (`ca-cert.pem` and `rootca-cert.pem`) validate the proxy’s server certificate.
- **Proxy Status**: Set to `Up` for HTTP 200 responses, `Down` otherwise. Adjust logic if other 2xx codes are valid.
- **ExecutedAt**: Captures the start time of each request.
- **Latency**: Log data may take 5–10 minutes to appear in Log Analytics.
- **Costs**: Monitor ingestion costs in the Azure portal.
- **ASE Considerations**: Ensure the ASE allows outbound internet access to the proxy URL, the five public URLs, and the DCE endpoint.
- **References**: Based on Microsoft Learn documentation for Azure Functions, Log Analytics, managed identities, and certificate management.

## Troubleshooting
- **Logs not appearing**:
  - Verify the DCE, DCR, and user-assigned managed identity permissions.
  - Ensure the DCR uses the `Custom-ProxyMonitorLogs_CL` stream.
  - Check that the `ManagedIdentityClientId` matches the Client ID of `ProxyMonitorIdentity`.
- **Token acquisition errors**:
  - Check Application Insights logs for errors in the `Invoke-RestMethod` call to `$identityEndpoint`.
  - Ensure the user-assigned managed identity is assigned to the Function App and has the **Monitoring Metrics Publisher** role on the DCR.
  - Verify the `ManagedIdentityClientId` is correctly set in the application settings.
  - Confirm that `IDENTITY_ENDPOINT` and `IDENTITY_HEADER` are available in the Function App’s environment (**Settings** > **Configuration** > **Environment variables**).
- **Certificate errors**:
  - Check Application Insights logs for errors in certificate loading (e.g., "CA certificate with thumbprint not found").
  - Ensure the `CaCertThumbprint` and `RootCaCertThumbprint` match the uploaded certificates’ thumbprints.
  - Verify the `WEBSITE_LOAD_CERTIFICATES` setting includes both thumbprints.
  - If `.pem` files fail to upload, convert to `.cer` format and retry.
  - If HTTP requests fail with certificate validation errors, ensure the proxy’s server certificate is issued by the CA or root CA and that the certificates are correctly uploaded.
- **Proxy errors**:
  - Check Application Insights logs for errors in `HttpClient` requests.
  - Ensure the `ProxyUrl` is correct and accessible from the ASE.
  - Verify the ASE’s network security groups (NSGs) or firewall allow outbound traffic to the proxy URL.
- **Network issues**: Ensure the ASE allows outbound traffic to the proxy URL, public URLs, and DCE endpoint.
- **DCR issues**: Verify the DCR’s **JSON View** in the Azure portal to confirm the `streamDeclarations` and `dataFlows` are correctly set.

For further assistance, refer to the [Azure Functions documentation](https://learn.microsoft.com/azure/azure-functions/) or contact your Azure administrator.