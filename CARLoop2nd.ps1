# TODO
# DONE 1. Add start date and end date
# DONE Notify once the access review is completed
# DONE 3. Additional content for reviewer email
# 4. RUN only on ELIGIBLE not Active - 18 roles marked as eligible


# https://learn.microsoft.com/en-us/graph/api/resources/accessreviewinstance?view=graph-rest-1.0
#


# Ensure the required modules are imported
# Import-Module Microsoft.Graph.Identity.Governance
# Import-Module -Name Microsoft.Graph

# Authenticate to Microsoft Graph
Connect-MgGraph -Scopes "AccessReview.ReadWrite.All", "Directory.ReadWrite.All"

# Define role names and their corresponding IDs
# https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference
# All roles can be found in the CARLoop.ps1 script

$roles = @{
    "Global Administrator" = "62e90394-69f5-4237-9190-012177145e10"
    "Groups Administrator" = "fdd7a751-b60b-444a-984c-02652fe8fa1c"
}

# Get the current month for naming the access review
$currentMonth = (Get-Date).ToString("MMMM")

# Loop through each role and create an access review
foreach ($role in $roles.GetEnumerator()) {

    Write-Host "Creating access review for role: $($role.Key)" -ForegroundColor Cyan

    # Get eligible role assignments for the specified role using roleEligibilityScheduleInstances
    # try {
    #     $eligibleAssignments = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "roleDefinitionId eq '$($role.Value)'"

    #     # Check if we have any eligible assignments
    #     if ($eligibleAssignments.Count -eq 0) {
    #         Write-Host "No eligible assignments found for role: $($role.Key)" -ForegroundColor Yellow
    #         continue
    #     }

    #     Write-Host "Found $($eligibleAssignments.Count) eligible assignments for role: $($role.Key)" -ForegroundColor Green
    #     } catch {
    #         Write-Host "Error fetching eligible assignments for role: $($role.Key) - $_" -ForegroundColor Red
    #         continue
    #     }

    # Create unique display name for each access review based on the month and role name
    $displayName = "Access Review - $currentMonth - $($role.Key)"

    # Define parameters for the access review
    $params = @{
        displayName = $displayName
        descriptionForAdmins = "Review access for role: $($role.Key)" # Review description
        descriptionForReviewers = "This is a review please complete"  # Friendly description
        scope = @{
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
                    query = "/roleManagement/directory/roleDefinitions/$($role.Value)"
                    queryType = "MicrosoftGraph"
                }
            )
        }

        reviewers = @()  # Self-reviewers
        
        # Settings for the access review
        # more: https://learn.microsoft.com/en-us/graph/api/resources/accessreviewschedulesettings?view=graph-rest-1.0
        settings = @{
            mailNotificationsEnabled = $true  # Enable email notifications
            reminderNotificationsEnabled = $true  # Enable reminders
            justificationRequiredOnApproval = $true  # Require justification on approval
            defaultDecisionEnabled = $true  # No default decision
            defaultDecision = "Deny"  # No default decision
            autoApplyDecisionsEnabled = $true  # Automatically apply decisions
            # instanceDurationInDays = 21  # Duration of 21 days
            recommendationsEnabled = $false  # Disable recommendations
            recurrence = @{
                range = @{
                    type = "endDate"
                    startDate = "2024-11-08"
                    endDate = "2024-12-28"
                }
            }
        }

        # Notify once the access review is completed
        additionalNotificationRecipients = @(
            @{
                "@odata.type" = "#microsoft.graph.accessReviewNotificationRecipientItem"
                notificationRecipientScope = @{
                    "@odata.type" = "#microsoft.graph.accessReviewNotificationRecipientQueryScope"
                    # place the user objhect id from Entra ID
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


