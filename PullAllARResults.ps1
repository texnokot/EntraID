
# Install the Microsoft.Graph module if not already installed
# Install-Module Microsoft.Graph 
# Import the Microsoft.Graph module
# Import-Module Microsoft.Graph
# Install the MS Identity Governance module
# Install-Module -Name Microsoft.Graph.Identity.Governance
# Import both if needed


# Function to place results from Get requests to Microsoft Graph
function Get-GraphData {
    # GET data from Microsoft Graph.
    param (
        [parameter(Mandatory = $true)]
        $AccessToken,

        [parameter(Mandatory = $true)]
        $Uri
    )

    # Check if authentication was successful.
    if ($AccessToken) {
        # Format headers.
        $Headers = @{
            'Content-Type'  = "application/json"
            'Authorization' = "Bearer $AccessToken" 
            'ConsistencyLevel' = "eventual"   
        }

        # Create an empty array to store the result.
        $QueryResults = @()

        # Invoke REST method and fetch data until there are no pages left.
        do {
            $Results = ""
            $StatusCode = ""

            do {
                try {
                    $Results = Invoke-RestMethod -Headers $Headers -Uri $Uri -Method "GET" -ContentType "application/json"

                    $StatusCode = $Results.StatusCode
                } catch {
                    $StatusCode = $_.Exception.Response.StatusCode.value__

                    if ($StatusCode -eq 429) {
                        Write-Warning "Got throttled by Microsoft. Sleeping for 45 seconds..."
                        Start-Sleep -Seconds 45
                    }
                    else {
                        Write-Error $_.Exception
                    }
                }
            } while ($StatusCode -eq 429)

            if ($Results.value) {
                $QueryResults += $Results.value
            }
            else {
                $QueryResults += $Results
            }

            $Uri = $Results.'@odata.nextLink'
        } until (!($Uri))

        # Return the result.
        $QueryResults
    }
    else {
        Write-Error "No Access Token"
    }
}

# Define the values applicable for the application used to connect to the Graph (change these details for your tenant and registered app)
$AppId = "AppID"
$TenantId = "TenantID"
$AppSecret = 'Secret'

$OutputCSV = "AllAzureADAccessReviewResults.csv"

# Construct URI and body needed for authentication
$uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$body = @{
    client_id     = $AppId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $AppSecret
    grant_type    = "client_credentials"
}

# Get OAuth 2.0 Token
$tokenRequest = Invoke-WebRequest -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $body
# Unpack Access Token
$token = ($tokenRequest.Content | ConvertFrom-Json).access_token
$Headers = @{
            'Content-Type'  = "application/json"
            'Authorization' = "Bearer $token" 
            'ConsistencyLevel' = "eventual" 
}

Write-Host "Fetching Azure AD Access Review Data..."

# Define the Graph API URL for all access review definitions
$graphApiUrl = "https://graph.microsoft.com/v1.0/identityGovernance/accessReviews/definitions"

# Get the list of all access review definitions
$accessReviewDefinitions = Get-GraphData -AccessToken $token -Uri $graphApiUrl

# DEBUG: Check if any access review definitions were found
Write-Host "How many definitions: " $accessReviewDefinitions.Count

if ($accessReviewDefinitions.Count -eq 0) {
    Write-Host "No access review definitions found. Exiting."
    Disconnect-MgGraph
    exit
}

# Get authenticated to the Graph for using powershell commands from IdentityGovernance
$tokens = $token | ConvertTo-SecureString -AsPlainText -Force
Connect-MgGraph -AccessToken $tokens -NoWelcome

# Create an array to accumulate all results
$allResults = @()

# Loop through each access review definition
foreach ($definition in $accessReviewDefinitions) {
    $definitionId = $definition.Id
    $definitionName = $definition.DisplayName

    Write-Host "Access Review Definition ID: $definitionId"
    Write-Host "Access Review Definition Name: $definitionName"

    # Get the instances for the access review definition
    $instances = Get-MgIdentityGovernanceAccessReviewDefinitionInstance -AccessReviewScheduleDefinitionId $definitionId -All

    # Loop through each instance
    foreach ($instance in $instances) {
        $instanceId = $instance.Id

        # Get decisions for the specific access review instance
        $decisions = Get-MgIdentityGovernanceAccessReviewDefinitionInstanceDecision -AccessReviewScheduleDefinitionId $definitionId -AccessReviewInstanceId $instanceId -All

        # Loop through each decision and store the result
        foreach ($decision in $decisions) {
            $result = [PSCustomObject]@{
                AccessReviewDefinitionId = $definitionId
                AccessReviewDefinitionName = $definitionName
                AccessReviewInstanceId = $instanceId
                PrincipalName = $decision.PrincipalDisplayName
                Decision = $decision.Decision
                ReviewedDate = $decision.ReviewedDateTime
                ReviewResult = $decision.Result
                ReviewResultDetails = $decision.Details
            }

            # Add the result to the accumulated array
            $allResults += $result
        }
    }
}

# Export all results to a single CSV file
$allResults | Export-Csv -Path $OutputCSV -NoTypeInformation

Write-Host "All access review results exported to $OutputCSV"

# Disconnect from Microsoft Graph
Disconnect-MgGraph
