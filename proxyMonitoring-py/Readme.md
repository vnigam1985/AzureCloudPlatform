
# 🚀 Deploy Proxy Monitoring Function App in Azure App Service Environment (ASE)

This guide walks you through deploying a **Python-based Proxy Monitoring Function App** inside an Azure App Service Environment (ASE) to monitor multiple public URLs via a proxy. The function logs HTTP status codes, success/failure, and response time, sending data securely to Log Analytics.

---

## 📝 Prerequisites

✅ Azure Subscription  
✅ Azure CLI or VS Code with Azure Functions extension  
✅ Virtual Network (VNet) with outbound access  
✅ ASE v3 (Internal or External) configured in the VNet  
✅ Log Analytics Workspace (Workspace ID & Shared Key)  
✅ (Optional) Internal Proxy URL accessible from within the VNet  

---

## 🔧 Step 1 — Prepare the Azure Resources

### 1️⃣ Create a Virtual Network (VNet)
- Use Azure Portal or CLI to create a VNet (e.g. `my-vnet`).
- Define an address space (e.g. `10.0.0.0/16`).
- Create a subnet (e.g. `ase-subnet`) for the ASE.

### 2️⃣ Create a Log Analytics Workspace
- Navigate to **Azure Monitor** → **Log Analytics Workspaces**.
- Save the **Workspace ID** and **Primary Key (Shared Key)**.

### 3️⃣ Create an App Service Environment (ASE v3)
- ILB (Internal Load Balancer) or External.
- Deploy it into the VNet (`ase-subnet`).
- Ensure outbound access to:
  - Public URLs to monitor.
  - Azure Log Analytics ingestion endpoint.

---

## 🔧 Step 2 — Prepare the Function Code

### 1️⃣ Structure the Code Locally
Create the following folder structure:

```
ProxyMonitoring/
├── host.json
├── requirements.txt
└── ProxyFunction/
    ├── __init__.py
    └── function.json
```

### 2️⃣ Add Code Files

#### host.json
```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  }
}
```

#### requirements.txt
```
azure-functions
requests
```

#### ProxyFunction/function.json
```json
{
  "bindings": [
    {
      "name": "timer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 * * * * *"
    }
  ]
}
```

#### ProxyFunction/__init__.py
(Add the provided Python script from earlier with `requests` and `send_log_entry()`)

---

## 🔧 Step 3 — Create a Function App in Azure

### 1️⃣ Navigate to the Azure Portal
- Select **Create a resource** → **Function App**.

### 2️⃣ Configure the Function App
- **Subscription**: Choose your subscription.
- **Resource Group**: Select or create one.
- **Name**: e.g. `proxy-monitoring-func`.
- **Publish**: Code.
- **Runtime stack**: Python 3.11 (or latest).
- **Region**: Same as ASE.
- **Hosting**: Choose your ASE v3 (ILB or External).
- **Plan**: Elastic Premium (EP1 recommended).
- **VNet Integration**: Enable and select the VNet/subnet if prompted.

---

## 🔧 Step 4 — Deploy the Function App

### 1️⃣ Use Azure CLI
```bash
cd ProxyMonitoring
func azure functionapp publish <your-function-app-name> --python
```

### 2️⃣ Or Use VS Code
- Open the folder in VS Code.
- Install Azure Functions extension.
- Right-click the function folder → Deploy to Function App.

---

## 🔧 Step 5 — Configure Application Settings

In the Azure Portal → Function App → **Configuration** → **Application Settings**, add:

| Key | Value |
|-----|-------|
| `LOG_ANALYTICS_WORKSPACE_ID` | <your-workspace-id> |
| `LOG_ANALYTICS_SHARED_KEY` | <your-shared-key> |
| `PROXY_URL` | http://<internal-proxy-ip>:<port> (optional) |

---

## 🔧 Step 6 — Validate Function Logs

### 1️⃣ Log Analytics Query
In the Log Analytics Workspace, run:
```kusto
ProxyMonitoring_CL
| sort by TimeGenerated desc
| take 10
```

### 2️⃣ Metrics Captured
- `TimeGenerated`
- `TargetUrl`
- `HttpStatus`
- `ProxyStatus` (Success/Failure)
- `ResponseTime_ms`
- `ExecutedAt`

---

## 🔧 Step 7 — Additional Recommendations

✅ Set up alert rules on high response time or repeated failures.  
✅ Use Application Insights for detailed monitoring.  
✅ Rotate keys and use Azure Key Vault for secrets management.  
✅ Use Managed Identity for secure authentication (future enhancement).

---

## 📌 Summary

✅ Deploy Function App in ASE for private network monitoring.  
✅ Logs each proxy check to Log Analytics Workspace.  
✅ Secure, scalable, and cloud-native solution for real-time proxy monitoring.

---

## 🤝 Support

Raise issues or questions as needed — happy to help!
