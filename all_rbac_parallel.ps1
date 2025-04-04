# Connect to Azure and Microsoft Graph with required permissions
$startTime = Get-Date
Connect-MgGraph -Scopes "User.Read.All","Group.Read.All","Directory.Read.All"
Connect-AzAccount

$outputFile = "RBAC_Assignments_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
$subscriptions = Get-AzSubscription -WarningAction SilentlyContinue
$totalSubs = $subscriptions.Count
$currentSub = 0

# Process subscriptions in parallel using PowerShell jobs
$jobs = $subscriptions | ForEach-Object {
    $sub = $_
    $currentSub++
    
    Start-Job -Name "Process-$($sub.Name)" -ScriptBlock {
        param($sub, $currentSub, $totalSubs)
        
        Write-Progress -Activity "Processing Subscriptions" -Status "$currentSub/$totalSubs" -PercentComplete (($currentSub / $totalSubs) * 100)
        
        Set-AzContext -Subscription $sub.Id | Out-Null
        $roleAssignments = Get-AzRoleAssignment -ErrorAction SilentlyContinue

        # Batch process object metadata
        $userIds = $roleAssignments | Where-Object { 
            $_.ObjectType -eq 'User' -and [string]::IsNullOrEmpty($_.DisplayName)
        } | Select-Object -ExpandProperty ObjectId -Unique

        $objectMap = @{}
        if ($userIds) {
            Get-MgDirectoryObjectById -Ids $userIds | ForEach-Object {
                $objectMap[$_.Id] = @{
                    DisplayName = $_.AdditionalProperties['displayName']
                    UserPrincipalName = $_.AdditionalProperties['userPrincipalName']
                }
            }
        }

        # Create results array
        $results = foreach ($ra in $roleAssignments) {
            $displayName = $ra.DisplayName
            $signInName = $ra.SignInName

            if ([string]::IsNullOrEmpty($displayName)) {
                switch ($ra.ObjectType) {
                    "User" { 
                        $lookup = $objectMap[$ra.ObjectId]
                        $displayName = $lookup.DisplayName
                        $signInName = $lookup.UserPrincipalName
                    }
                    "Group" {
                        $displayName = (Get-MgGroup -GroupId $ra.ObjectId -ErrorAction SilentlyContinue).DisplayName
                    }
                    "ServicePrincipal" {
                        $displayName = (Get-MgServicePrincipal -ServicePrincipalId $ra.ObjectId -ErrorAction SilentlyContinue).DisplayName
                    }
                }
            }

            [PSCustomObject]@{
                SubscriptionId      = $sub.Id
                SubscriptionName    = $sub.Name
                ObjectId            = $ra.ObjectId
                ObjectType          = $ra.ObjectType
                RoleDefinitionName  = $ra.RoleDefinitionName
                Scope               = $ra.Scope
                DisplayName         = $displayName
                SignInName          = $signInName
            }
        }

        return $results
    } -ArgumentList $_, $currentSub, $totalSubs
}

# Collect and export results
$results = $jobs | Receive-Job -Wait -AutoRemoveJob
$results | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

# Calculate execution time
$executionTime = (Get-Date) - $startTime
Write-Host "`nScript completed in $($executionTime.ToString('hh\:mm\:ss'))"
Write-Host "Results saved to: $outputFile"
Write-Host "Total role assignments processed: $($results.Count)"
