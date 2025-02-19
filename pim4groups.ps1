# No changes needed, can be run as-is
#region Get accesstoken
$ClientID = '1950a258-227b-4e31-a9cf-717495945fc2'
$TenantID = 'common'
$Resource = "01fc33a7-78ba-4d2f-a4b7-768e336e890e"
$DeviceCodeRequestParams = @{
    Method = 'POST'
    Uri    = "https://login.microsoftonline.com/$TenantID/oauth2/devicecode"
    Body   = @{
        client_id = $ClientId
        resource  = $Resource
    }
}
$DeviceCodeRequest = Invoke-RestMethod @DeviceCodeRequestParams
Write-Host $DeviceCodeRequest.message -ForegroundColor Yellow
pause
$TokenRequestParams = @{
    Method = 'POST'
    Uri    = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    Body   = @{
        grant_type = "urn:ietf:params:oauth:grant-type:device_code"
        code       = $DeviceCodeRequest.device_code
        client_id  = $ClientId
    }
}
$TokenRequest = Invoke-RestMethod @TokenRequestParams
$token = "Bearer {0}" -f $TokenRequest.access_token # Oauth token from the azure portal
#endregion
#region Get PIM groups
$pimgroups = Invoke-RestMethod -Method Get -Uri "https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/aadGroups/resources?$select=id,displayName,type,externalId&$expand=parent&$top=10" -Headers @{Authorization = "$token"} #-ContentType "application/json"
$assignments = @()
$n = $pimgroups.value.Count
for($i=0;$i -lt $n;$i++){
   $grpassignment = Invoke-RestMethod -Method Get -Uri "https://api.azrbac.mspim.azure.com/api/v2/privilegedAccess/aadGroups/roleAssignments?`$expand=linkedEligibleRoleAssignment,subject,roleDefinition(`$expand=resource)&`$filter=(roleDefinition/resource/id%20eq%20%27$($pimgroups.value[$i].id)%27)"  -Headers @{Authorization = "$token"} #-ContentType "application/json, text/javascript, */*; q=0.01"
   $assignments += $grpassignment.value
}
#endregion
#region Collect group eligibility and store in $export
$export = @()
$groupedassignments = $assignments|  Group-Object -Property {$_.roleDefinition.resource.displayName} 
$n = $groupedassignments.Count
for($i=0;$i -lt $n;$i++){
    $output = [PSCustomObject]@{
        Name = $($groupedassignments[$i].name)
        User = $($groupedassignments[$i].Group.subject.displayName)
        Email = $($groupedassignments[$i].Group.subject.email)
        memberType = $($groupedassignments[$i].Group.MemberType)
        assignmentState = $($groupedassignments[$i].Group.assignmentState)
        status = $($groupedassignments[$i].Group.status)
    }
   $export += $output
}
clear-host
Write-Host '$export contains the output of the script.' -ForegroundColor Yellow
#endregion
