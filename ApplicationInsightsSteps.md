### 1\. Create an Application Insights Resource

1.  Go to **Azure Portal → Application Insights → Create**.
    
2.  Fill the details:
    
    *   **Resource Group:** (choose or create)
        
    *   **Name:** e.g., proxy-monitoring-appinsights
        
    *   **Region:** Same region as close as possible to your Azure services.
        
    *   **Application Type:** General
        
3.  Click **Review + Create**.
    

✅ Application Insights instance is now ready.

### 2\. Configure a Synthetic Availability Test

1.  Inside your Application Insights resource → go to **Availability** (left side menu).
    
2.  Click **\+ Add Standard Test**.
    
3.  Fill the test configuration:
    

*   **Test Name:** Proxy Availability Test
    
*   **Test Type:** **Standard Test**
    
*   **Test Frequency:** Every 5 minutes
    
*   **Test Locations:** Select multiple Azure regions (at least 3 for redundancy).
    
*   **URL:**
    
    *   If your proxy exposes a public endpoint (e.g., health check API):
        
        *   Use that URL.
            
    *   Example: https://proxy.customer.environment/healthcheck
        
*   **HTTP Method:** GET
    
*   **Success Criteria:**
    
    *   Test passes if **HTTP response code is 200**.
        
*   **Timeout:** 30 seconds (default).
    
*   **Alerts:** Enable alerts on test failures.
    

1.  Save the test.
    

✅ Now Azure will start sending HTTP requests from multiple regions to your proxy target.

### 3\. (Important) Proxy Configuration Considerations

⚡ **Note:**Azure built-in synthetic tests **do not support sending traffic through private proxies or VPN tunnels**.They send traffic **directly from Azure public datacenters**.

If you **must** check proxy behind a private network:

*   You need to set up a **custom synthetic tester VM** inside your network that runs your own HTTP tests (manual scripts or Application Insights SDK).
    

For external (public) proxies or external proxy endpoints — no issue.

### 4\. Setup Alerts for Test Failures

Azure automatically allows alert creation during synthetic test setup:

If you didn't do it then, set it now:

1.  Go to **Monitor → Alerts → New Alert Rule**.
    
2.  Target: Your Application Insights resource.
    
3.  Condition:
    
    *   **Signal type:** Availability Results
        
    *   **Condition:** Failed location count > 1 in last 5 minutes.
        
4.  Action Group:
    
    *   Send Email
        
    *   Send Teams Webhook
        
    *   SMS/Voice alert if needed
        

✅ You will get notified if proxy becomes unavailable.

### 5\. Visualization (Optional)

*   Inside Application Insights → **Availability** blade:
    
    *   You can view:
        
        *   Availability percentage
            
        *   Average response time
            
        *   Failures by location
            
*   Build custom Workbooks for leadership dashboards if needed.
    

Example Graphs:

*   Line chart: Uptime %
    
*   Pie chart: Failed tests by region