# TODO
# 1. Add start date and end date
# 2. Notify once the access review is completed
# 3. Additional content for reviewer email
# 4. RUN only on ELIGIBLE not Active - 18 roles marked as eligible
 



# Ensure the required modules are imported
# Import-Module Microsoft.Graph.Identity.Governance
# Import-Module -Name Microsoft.Graph

# Authenticate to Microsoft Graph
Connect-MgGraph -Scopes "AccessReview.ReadWrite.All", "Directory.ReadWrite.All"

# Define role names and their corresponding IDs
# https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference

$roles = @{
    "Authentication Administrator" = "c4e39bd9-1100-46d3-8c65-fb160da0071f"
    "Directory Readers" = "88d8e3e3-8f55-4a1e-953a-9b9898b8876b"
    "Directory Writers" = "9360feb5-f418-4baa-8175-e2a00bac4301"
    "Exchange Administrator" = "29232cdf-9323-42fd-ade2-1d097af3e4de"
    "Global Administrator" = "62e90394-69f5-4237-9190-012177145e10"
    "Groups Administrator" = "fdd7a751-b60b-444a-984c-02652fe8fa1c"
    "Helpdesk Administrator" = "729827e3-9c14-49f7-bb1b-9608f156bbb8"
    "Power Platform Administrator" = "11648597-926c-4cf3-9c36-bcebb0ba8dcc"
    "Privileged Authentication Administrator" = "7be44c8a-adaf-4e2a-84d6-ab2649e08a13"
    "Reports Reader" = "4a5d8f65-41da-4de4-8968-e035b65339cf"
    "Security Administrator" = "194ae4cb-b126-40b2-bd5b-6091b380977d"
    "Security Reader" = "5d6b6bb7-de71-4623-b4af-96380a352509"
    "Skype for Business Administrator" = "75941009-915a-4869-abe7-691bff18279e"
    "Teams Administrator" = "69091246-20e8-4a56-aa4d-066075b2a7a8"
    "Teams Communications Support Engineer" = "f70938a0-fc10-4177-9e90-2178f8765737"
    "User Administrator" = "fe930be7-5e62-47db-91af-98c3a49a38b1"
    "Application Administrator" = "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3"
    "Microsoft Entra Joined Device Local Administrator" = "9f06204d-73c1-4d4c-880a-6edb90606fd8"
    "Azure DevOps Administrator" = "e3973bdf-4987-49ae-837a-ba8e231c7286"
    "Billing Administrator" = "b0f54661-2d74-4c50-afa3-1ec803f12efe"
    "Cloud App Security Administrator" = "892c5842-a9a6-463a-8041-72aa08ca3cf6"
    "Cloud Application Administrator" = "158c047a-c907-4556-b7ef-446551a6b5f7"
    "Cloud Device Administrator" = "7698a772-787b-4ac8-901f-60d6b08affd2"
    "Compliance Administrator" = "17315797-102d-40b4-93e0-432062caca18"
    "Compliance Data Administrator" = "e6d1a23a-da11-4be4-9570-befc86d067a7"
    "Conditional Access Administrator" = "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9"
    "Exchange Recipient Administrator" = "31392ffb-586c-42d1-9346-e59415a2cc4e"
    "Fabric Administrator" = "a9ea8996-122f-4c74-9520-8edcd192826c"
    "Global Reader" = "f2ef992c-3afb-46b9-b7cf-a126ee74c451"
    "Hybrid Identity Administrator" = "8ac3fc64-6eca-42ea-9e69-59f4c7b60eb2"
    "Identity Governance Administrator" = "45d8d3c5-c802-45c6-b32a-1d70b5e1e86e"
    "Intune Administrator" = "3a2c62db-5318-420d-8d74-23affee5d9d5"
    "License Administrator" = "4d6ac14f-3453-41d0-bef9-a3e0c569773a"
    "Message Center Reader" = "790c1fb9-7f7d-4f88-86a1-ef1f95c05c1b"
    "Password Administrator" = "966707d0-3269-4727-9be2-8c3a10f19b9d"
    "Privileged Role Administrator" = "e8611ab8-c189-46e8-94e1-60213ab1f814"
    "Security Operator" = "5f2222b1-57c3-48ba-8ad5-d4759f1fde6f"
    "Service Support Administrator" = "f023fd81-a637-4b56-95fd-791ac0226033"
    "SharePoint Administrator" = "f28a1f50-f6e7-4571-818b-6a12f2af6b6c"
    "Teams Communications Administrator" = "baf37b3a-610e-45da-9e62-d9d1e5e8914b"
    "Teams Devices Administrator" = "3d762c5a-1b6c-493f-843e-55a3b42923d4"
    "User Experience Success Manager" = "27460883-1df1-4691-b032-3b79643e5e63"
    "Windows 365 Administrator" = "11451d60-acb2-45eb-a7d6-43d0f0125c13"
    "Yammer Administrator" = "810a2642-a034-447f-a5e8-41beaa378541"
}

# Get the current month for naming the access review
$currentMonth = (Get-Date).ToString("MMMM")

# Loop through each role and create an access review
foreach ($role in $roles.GetEnumerator()) {
    # Create unique display name for each access review based on the month and role name
    $displayName = "Access Review - $currentMonth - $($role.Key)"

    # Define parameters for the access review
    $params = @{
        displayName = $displayName
        descriptionForAdmins = "Review access for role: $($role.Key)"
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
            defaultDecisionEnabled = $false  # No default decision
            defaultDecision = "None"  # No default decision
            instanceDurationInDays = 21  # Duration of 21 days
            recommendationsEnabled = $false  # Disable recommendations
        }
    }

    # Create the access review using the defined parameters
    New-MgIdentityGovernanceAccessReviewDefinition -BodyParameter $params
}


