# Connect to Azure and Microsoft Graph
$startTime = Get-Date
Connect-MgGraph -Scopes "User.Read.All","Group.Read.All"

$outputFile = "RBAC_Assignments_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
$results = [System.Collections.Generic.List[object]]::new()
$subscriptions = Get-AzSubscription -WarningAction SilentlyContinue
$totalSubs = $subscriptions.Count
$currentSub = 0

# Process subscriptions with progress tracking
foreach ($sub in $subscriptions) {
    $currentSub++
    $percentComplete = ($currentSub / $totalSubs) * 100
    
    Write-Progress -Activity "Processing Subscriptions" -Status "$currentSub/$totalSubs ($([math]::Round($percentComplete,1))%)" `
        -CurrentOperation $sub.Name -PercentComplete $percentComplete
    
    # Get and process role assignments
    $roleAssignments = Get-AzRoleAssignment -ErrorAction SilentlyContinue
    foreach ($ra in $roleAssignments) {
        $displayName = $ra.DisplayName
        $signInName = $ra.SignInName
        
        if ([string]::IsNullOrEmpty($displayName)) {
            switch ($ra.ObjectType) {
                "User" { 
                    $user = Get-MgUser -UserId $ra.ObjectId -ErrorAction SilentlyContinue
                    $displayName = $user?.DisplayName
                    $signInName = $user?.UserPrincipalName
                }
                "Group" {
                    $group = Get-MgGroup -GroupId $ra.ObjectId -ErrorAction SilentlyContinue
                    $displayName = $group?.DisplayName
                }
                "ServicePrincipal" {
                    $sp = Get-MgServicePrincipal -ServicePrincipalId $ra.ObjectId -ErrorAction SilentlyContinue
                    $displayName = $sp?.DisplayName
                }
            }
        }

        $results.Add([PSCustomObject]@{
            SubscriptionId      = $sub.Id
            SubscriptionName    = $sub.Name
            ObjectId            = $ra.ObjectId
            ObjectType          = $ra.ObjectType
            RoleDefinitionName  = $ra.RoleDefinitionName
            Scope               = $ra.Scope
            DisplayName         = $displayName
            SignInName          = $signInName
        })
    }
}

# Export results
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
Write-Progress -Activity "Processing Subscriptions" -Completed

# Calculate and display execution time
$endTime = Get-Date
$executionTime = $endTime - $startTime
Write-Host "`nScript completed in $($executionTime.ToString('hh\:mm\:ss')) (hh:mm:ss)"
Write-Host "Results saved to: $outputFile"
Write-Host "Total role assignments processed: $($results.Count)"
