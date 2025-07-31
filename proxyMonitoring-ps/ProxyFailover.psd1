# This script runs inside Azure Function (PowerShell runtime)
# Make sure your Function App has "Contributor" rights on the DNS Zone

using namespace System.Net

param($Request)

# Resource group and DNS zone info
$resourceGroupName = "MyResourceGroup"
$dnsZoneName = "internal.contoso.net
$recordSetName = "proxy"
$originalIP = "10.0.0.9"
$fallbackIP = "10.0.0.8"

# Authenticate using Managed Identity
Connect-AzAccount -Identity

# Parse alert payload
$body = $Request.Body | ConvertFrom-Json

# Debug log (can be removed)
Write-Output "Received alert: $($body | ConvertTo-Json -Depth 5)"

# Extract the status of the alert
$alertStatus = $body.data.essentials.monitorCondition  # should be "Fired" or "Resolved"

# Determine target IP based on alert state
switch ($alertStatus) {
    "Fired"   { $newIP = $fallbackIP }
    "Resolved" { $newIP = $originalIP }
    default {
        return @{
            statusCode = [HttpStatusCode]::BadRequest
            body = "Unknown monitorCondition: $alertStatus"
        }
    }
}

# Fetch existing record set
$recordSet = Get-AzPrivateDnsRecordSet `
    -ResourceGroupName $resourceGroupName `
    -ZoneName $dnsZoneName `
    -Name $recordSetName `
    -RecordType A

# Update the IP address in the record set
# Remove all existing A records first
$recordSet.Records.Clear()

# Add the new IP address
$newARecord = New-AzPrivateDnsRecordConfig -IPv4Address $newIP
$recordSet.Records.Add($newARecord)

# Commit the update
Set-AzPrivateDnsRecordSet -RecordSet $recordSet

# Response
return @{
    statusCode = [HttpStatusCode]::OK
    body = "DNS A record for $recordSetName updated to $newIP due to alert status: $alertStatus"
}