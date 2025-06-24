# Disconnect any existing Graph session
# Disconnect-MgGraph -ErrorAction SilentlyContinue
# Install the Microsoft Graph module
# Install-Module Microsoft.Graph -Scope CurrentUser -Force  
 
# Connect with all required permissions
Connect-MgGraph -Scopes "Policy.ReadWrite.ConditionalAccess", "Application.Read.All"
# Variables
$policyName = "VA - Require MFA for AppX - PS"
$appDisplayName = "Evilapp" # Replace with your application's display name

# Get the application's AppId (clientId)
$app = Get-MgApplication -Filter "displayName eq '$appDisplayName'"
if (-not $app) {
    Write-Error "Application not found. Please check the display name."
    return
}

# Construct the policy definition
$params = @{
    displayName = $policyName
    state       = "enabledForReportingButNotEnforced"  # Report-only mode
    conditions  = @{
        users = @{
            includeUsers = @("All")
        }
        applications = @{
            includeApplications = @($app.AppId)
        }
    }
    grantControls = @{
        operator = "OR"
        builtInControls = @("mfa")
    }
}

# Create the Conditional Access policy
$policy = New-MgIdentityConditionalAccessPolicy -BodyParameter $params

Write-Host "Conditional Access policy '$policyName' created in report-only mode for app: $($app.AppId)"
