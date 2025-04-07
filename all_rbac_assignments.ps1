# Connect to Azure and Microsoft Graph
$startTime = Get-Date
Connect-MgGraph -Scopes "Directory.Read.All","User.Read.All","Group.Read.All","Application.Read.All"
Connect-AzAccount

$outputFile = "RBAC_Assignments_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
$results = [System.Collections.Generic.List[object]]::new()
$subscriptions = Get-AzSubscription -WarningAction SilentlyContinue
$totalSubs = $subscriptions.Count
$currentSub = 0

foreach ($sub in $subscriptions) {
    $currentSub++
    $percentComplete = ($currentSub / $totalSubs) * 100
    
    Write-Progress -Activity "Processing Subscriptions" -Status "$currentSub/$totalSubs ($([math]::Round($percentComplete,1))%)" `
        -CurrentOperation $sub.Name -PercentComplete $percentComplete

    Set-AzContext -Subscription $sub.Id | Out-Null
    $roleAssignments = Get-AzRoleAssignment -ErrorAction SilentlyContinue

    # Batch lookup missing identities
    $missingIdentityIds = $roleAssignments | 
        Where-Object { [string]::IsNullOrEmpty($_.DisplayName) } | 
        Select-Object -ExpandProperty ObjectId -Unique
    
    $identityMap = @{}
    if ($missingIdentityIds) {
        Get-MgDirectoryObjectById -Ids $missingIdentityIds -ErrorAction SilentlyContinue | ForEach-Object {
            $objectType = $_.AdditionalProperties['@odata.type'].Split('.')[-1]
            
            # Handle Managed Identity detection
            if ($objectType -eq "ServicePrincipal") {
                $sp = Get-MgServicePrincipal -ServicePrincipalId $_.Id -Property "servicePrincipalType,appId" -ErrorAction SilentlyContinue
                if ($sp.ServicePrincipalType -eq "ManagedIdentity" -or $sp.AppId -match "managedidentity") {
                    $objectType = "ManagedIdentity"
                }
            }
            
            $identityMap[$_.Id] = @{
                DisplayName = $_.AdditionalProperties['displayName']
                UserPrincipalName = $_.AdditionalProperties['userPrincipalName']
                ObjectType = $objectType
            }
        }
    }

    foreach ($ra in $roleAssignments) {
        $displayName = $ra.DisplayName
        $signInName = $ra.SignInName
        $objectType = $ra.ObjectType

        if ([string]::IsNullOrEmpty($displayName)) {
            $lookup = $identityMap[$ra.ObjectId]
            if ($lookup) {
                $displayName = $lookup.DisplayName
                $objectType = $lookup.ObjectType
                $signInName = if ($lookup.UserPrincipalName) { $lookup.UserPrincipalName } else { $signInName }
            }
        }

        # Final object type normalization
        $objectType = switch ($objectType) {
            "ServicePrincipal" { 
                $sp = Get-MgServicePrincipal -ServicePrincipalId $ra.ObjectId -Property "servicePrincipalType" -ErrorAction SilentlyContinue
                if ($sp.ServicePrincipalType -eq "ManagedIdentity") {
                    "ManagedIdentity"
                } else {
                    "ServicePrincipal"
                }
            }
            default { $objectType }
        }

        $results.Add([PSCustomObject]@{
            SubscriptionId      = $sub.Id
            SubscriptionName    = $sub.Name
            ObjectId            = $ra.ObjectId
            ObjectType          = $objectType
            RoleDefinitionName  = $ra.RoleDefinitionName
            Scope               = $ra.Scope
            DisplayName         = $displayName
            SignInName          = $signInName
        })
    }
}

$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Progress -Activity "Processing Subscriptions" -Completed

$executionTime = (Get-Date) - $startTime
Write-Host "`nScript completed in $($executionTime.ToString('hh\:mm\:ss'))"
Write-Host "Results saved to: $outputFile"
Write-Host "Total role assignments processed: $($results.Count)"
