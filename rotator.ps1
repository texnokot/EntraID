# Parameters - update these with your values
$KeyVaultName = ""
$RGName = ""
$ClientId = ""
$ClientSecret = ""
$TenantId = ""

# Authenticate to Azure
$securePassword = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($ClientId, $securePassword)
Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $TenantId

# Get an access token for Microsoft Graph
$token = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token

# Convert token to SecureString (required for Microsoft Graph PowerShell SDK v2.x+)
$secureToken = ConvertTo-SecureString $token -AsPlainText -Force

# Connect to Microsoft Graph using the access token
Connect-MgGraph -AccessToken $secureToken

Write-Output "Successfully authenticated to Azure and Microsoft Graph"

# Ensure you've run the authentication script above first

function Get-EntraIDAppCredentials {
    $Report = [System.Collections.Generic.List[Object]]::new()
    $Apps = Get-MgApplication -All -Property 'AppId','DisplayName','PasswordCredentials','KeyCredentials','Id'
    
    Write-Output "Found $($Apps.Count) applications"
    
    foreach ($App in $Apps) {
        # Check application for client secrets
        if ($null -ne $App.PasswordCredentials) {
            foreach ($Secret in $App.PasswordCredentials) {
                $DaysLeft = ($Secret.EndDateTime - (Get-Date)).Days
                
                $ReportLine = [PSCustomObject]@{
                    ApplicationName = $App.DisplayName
                    ApplicationID = $App.AppId
                    ObjectID = $App.Id
                    CredentialType = "ClientSecret"
                    CredentialID = $Secret.KeyId
                    DisplayName = $Secret.DisplayName
                    StartDateTime = $Secret.StartDateTime
                    EndDateTime = $Secret.EndDateTime
                    DaysLeft = $DaysLeft
                    ExpireStatus = if ($DaysLeft -lt 0) { "Expired" } 
                                   elseif ($DaysLeft -lt 30) { "NearExpiry" } 
                                   else { "Valid" }
                }
                $Report.Add($ReportLine)
            }
        }
        
        # Check application for certificates
        if ($null -ne $App.KeyCredentials) {
            foreach ($Cert in $App.KeyCredentials) {
                $DaysLeft = ($Cert.EndDateTime - (Get-Date)).Days
                
                $ReportLine = [PSCustomObject]@{
                    ApplicationName = $App.DisplayName
                    ApplicationID = $App.AppId
                    ObjectID = $App.Id
                    CredentialType = "Certificate"
                    CredentialID = $Cert.KeyId
                    DisplayName = $Cert.DisplayName
                    StartDateTime = $Cert.StartDateTime
                    EndDateTime = $Cert.EndDateTime
                    DaysLeft = $DaysLeft
                    ExpireStatus = if ($DaysLeft -lt 0) { "Expired" } 
                                   elseif ($DaysLeft -lt 30) { "NearExpiry" } 
                                   else { "Valid" }
                }
                $Report.Add($ReportLine)
            }
        }
    }
    
    return $Report
}

# Run the function and display results
$credentials = Get-EntraIDAppCredentials
Write-Output "Found $($credentials.Count) credentials across all applications"

# Show a summary of expiring credentials
$expiring = $credentials | Where-Object { $_.ExpireStatus -eq "NearExpiry" }
Write-Output "Found $($expiring.Count) credentials expiring within 30 days"
$expiring | Format-Table ApplicationName, CredentialType, DaysLeft, EndDateTime

#update expiring secrets
function Update-ExpiringSecrets {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory)]
        [string]$KeyVaultResourceGroup
    )

    # Ensure modules are loaded
    # Import-Module Microsoft.Graph.Applications, Az.KeyVault -ErrorAction Stop

    # Get credentials report
    $CredentialsReport = Get-EntraIDAppCredentials
    
    # Process near-expiry secrets
    $NearExpirySecrets = $CredentialsReport | 
        Where-Object { $_.CredentialType -eq "ClientSecret" -and $_.ExpireStatus -eq "NearExpiry" }

    foreach ($Secret in $NearExpirySecrets) {
        try {
            # 1. Generate new Entra ID secret
            $NewSecretParams = @{
                ApplicationId = $Secret.ObjectID
                PasswordCredential = @{
                    DisplayName = "Rotated_$(Get-Date -Format 'yyyyMMdd')"
                    EndDateTime = (Get-Date).AddYears(1).ToUniversalTime()
                }
            }
            
            if ($PSCmdlet.ShouldProcess($Secret.ApplicationID, "Create new client secret")) {
                $NewSecret = Add-MgApplicationPassword @NewSecretParams
            }

            # 2. Update Azure Key Vault (application ID = secret name)
            $SecretValue = ConvertTo-SecureString $NewSecret.SecretText -AsPlainText -Force
            
            if ($PSCmdlet.ShouldProcess($KeyVaultName, "Update secret $($Secret.ApplicationID)")) {
                Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $Secret.ApplicationID -SecretValue $SecretValue | Out-Null
            }

            # 3. Remove old expiring secret from Entra ID
            if ($PSCmdlet.ShouldProcess($Secret.ApplicationID, "Remove expiring secret $($Secret.CredentialID)")) {
                Remove-MgApplicationPassword -ApplicationId $Secret.ObjectID -KeyId $Secret.CredentialID
            }

            # Output result
            [PSCustomObject]@{
                ApplicationID  = $Secret.ApplicationID
                ApplicationName = $Secret.ApplicationName
                NewSecretID    = $NewSecret.KeyId
                OldSecretID    = $Secret.CredentialID
                KeyVaultName   = $KeyVaultName
                RotationDate   = Get-Date
                Status         = "Success"
            }
        }
        catch {
            [PSCustomObject]@{
                ApplicationID  = $Secret.ApplicationID
                ApplicationName = $Secret.ApplicationName
                NewSecretID    = $null
                OldSecretID    = $Secret.CredentialID
                KeyVaultName   = $KeyVaultName
                RotationDate   = Get-Date
                Status         = "Failed: $_"
            }
        }
    }
}
# Update expiring certificates
function Update-ExpiringCertificates {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$KeyVaultName,
        
        [Parameter(Mandatory)]
        [string]$KeyVaultResourceGroup
    )

    #Import-Module Microsoft.Graph.Applications, Az.KeyVault -ErrorAction Stop

    $CredentialsReport = Get-EntraIDAppCredentials    
    $NearExpiryCerts = $CredentialsReport | 
        Where-Object { $_.CredentialType -eq "Certificate" -and $_.ExpireStatus -eq "NearExpiry" }

    foreach ($Cert in $NearExpiryCerts) {
        try {
            $CertSecretName = "$($Cert.ApplicationID)-cert"
            $CurrentKvVersion = $Cert.DisplayName

            # 1. Get Key Vault versions
            $allVersions = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $CertSecretName -IncludeVersions |
                Where-Object { $_.Enabled -eq $true } |
                Sort-Object -Property Created -Descending

            if (-not $allVersions) {
                throw "No enabled versions found for secret $CertSecretName"
            }

            $latestVersion = $allVersions[0].Version

            # 2. Skip if already up-to-date
            if ($CurrentKvVersion -eq $latestVersion) {
                Write-Verbose "Application $($Cert.ApplicationID) uses current version $latestVersion"
                continue
            }

            # 3. Retrieve and validate certificate
            $KeyVaultSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $CertSecretName -Version $latestVersion -AsPlainText
            if ([string]::IsNullOrEmpty($KeyVaultSecret)) {
                throw "Certificate secret is empty"
            }

            # 4. Process certificate data
            $certBytes = $null
            $password = $null

            if ($KeyVaultSecret -match '^\s*{') {
                $json = $KeyVaultSecret | ConvertFrom-Json
                $certBytes = [Convert]::FromBase64String($json.data)
                $password = ConvertTo-SecureString $json.password -AsPlainText -Force
            }
            else {
                $certBytes = [Convert]::FromBase64String($KeyVaultSecret)
            }

            # 5. Create certificate with temp file workaround
            $tempFile = $null
            try {
                $tempFile = [System.IO.Path]::GetTempFileName()
                [System.IO.File]::WriteAllBytes($tempFile, $certBytes)

                $storageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable `
                    -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet `
                    -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet

                $NewCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
                    $tempFile,
                    $password,
                    $storageFlags
                )
            }
            finally {
                if ($tempFile -and (Test-Path $tempFile)) {
                    Remove-Item $tempFile -Force
                }
            }

            if (-not $NewCert.HasPrivateKey) {
                throw "Certificate lacks private key"
            }

            # 6. Update Entra ID application
            if ($PSCmdlet.ShouldProcess($Cert.ApplicationID, "Rotate certificate")) {
                # Get current credentials excluding the old one
                $app = Get-MgApplication -ApplicationId $Cert.ObjectID
                $keyCredentials = @($app.KeyCredentials | Where-Object { $_.KeyId -ne $Cert.CredentialID })

                # Create new credential
                $newCredential = @{
                    Type          = "AsymmetricX509Cert"
                    Usage         = "Verify"
                    Key           = $NewCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
                    DisplayName   = $latestVersion
                    StartDateTime = $NewCert.NotBefore.ToUniversalTime().ToString("o")
                    EndDateTime   = $NewCert.NotAfter.ToUniversalTime().ToString("o")
                }

                # Update application with new credentials set
                Update-MgApplication -ApplicationId $Cert.ObjectID -KeyCredentials ($keyCredentials + $newCredential)

                # Verify update
                $updatedApp = Get-MgApplication -ApplicationId $Cert.ObjectID
                $newCredentialObject = $updatedApp.KeyCredentials | 
                    Where-Object { $_.DisplayName -eq $latestVersion } |
                    Select-Object -First 1

                if (-not $newCredentialObject) {
                    throw "Failed to retrieve new certificate after update"
                }
            }

            # 7. Output results
            [PSCustomObject]@{
                ApplicationID    = $Cert.ApplicationID
                ApplicationName  = $Cert.ApplicationName
                OldCertificateID = $Cert.CredentialID
                NewCertificateID = $newCredentialObject.KeyId
                KeyVaultName     = $KeyVaultName
                OldVersion       = $CurrentKvVersion
                NewVersion       = $latestVersion
                ExpirationDate   = $NewCert.NotAfter.ToString("yyyy-MM-dd")
                Status           = "Success"
            }
        }
        catch {
            [PSCustomObject]@{
                ApplicationID    = $Cert.ApplicationID
                ApplicationName  = $Cert.ApplicationName
                OldCertificateID = $Cert.CredentialID
                NewCertificateID = $null
                KeyVaultName     = $KeyVaultName
                ExpirationDate   = $null
                Status           = "Failed: $($_.Exception.Message)"
            }
        }
    }
}








# Run rotation process for secrets
Update-ExpiringSecrets -KeyVaultName $KeyVaultName -KeyVaultResourceGroup $RGName

# Run rotation process for certificates
Update-ExpiringCertificates -KeyVaultName $KeyVaultName -KeyVaultResourceGroup $RGName 
