[OutputType('PSAzureOperationResponse')]
param (
    [Parameter(Mandatory = $false)]
    [object] $WebhookData
)

$ErrorActionPreference = 'Stop'

# Hardcoded variables (replace with your values)
$resourceGroupName = 'YourResourceGroup'  # DNS zone resource group
$zoneName = 'yourprivatezone.com'         # Private DNS zone name
$recordName = 'www'                       # Relative name of the A record (e.g., 'www' for www.yourprivatezone.com)
$originalIp = '10.0.0.4'                  # Original IP for rollback
$newIp = '10.0.0.5'                       # New IP for update (e.g., failover)

if ($WebhookData) {
    # Parse the JSON payload
    $webhookBody = ConvertFrom-Json -InputObject $WebhookData.RequestBody
    $schemaId = $webhookBody.schemaId

    if ($schemaId -eq 'azureMonitorCommonAlertSchema') {
        $essentials = $webhookBody.data.essentials
        $monitorCondition = $essentials.monitorCondition
        $alertRule = $essentials.alertRule  # Optional: Log or use for conditions
        Write-Output "Alert rule: $alertRule, Condition: $monitorCondition"

        # Authenticate using system-assigned managed identity
        Disable-AzContextAutosave -Scope Process
        $azureContext = (Connect-AzAccount -Identity).context
        $azureContext = Set-AzContext -SubscriptionName $azureContext.Subscription -DefaultProfile $azureContext

        # Get the existing A record set
        $recordSet = Get-AzPrivateDnsRecordSet -ResourceGroupName $resourceGroupName -ZoneName $zoneName -Name $recordName -RecordType A

        if ($recordSet) {
            if ($monitorCondition -eq 'Fired') {
                # Update to new IP
                $recordSet.Records[0].Ipv4Address = $newIp
                Set-AzPrivateDnsRecordSet -RecordSet $recordSet
                Write-Output "Updated A record '$recordName' to IP $newIp"
            } elseif ($monitorCondition -eq 'Resolved') {
                # Roll back to original IP
                $recordSet.Records[0].Ipv4Address = $originalIp
                Set-AzPrivateDnsRecordSet -RecordSet $recordSet
                Write-Output "Rolled back A record '$recordName' to IP $originalIp"
            } else {
                Write-Output "Unknown monitor condition: $monitorCondition. No action taken."
            }
        } else {
            Write-Error "A record set '$recordName' not found in zone '$zoneName'."
        }
    } else {
        Write-Error "Unsupported schema: $schemaId. Ensure common alert schema is enabled."
    }
} else {
    Write-Error "No webhook data received."
}