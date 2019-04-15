function EnsureCertificateInKeyVault {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $ScriptFolder
    )

    $existingCert = az keyvault certificate list --vault-name $VaultName --query "[?id=='https://$VaultName.vault.azure.net/certificates/$CertName']" | ConvertFrom-Json
    if ($existingCert) {
        LogInfo -Message "Certificate '$CertName' already exists in vault '$VaultName'"
    }
    else {
        $credentialFolder = Join-Path $ScriptFolder "credential"
        New-Item -Path $credentialFolder -ItemType Directory -Force | Out-Null
        $defaultPolicyFile = Join-Path $credentialFolder "default_policy.json"
        az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8 
        az keyvault certificate create -n $CertName --vault-name $vaultName -p @$defaultPolicyFile | Out-Null
    }
}

function DownloadCertFromKeyVault {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $EnvRootFolder
    )

    $credentialFolder = Join-Path $EnvRootFolder "credential"
    New-Item -Path $credentialFolder -ItemType Directory -Force | Out-Null
    $pfxCertFile = Join-Path $credentialFolder "$certName.pfx"
    $pemCertFile = Join-Path $credentialFolder "$certName.pem"
    $keyCertFile = Join-Path $credentialFolder "$certName.key"

    LogInfo -Message "Downloading cert '$CertName' from keyvault '$VaultName' and convert it to private key" 
    az keyvault secret download --vault-name $VaultName -n $CertName -e base64 -f $pfxCertFile
    openssl pkcs12 -in $pfxCertFile -clcerts -nodes -out $keyCertFile -passin pass:
    openssl rsa -in $keyCertFile -out $pemCertFile
}

function EnsureSshCert {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $EnvName,
        [string] $ScriptFolder
    )

    $EnvFolder = Join-Path $ScriptFolder "Env"
    $credentialFolder = Join-Path (Join-Path $EnvFolder "credential") $EnvName
    New-Item $credentialFolder -ItemType Directory -Force | Out-Null
    $certFile = Join-Path $credentialFolder $CertName
    $pubCertFile = "$certFile.pub"
    $pubCertName = "$($CertName)-pub"

    if (-not (Test-Path $pubCertFile)) {
        LogInfo -Message "File '$pubCertFile' is not found oon disk"
        $certSecret = az keyvault secret show --vault-name $VaultName --name $CertName | ConvertFrom-Json
        if (!$certSecret) {
            $pwdName = "$($CertName)-pwd"
            LogInfo -Message "SSH key password is stored in kv '$VaultName' with name '$pwdName'"
            $pwdSecret = Get-OrCreatePasswordInVault2 -VaultName $VaultName -SecretName $pwdName
            LogInfo -Message "Generating ssh key for linux vm in AKS cluster..."
            ssh-keygen -f $certFile -P $pwdSecret.value 
            
            LogInfo -Message "Put ssh private key '$CertName' to keyvault '$VaultName'"
            $certPrivateString = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($certFile))
            az keyvault secret set --vault-name $VaultName --name $CertName --value $certPrivateString | Out-Null
            LogInfo -Message "Put ssh public key '$pubCertName' to keyvault '$VaultName'"
            $certPublicString = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pubCertFile))
            az keyvault secret set --vault-name $VaultName --name $pubCertName --value $certPublicString | Out-Null
        }
        else {
            LogInfo -Message "Found ssh public key '$pubCertName' within keyvault '$VaultName'. Download it to file '$pubCertFile'"
            $pubCertSecret = az keyvault secret show --vault-name $VaultName --name $pubCertName | ConvertFrom-Json
            [System.IO.File]::WriteAllBytes($pubCertFile, [System.Convert]::FromBase64String($pubCertSecret.value))
            $privateCertSecret = az keyvault secret show --vault-name $VaultName --name $CertName | ConvertFrom-Json
            [System.IO.File]::WriteAllBytes($certFile, [System.Convert]::FromBase64String($privateCertSecret.value))
        }
    }
    else {
        LogInfo -Message "ssh public key file found at '$pubCertFile'"
    }
}