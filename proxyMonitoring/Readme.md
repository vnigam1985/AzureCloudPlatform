# Proxy Monitoring Function App

This project contains an Azure Function App (PowerShell) that performs proxy health monitoring. It runs every second, logs each run’s metrics, and sends the data to a Log Analytics workspace. The function is designed to run **inside an App Service Environment (ASE)** with VNet integration to monitor proxies accessible only from inside your private network.

---

## 🚀 Prerequisites

✅ Azure Subscription  
✅ VNet with subnet for ASE  
✅ Azure Log Analytics Workspace  
✅ Access to your internal proxy URL  
✅ Azure CLI or Portal Access

---

## 🔧 Step 1 — Create Infrastructure

### 1️⃣ Create a Virtual Network
- Create a VNet (e.g. `my-vnet`) with an address space (e.g. 10.0.0.0/16).
- Add a subnet (e.g. `ase-subnet`) for the ASE.
- Ensure outbound connectivity from this subnet to your proxy IP.

### 2️⃣ Create a Log Analytics Workspace
- Name: `ProxyMonitoringWorkspace`
- Save the **Workspace ID** and **Primary Key** (Shared Key) — you'll need them later.

### 3️⃣ Create an App Service Environment (ASE v3)
- ILB (Internal Load Balancer) mode
- Place in the VNet `ase-subnet`.
- Region: same as your resources.
- Enable VNet Integration.

### 4️⃣ Create a Premium Azure Function App
- Runtime: PowerShell Core 7
- Plan: Elastic Premium (EP1+)
- Hosting: select the ASE (ILB) you created.
- Enable VNet integration.

---

## 🔧 Step 2 — Deploy the Function Code

### 1️⃣ Clone this repo or download the project folder:
