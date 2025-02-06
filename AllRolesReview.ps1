# Import required modules
Import-Module Microsoft.Graph.Identity.Governance

# Authenticate to Microsoft Graph
Connect-MgGraph -Scopes "AccessReview.ReadWrite.All", "Directory.ReadWrite.All"

# Path to the CSV file
$csvPath = "roles.csv"

# Read the CSV file with semicolon delimiter
$roles = Import-Csv -Path $csvPath -Delimiter ";"

# Debug: Print the contents of the CSV
Write-Host "Contents of CSV file:" -ForegroundColor Cyan
$roles | Format-Table -AutoSize

# Get the current month for naming the access review
$currentMonth = (Get-Date).ToString("MMMM")

# Loop through each role in the CSV and create an access review
foreach ($role in $roles) {
    # Verify that we have values from the CSV
    if ([string]::IsNullOrWhiteSpace($role.RoleName) -or [string]::IsNullOrWhiteSpace($role.RoleId) -or [string]::IsNullOrWhiteSpace($role.AssignmentType)) {
        Write-Host "Skipping row due to missing data: $($role | ConvertTo-Json)" -ForegroundColor Yellow
        continue
    }

    Write-Host "Creating access review for role: $($role.RoleName) - Assignment Type: $($role.AssignmentType)" -ForegroundColor Cyan

    # Create unique display name for each access review
    $displayName = "Access Review - $currentMonth - $($role.RoleName) ($($role.AssignmentType))"

    # Define parameters for the access review
    $params = @{
        displayName = $displayName
        descriptionForAdmins = "Review $($role.AssignmentType) access for role: $($role.RoleName)"
        descriptionForReviewers = "This is a review of $($role.AssignmentType) role assignments."
        reviewers = @()
        settings = @{
            mailNotificationsEnabled = $true
            reminderNotificationsEnabled = $true
            justificationRequiredOnApproval = $true
            defaultDecisionEnabled = $true
            defaultDecision = "Deny"
            # instanceDurationInDays = 14
            autoApplyDecisionsEnabled = $true
            recommendationsEnabled = $false
            recurrence = @{
                range = @{
                    type = "endDate"
                    startDate = "2025-02-08"
                    endDate = "2025-02-28"
                }
            }
        }
    }

    # Set the scope based on the assignment type
    if ($role.AssignmentType -eq "Eligible") {
        $params.scope = @{
            "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
            query = "/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') or isof(principal,'microsoft.graph.group')) and roleDefinitionId eq '$($role.RoleId)'"
            queryType = "MicrosoftGraph"
        }
    } else {
        $params.scope = @{
            "@odata.type" = "#microsoft.graph.principalResourceMembershipsScope"
            principalScopes = @(
                @{
                    "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
                    query = "/users"
                    queryType = "MicrosoftGraph"
                }
                @{
                    "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
                    query = "/groups"
                    queryType = "MicrosoftGraph"
                }
            )
            resourceScopes = @(
                @{
                    "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
                    query = "/roleManagement/directory/roleDefinitions/$($role.RoleId)"
                    queryType = "MicrosoftGraph"
                }
            )
        }
    }


    # Create the access review using the defined parameters
    try {
        New-MgIdentityGovernanceAccessReviewDefinition -BodyParameter $params -ErrorAction Stop
        Write-Host "Access review created successfully for $($role.RoleName)" -ForegroundColor Green
    } catch {
        Write-Host "Error creating access review for $($role.RoleName): $_" -ForegroundColor Red
    }
}
