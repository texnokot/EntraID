# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Identity.Governance
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users

# Authenticate with required permissions
Connect-MgGraph -Scopes `
    "PrivilegedAccess.Read.AzureADGroup", `
    "PrivilegedAccess.ReadWrite.AzureADGroup", `
    "Group.Read.All", `
    "Directory.Read.All", `
    "User.Read.All"

# Get all PIM-enabled groups
$pimGroups = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/beta/privilegedAccess/aadGroups/resources" `
    -OutputType PSObject | Select-Object -ExpandProperty value

# Initialize output collection
$export = [System.Collections.Generic.List[Object]]::new()

foreach ($group in $pimGroups) {
    Write-Host "Processing group: $($group.displayName)" -ForegroundColor Cyan
    
    # Get all eligible assignments (includes both active and eligible)
    $allAssignments = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/beta/privilegedAccess/aadGroups/roleAssignments?`$filter=roleDefinition/resource/id eq '$($group.id)'&`$expand=subject,roleDefinition" `
        -OutputType PSObject | Select-Object -ExpandProperty value
    
    # Process each assignment
    foreach ($assignment in $allAssignments) {
        try {
            $user = Get-MgUser -UserId $assignment.subject.id -ErrorAction Stop
            $export.Add([PSCustomObject]@{
                GroupName       = $group.displayName
                GroupId         = $group.id
                UserName        = $user.DisplayName
                UserEmail       = $user.Mail
                UserPrincipalName = $user.UserPrincipalName
                UserId          = $user.Id
                AssignmentType  = $assignment.assignmentState
                MemberType      = $assignment.memberType
                StartDateTime   = $assignment.startDateTime
                EndDateTime     = $assignment.endDateTime
                Status          = $assignment.status
                RoleName        = $assignment.roleDefinition.displayName
            })
        }
        catch {
            Write-Warning "Failed to get user details for principal ID $($assignment.subject.id)"
        }
    }
}

# Display results
$export | Format-Table -AutoSize

# Export to CSV
$export | Export-Csv -Path "PIMGroupMemberships.csv" -NoTypeInformation -Encoding UTF8

Write-Host "Script completed. $($export.Count) records collected from $($pimGroups.Count) PIM-enabled groups." -ForegroundColor Green
