using namespace System.Collections

param($Timer)

# Configuration
$workspaceName = "ProxyMonitorWorkspace"
$workspaceResourceGroup = "MyResourceGroup"
$managedIdentityClientId = $env:ManagedIdentityClientId
$dceEndpoint = $env:DceEndpoint # e.g., https://proxy-monitor-dce.eastus-1.ingest.monitor.azure.com
$failoverDcrImmutableId = $env:FailoverDcrImmutableId # e.g., dcr-1234567890abcdef
$failoverTableName = "ProxyFailoverLogs_CL"
$dnsZoneName = "proxy.contoso.com"
$dnsRecordName = "proxy" # A record: proxy.proxy.contoso.com
$dnsResourceGroup = "MyResourceGroup"
$primaryIp = "10.0.0.1"
$secondaryIp = "10.0.0.2"
$primaryHttpProxyUrl = "https://primary.proxy.com:443"
$secondaryHttpProxyUrl = "https://secondary.proxy.com:443"
$primaryTcpHost = "10.0.0.1"
$secondaryTcpHost = "10.0.0.2"
$timeRange = "ago(10m)" # Last 10 minutes
$thresholdPercent = 50 # Failover if >50% Down
$subscriptionId = $env:AZURE_SUBSCRIPTION_ID # Set in Function App environment

# Thread-safe logs collection
$logs = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
$executedAt = (Get-Date).ToUniversalTime().ToString("o")

# Helper function to log events
function Add-FailoverLog {
    param($Action, $Status, $Message)
    $null = $logs.Add([PSCustomObject]@{
        Timestamp  = (Get-Date).ToUniversalTime().ToString("o")
        Action     = $Action # e.g., Failover, Rollback, Check
        Status     = $Status # e.g., Success, Failed
        Message    = $Message
        ExecutedAt = $executedAt
    })
}

# Get OAuth token for Log Analytics and Azure DNS
$identityEndpoint = $env:IDENTITY_ENDPOINT
$identityHeader = $env:IDENTITY_HEADER
$resources = @("https://monitor.azure.com", "https://management.azure.com")
$accessTokens = @{}
foreach ($resource in $resources) {
    $tokenUrl = "$identityEndpoint`?api-version=2019-08-01&resource=$resource&client_id=$managedIdentityClientId"
    $headers = @{ "X-IDENTITY-HEADER" = $identityHeader }
    try {
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Get -Headers $headers
        $accessTokens[$resource] = $tokenResponse.access_token
    } catch {
        Add-FailoverLog -Action "TokenAcquisition" -Status "Failed" -Message "Failed to acquire token for $resource`: $_"
        return
    }
}

# Get Log Analytics Workspace ID
try {
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspaceResourceGroup -Name $workspaceName
    $workspaceId = $workspace.CustomerId
} catch {
    Add-FailoverLog -Action "WorkspaceQuery" -Status "Failed" -Message "Failed to get workspace ID: $_"
    return
}

# KQL query for HTTP and TCP logs
$kqlQuery = @"
let HttpLogs = ProxyMonitorLogs_CL
| where TimeGenerated > $timeRange
| where ProxyUrl == "$primaryHttpProxyUrl"
| summarize HttpDownCount = countif(ProxyStatus == "Down"), HttpTotalCount = count()
| project HttpDownPercent = (HttpDownCount * 100.0) / HttpTotalCount;
let TcpLogs = TcpProxyMonitorLogs_CL
| where TimeGenerated > $timeRange
| where Host == "$primaryTcpHost"
| summarize TcpDownCount = countif(TcpStatus == "Down"), TcpTotalCount = count()
| project TcpDownPercent = (TcpDownCount * 100.0) / TcpTotalCount;
HttpLogs
| join kind=outer TcpLogs on `$left.HttpDownPercent == `$right.TcpDownPercent
| project CombinedDownPercent = (coalesce(HttpDownPercent, 0) * HttpTotalCount + coalesce(TcpDownPercent, 0) * TcpTotalCount) / (coalesce(HttpTotalCount, 0) + coalesce(TcpTotalCount, 0)),
          HttpDownPercent, TcpDownPercent, HttpTotalCount, TcpTotalCount
"@

# Execute KQL query
try {
    $queryResults = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $kqlQuery -ErrorAction Stop
    $results = $queryResults.Results
    if (-not $results) {
        Add-FailoverLog -Action "QueryExecution" -Status "Failed" -Message "No results returned from KQL query"
        return
    }
    $combinedDownPercent = [double]$results.CombinedDownPercent
    $httpDownPercent = [double]$results.HttpDownPercent
    $tcpDownPercent = [double]$results.TcpDownPercent
    Add-FailoverLog -Action "QueryExecution" -Status "Success" -Message "CombinedDownPercent: $combinedDownPercent%, HttpDownPercent: $httpDownPercent%, TcpDownPercent: $tcpDownPercent%"
} catch {
    Add-FailoverLog -Action "QueryExecution" -Status "Failed" -Message "Failed to execute KQL query: $_"
    return
}

# Get current DNS A record
try {
    $dnsRecord = Get-AzPrivateDnsRecordSet -ResourceGroupName $dnsResourceGroup -ZoneName $dnsZoneName -Name $dnsRecordName -RecordType A
    $currentIp = $dnsRecord.Records[0].Ipv4Address
} catch {
    Add-FailoverLog -Action "DnsQuery" -Status "Failed" -Message "Failed to get DNS A record: $_"
    return
}

# Failover logic
if ($combinedDownPercent -gt $thresholdPercent -and $currentIp -eq $primaryIp) {
    # Perform failover to secondary IP
    try {
        $recordSet = New-AzPrivateDnsRecordSet -ResourceGroupName $dnsResourceGroup -ZoneName $dnsZoneName -Name $dnsRecordName -RecordType A -Ttl 300
        $record = New-AzPrivateDnsRecordConfig -Ipv4Address $secondaryIp
        $recordSet.Records = @($record)
        Set-AzPrivateDnsRecordSet -RecordSet $recordSet
        Add-FailoverLog -Action "Failover" -Status "Success" -Message "Failed over to secondary IP $secondaryIp due to $combinedDownPercent% Down"
    } catch {
        Add-FailoverLog -Action "Failover" -Status "Failed" -Message "Failed to update DNS to secondary IP: $_"
        return
    }
} elseif ($combinedDownPercent -eq 0 -and $currentIp -eq $secondaryIp) {
    # Rollback to primary IP if primary is 100% Up
    try {
        $recordSet = New-AzPrivateDnsRecordSet -ResourceGroupName $dnsResourceGroup -ZoneName $dnsZoneName -Name $dnsRecordName -RecordType A -Ttl 300
        $record = New-AzPrivateDnsRecordConfig -Ipv4Address $primaryIp
        $recordSet.Records = @($record)
        Set-AzPrivateDnsRecordSet -RecordSet $recordSet
        Add-FailoverLog -Action "Rollback" -Status "Success" -Message "Rolled back to primary IP $primaryIp as primary is 100% Up"
    } catch {
        Add-FailoverLog -Action "Rollback" -Status "Failed" -Message "Failed to update DNS to primary IP: $_"
        return
    }
} else {
    Add-FailoverLog -Action "Check" -Status "Success" -Message "No action taken. CombinedDownPercent: $combinedDownPercent%, Current IP: $currentIp"
}

# Send logs to Log Analytics
if ($logs.Count -gt 0) {
    $headers = @{
        "Authorization" = "Bearer $($accessTokens['https://monitor.azure.com'])"
        "Content-Type"  = "application/json"
    }
    $body = $logs | ConvertTo-Json
    $uri = "$dceEndpoint/dataCollectionRules/$failoverDcrImmutableId/streams/Custom-$failoverTableName`?api-version=2023-01-01"
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
    } catch {
        Write-Error "Failed to send logs to Log Analytics: $_"
    }
} else {
    Write-Error "No logs generated for this execution"
}