
function SetupGlobalEnvironmentVariables() {
    param(
        [string] $ScriptFolder
    )

    $ErrorActionPreference = "Stop"
    $scriptFolderName = Split-Path $ScriptFolder -Leaf
    if ($null -eq $scriptFolderName -or $scriptFolderName -ne "Scripts") {
        throw "Invalid script folder: '$ScriptFolder'"
    }
    $logFolder = Join-Path $ScriptFolder "log"
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    $timeString = (Get-Date).ToString("yyyy-MM-dd-HHmmss")
    $logFile = Join-Path $logFolder "$($timeString).log"
    $env:LogFile = $logFile
}

function LogVerbose() {
    param(
        [string] $Message,
        [int] $IndentLevel = 0)

    if (-not (Test-Path $env:LogFile)) {
        New-Item -Path $env:LogFile -ItemType File -Force | Out-Null
    }

    $timeString = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $formatedMessage = ""
    for ($i = 0; $i -lt $IndentLevel; $i++) {
        $formatedMessage = "`t" + $formatedMessage
    }
    $formatedMessage += "$timeString $Message"
    Add-Content -Path $env:LogFile -Value $formatedMessage
}

function LogInfo() {
    param(
        [string] $Message,
        [int] $IndentLevel = 1
    )

    $formatedMessage = ""
    for ($i = 0; $i -lt $IndentLevel; $i++) {
        $formatedMessage = "`t" + $formatedMessage
    }
    $formatedMessage += $Message
    LogVerbose -Message $formatedMessage -IndentLevel $IndentLevel

    Write-Host $formatedMessage -ForegroundColor Yellow
}

function LogTitle() {
    param(
        [string] $Message
    )

    Write-Host "`n"
    Write-Host "`t`t***** $Message *****" -ForegroundColor Green
    Write-Host "`n"
}

function LogStep() {
    param(
        [int] $Step,
        [string] $Message
    )

    $formatedMessage = "$Step) $Message"
    LogVerbose -Message $formatedMessage
    Write-Host "$formatedMessage" -ForegroundColor Green
}

function Get-OrCreatePasswordInVault2 { 
    param(
        [string] $VaultName, 
        [string] $SecretName
    )

    $secretsFound = az keyvault secret list `
        --vault-name $VaultName `
        --query "[?id=='https://$($VaultName).vault.azure.net/secrets/$SecretName']" | ConvertFrom-Json
    if (!$secretsFound) {
        $prng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
        $bytes = New-Object Byte[] 30
        $prng.GetBytes($bytes)
        $password = [System.Convert]::ToBase64String($bytes) + "!@1wW" #  ensure we meet password requirements
        az keyvault secret set --vault-name $VaultName --name $SecretName --value $password
        $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
        return $res 
    }

    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    if ($res) {
        return $res
    }
}


function Get-OrCreateServicePrincipalUsingPassword {
    param(
        [string] $ServicePrincipalName,
        [string] $ServicePrincipalPwdSecretName,
        [string] $VaultName
    )

    $servicePrincipalPwd = Get-OrCreatePasswordInVault2 -VaultName $VaultName -secretName $ServicePrincipalPwdSecretName
    $spFound = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    if ($spFound) {
        LogInfo -Message "Service principal '$ServicePrincipalName' is already installed, reset its password..."
        az ad sp credential reset --name $ServicePrincipalName --password $servicePrincipalPwd.value 
        return $spFound
    }

    LogInfo -Message "Creating service principal '$ServicePrincipalName' with password..."
    az ad sp create-for-rbac `
        --name $ServicePrincipalName `
        --password $($servicePrincipalPwd.value) | Out-Null
    $sp = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    return $sp 
}

function Get-OrCreateAksServicePrincipal {
    param(
        [string] $ServicePrincipalName,
        [string] $ServicePrincipalPwdSecretName,
        [string] $VaultName,
        [string] $EnvRootFolder,
        [string] $EnvName
    )

    $templatesFolder = Join-Path $EnvRootFolder "templates"
    $spnAuthJsonFile = Join-Path $templatesFolder "aks-spn-auth.json"
    $servicePrincipalPwd = Get-OrCreatePasswordInVault2 -VaultName $VaultName -secretName $ServicePrincipalPwdSecretName
    $spFound = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    if ($spFound) {
        az ad sp credential reset --name $ServicePrincipalName --password $servicePrincipalPwd.value 
        $aksSpn = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
        az ad app update --id $aksSpn.appId --required-resource-accesses $spnAuthJsonFile | Out-Null
        return $aksSpn
    }

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvRootFolder
    $rgName = $bootstrapValues.aks.resourceGroup
    $azAccount = az account show | ConvertFrom-Json
    $subscriptionId = $azAccount.id
    $scopes = "/subscriptions/$subscriptionId/resourceGroups/$($rgName)"
    
    LogInfo -Message "Granting spn '$ServicePrincipalName' 'Contributor' role to resource group '$rgName'"
    az ad sp create-for-rbac `
        --name $ServicePrincipalName `
        --password $($servicePrincipalPwd.value) `
        --role="Contributor" `
        --scopes=$scopes | Out-Null
    
    $aksSpn = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json

    LogInfo -Message "Grant required resource access for aad app..."
    az ad app update --id $aksSpn.appId --required-resource-accesses $spnAuthJsonFile | Out-Null
    az ad app update --id $aksSpn.appId --reply-urls "http://$($ServicePrincipalName)" | Out-Null
    
    return $aksSpn 
}


function Get-OrCreateAksClientApp {
    param(
        [string] $EnvRootFolder,
        [string] $EnvName
    )

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvRootFolder
    $ClientAppName = $bootstrapValues.aks.clientAppName

    $aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
    if (!$aksSpn) {
        throw "Cannot create client app when server app with name '$($bootstrapValues.aks.servicePrincipal)' is not found!"
    }

    LogInfo -Message "Retrieving replyurl from server app..."
    $serverAppReplyUrls = $aksSpn.replyUrls
    $clientAppRedirectUrl = $serverAppReplyUrls
    if ($serverAppReplyUrls -is [array] -and ([array]$serverAppReplyUrls).Length -gt 0) {
        $clientAppRedirectUrl = [array]$serverAppReplyUrls[0]
    }

    $spFound = az ad app list --display-name $ClientAppName | ConvertFrom-Json
    if ($spFound -and $spFound -is [array]) {
        if ([array]$spFound.Count -gt 1) {
            throw "Duplicated client app found for '$ClientAppName'"
        }
    }
    if ($spFound) {
        LogInfo -Message "Client app '$ClientAppName' already exists."
        az ad app update --id $spFound.appId --reply-urls "$clientAppRedirectUrl"
        return $sp
    }
    
    LogInfo -Message "Creating client app '$ClientAppName'..."
    LogInfo -Message "Granting client app '$ClientAppName' access to server app '$($bootstrapValues.aks.servicePrincipal)'"
    $resourceAccess = "[{`"resourceAccess`": [{`"id`": `"318f4279-a6d6-497a-8c69-a793bda0d54f`", `"type`": `"Scope`"}],`"resourceAppId`": `"$($aksSpn.appId)`"}]" 
    $currentEnvFolder = Join-Path $EnvRootFolder $EnvName
    $clientAppResourceAccessJsonFile = Join-Path $currentEnvFolder "aks-client-auth.json"
    $resourceAccess | Out-File $clientAppResourceAccessJsonFile -Encoding ascii

    az ad app create `
        --display-name $ClientAppName `
        --native-app `
        --reply-urls "$clientAppRedirectUrl" `
        --required-resource-accesses @$clientAppResourceAccessJsonFile | Out-Null
    
    $sp = az ad sp list --display-name $ClientAppName | ConvertFrom-Json
    return $sp 
}

function LoginAzureAsUser2 {
    param (
        [string] $SubscriptionName
    )
    
    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount -or $azAccount.name -ine $SubscriptionName) {
        az login | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }

    $currentAccount = az account show | ConvertFrom-Json
    return $currentAccount
}

function LoginAsServicePrincipal {
    param (
        [string] $EnvName = "dev",
        [string] $ScriptFolder
    )
    
    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $ScriptFolder
    $vaultName = $bootstrapValues.kv.name
    $spnName = $bootstrapValues.global.servicePrincipal
    $certName = $spnName
    $tenantId = $bootstrapValues.global.tenantId

    $privateKeyFilePath = "$ScriptFolder/credential/$certName.key"
    if (-not (Test-Path $privateKeyFilePath)) {
        LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName
        DownloadCertFromKeyVault -VaultName $vaultName -CertName $certName -EnvRootFolder $ScriptFolder
    }
    
    LogInfo -Message "Login as service principal '$spnName'"
    az login --service-principal -u "http://$spnName" -p $privateKeyFilePath --tenant $tenantId | Out-Null
}
