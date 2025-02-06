# Authenticate to Microsoft Graph
Connect-MgGraph -Scopes "AccessReview.ReadWrite.All", "Directory.ReadWrite.All"

# Define role names and their corresponding IDs
$roles = @{
    "Global Administrator" = "62e90394-69f5-4237-9190-012177145e10"
    "Groups Administrator" = "fdd7a751-b60b-444a-984c-02652fe8fa1c"
}

# Get the current month for naming the access review
$currentMonth = (Get-Date).ToString("MMMM")

# Loop through each role and create an access review
foreach ($role in $roles.GetEnumerator()) {
    Write-Host "Creating access review for role: $($role.Key)" -ForegroundColor Cyan

    # Create unique display name for each access review based on the month and role name
    $displayName = "Access Review - $currentMonth - $($role.Key) (Eligible)"

    # Define parameters for the access review
    $params = @{
        displayName = $displayName
        descriptionForAdmins = "Review eligible access for role: $($role.Key)"
        descriptionForReviewers = "This is a review of eligible role assignments."
        scope = @{
            "@odata.type" = "#microsoft.graph.accessReviewQueryScope"
            query = "/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') or isof(principal,'microsoft.graph.group')) and roleDefinitionId eq '$($role.Value)'"
            queryType = "MicrosoftGraph"
        }
        reviewers = @()  # Self-reviewers
        settings = @{
            mailNotificationsEnabled = $true
            reminderNotificationsEnabled = $true
            justificationRequiredOnApproval = $true
            defaultDecisionEnabled = $true
            defaultDecision = "Deny"
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
        additionalNotificationRecipients = @(
            @{
                "@odata.type" = "#microsoft.graph.accessReviewNotificationRecipientItem"
                notificationRecipientScope = @{
                    "@odata.type" = "#microsoft.graph.accessReviewNotificationRecipientQueryScope"
                    query = "/users/3e1204bc-d84b-4006-8a6a-3a06d9ab13ca"
                    queryType = "MicrosoftGraph"               
                }
                notificationTemplateType = "CompletedAdditionalRecipients"
            }
        )
    }

    # Create the access review using the defined parameters
    New-MgIdentityGovernanceAccessReviewDefinition -BodyParameter $params
}
