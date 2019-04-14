
function New-CertificateAsSecret {
    param(
        [string] $CertName,
        [string] $VaultName 
    )

    $cert = New-SelfSignedCertificate `
        -CertStoreLocation "cert:\CurrentUser\My" `
        -Subject "CN=$CertName" `
        -KeySpec KeyExchange `
        -HashAlgorithm "SHA256" `
        -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    $certPwdSecretName = "$CertName-pwd"
    $spCertPwdSecret = Get-OrCreatePasswordInVault -vaultName $VaultName -secretName $certPwdSecretName
    $pwd = $spCertPwdSecret.SecretValue
    $pfxFilePath = [System.IO.Path]::GetTempFileName() 
    Export-PfxCertificate -cert $cert -FilePath $pfxFilePath -Password $pwd -ErrorAction Stop | Out-Null
    $Bytes = [System.IO.File]::ReadAllBytes($pfxFilePath)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $JSONBlob = @{
        data     = $Base64
        dataType = 'pfx'
        password = $spCertPwdSecret.SecretValueText
    } | ConvertTo-Json
    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($JSONBlob)
    $Content = [System.Convert]::ToBase64String($ContentBytes)
    $SecretValue = ConvertTo-SecureString -String $Content -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $VaultName -Name $CertName -SecretValue $SecretValue | Out-Null

    Remove-Item $pfxFilePath
    Remove-Item "cert:\\CurrentUser\My\$($cert.Thumbprint)"

    return $cert
}

function New-CertificateAsSecret2 {
    param(
        [string] $ScriptFolder,
        [string] $CertName,
        [string] $VaultName 
    )

    $certPwdSecretName = "$CertName-pwd"
    $spCertPwdSecret = Get-OrCreatePasswordInVault2 -vaultName $VaultName -SecretName $certPwdSecretName
    $password = $spCertPwdSecret.value 

    $certPrivateKeyFile = "$ScriptFolder/credential/$($CertName)"
    $certPublicKeyFile = "$ScriptFolder/credential/$($CertName).pub"
    $pemFilePath = "$ScriptFolder/credential/$($CertName).pem"
    
    ssh-keygen -f $certPrivateKeyFile -P $password
    $certPemString = ssh-keygen -f $certPublicKeyFile -e -m pem 
    $certPemString | Out-File $pemFilePath

    $privateKeyBytes = [System.IO.File]::ReadAllBytes($certPrivateKeyFile)
    $privateKeyText = [System.Convert]::ToBase64String($privateKeyBytes)
    $privateKeyJson = @{
        data     = $privateKeyText
        dataType = 'pem'
        password = $password
    } | ConvertTo-Json
    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($privateKeyJson)
    $Content = [System.Convert]::ToBase64String($ContentBytes)
    az keyvault secret set --vault-name $VaultName --name $CertName --value $Content --query $env:out_null
    az keyvault certificate import --vault-name $VaultName --name $CertName --file $certPrivateKeyFile --password $password

    # $publicKeyBytes = [System.IO.File]::ReadAllBytes($certPublicKeyFile)
    # $publicKeyText = [System.Convert]::ToBase64String($publicKeyBytes)
    $publicKeySecretName = "$($CertName)-pub"
    # az keyvault secret set --vault-name $VaultName --name $publicKeySecretName --value $publicKeyText --query $env:out_null
    az keyvault certificate import --name $publicKeySecretName --file $certPublicKeyFile --vault-name $VaultName
    
    # $pemKeyBytes = [System.Text.Encoding]::UTF8.GetBytes($certPemString)
    # $pemKeyContent = [System.Convert]::ToBase64String($pemKeyBytes)
    $pemKeySecretName = "$($CertName)-pem"
    
    # az keyvault secret set --vault-name $VaultName --name $pemKeySecretName --value $pemKeyContent --query $env:out_null
    az keyvault certificate import --name $pemKeySecretName --file $pemFilePath --vault-name $VaultName
}

function Install-CertFromVaultSecret {
    param(
        [string] $VaultName,
        [string] $CertSecretName 
    )
    $certSecret = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $CertSecretName 

    $kvSecretBytes = [System.Convert]::FromBase64String($certSecret.SecretValueText)
    $certDataJson = [System.Text.Encoding]::UTF8.GetString($kvSecretBytes) | ConvertFrom-Json
    $pfxBytes = [System.Convert]::FromBase64String($certDataJson.data)
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bxor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    $pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2

    $certPwdSecretName = "$CertSecretName-pwd"
    $certPwdSecret = Get-OrCreatePasswordInVault -vaultName $VaultName -secretName $certPwdSecretName

    $pfx.Import($pfxBytes, $certPwdSecret.SecretValue, $flags)
    $thumbprint = $pfx.Thumbprint

    $certAlreadyExists = Test-Path Cert:\CurrentUser\My\$thumbprint
    if (!$certAlreadyExists) {
        $x509Store = new-object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList My, CurrentUser
        $x509Store.Open('ReadWrite')
        $x509Store.Add($pfx)
    }

    return $pfx 
}