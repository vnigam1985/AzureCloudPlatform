# Proxy Monitor Azure Function

This project deploys a PowerShell-based Azure Function in an Azure App Service Environment (ASE) to monitor a proxy by accessing five public URLs every 10 seconds. It logs metrics (Timestamp, Url, HttpResponseCode, ResponseTimeMs, ProxyStatus, ExecutedAt) to a custom Log Analytics workspace table using a system-assigned managed identity for authentication.

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
   - Note the **Workspace ID** from **Overview** > **Settings** > **Agents**.

2. **Create a Data Collection Endpoint (DCE)**:
   - Go to **Monitor** > **Data Collection Endpoints** > **Create**.
   - Name the DCE (e.g., `ProxyMonitorDCE`), select the same region as your Log Analytics workspace, and create it.
   - Note the **Logs ingestion URI** from the DCE properties (e.g., `https://<dce-name>.<region>.ingest.monitor.azure.com`).

3. **Create a Custom Log Table and Data Collection Rule (DCR)**:
   - In the Log Analytics workspace, navigate to **Tables** > **Create** > **New custom log (DCR based)**.
   - Name the table `ProxyMonitorLogs_CL` (the `_CL` suffix is added automatically).
   - Create a **Data Collection Rule (DCR)**:
     - Select **Create a new data collection rule**.
     - Specify the subscription, resource group, and name (e.g., `ProxyMonitorDCR`).
     - For **Platform Type**, select **Custom** to support custom logs from the Azure Function.
     - Select the DCE created above (`ProxyMonitorDCE`) and proceed.
   - Upload a sample JSON file to define the schema:
     ```json
     [
       {
         "Timestamp": "2025-07-14T14:00:00Z",
         "Url": "https://example.com",
         "HttpResponseCode": 200,
         "ResponseTimeMs": 150,
         "ProxyStatus": "Up",
         "ExecutedAt": "2025-07-14T14:00:00Z"
       }
     ]
     ```
   - Azure infers the schema with columns: `Timestamp`, `Url`, `HttpResponseCode`, `ResponseTimeMs`, `ProxyStatus`, `ExecutedAt`.
   - Complete the table creation.
   - Note the **DCR Immutable ID** from the DCR’s **JSON View** under `immutableId`.

### Step 2: Create the PowerShell Function
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

     # Get OAuth token using managed identity
     $resource = "https://monitor.azure.com"
     $tokenUrl = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$resource"
     $headers = @{ "Metadata" = "true" }
     try {
         $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Get -Headers $headers
         $accessToken = $tokenResponse.access_token
     } catch