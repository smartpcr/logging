<#
    this script retrieve settings based on target environment
    1) create azure resource group
    2) create key vault
    3) create certificate and add to key vault
    4) create service principle with cert auth
    5) grant permission to service principle
        a) key vault
        b) resource group
#>
param([string] $EnvName = "dev")


$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"

Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setting Up Service Principal for Environment $EnvName" 

$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $envFolder

# login and set subscription 
LogStep -Step 1 -Message "Login to azure and set subscription to '$($bootstrapValues.global.subscriptionName)'..." 
$azureAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName


# create resource group 
LogStep -Step 2 -Message "Creating resource group '$($bootstrapValues.global.resourceGroup)' at location '$($bootstrapValues.global.location)'..."
$rgGroups = az group list --query "[?name=='$($bootstrapValues.global.resourceGroup)']" | ConvertFrom-Json
if (!$rgGroups -or $rgGroups.Count -eq 0) {
    LogInfo -Message "Creating resource group '$($bootstrapValues.global.resourceGroup)' in location '$($bootstrapValues.global.location)'"
    az group create --name $bootstrapValues.global.resourceGroup --location $bootstrapValues.global.location | Out-Null
}

# create key vault 
LogStep -Step 3 -Message "Creating key vault '$($bootstrapValues.kv.name)' within resource group '$($bootstrapValues.kv.resourceGroup)' at location '$($bootstrapValues.kv.location)'..."
$kvrg = az group list --query "[?name=='$($bootstrapValues.kv.resourceGroup)']" | ConvertFrom-Json
if (!$kvrg) {
    az group create --name $bootstrapValues.kv.resourceGroup --location $bootstrapValues.kv.location | Out-Null
}
$kvs = az keyvault list --resource-group $bootstrapValues.kv.resourceGroup --query "[?name=='$($bootstrapValues.kv.name)']" | ConvertFrom-Json
if ($kvs.Count -eq 0) {
    LogInfo -Message "Creating Key Vault $($bootstrapValues.kv.name)..." 
    
    az keyvault create `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --name $($bootstrapValues.kv.name) `
        --sku standard `
        --location $bootstrapValues.global.location `
        --enabled-for-deployment $true `
        --enabled-for-disk-encryption $true `
        --enabled-for-template-deployment $true | Out-Null
}
else {
    LogInfo -Message "Key vault $($bootstrapValues.kv.name) is already created" 
}

# create service principal (SPN) for cluster provision
LogStep -Step 4 -Message "Creating service principal '$($bootstrapValues.global.servicePrincipal)'..." 
$sp = az ad sp list --display-name $bootstrapValues.global.servicePrincipal | ConvertFrom-Json
if (!$sp) {
    LogInfo -Message "Creating service principal with name '$($bootstrapValues.global.servicePrincipal)'..." 

    $certName = $($bootstrapValues.global.servicePrincipal)
    EnsureCertificateInKeyVault -VaultName $($bootstrapValues.kv.name) -CertName $certName -ScriptFolder $envFolder
    
    az ad sp create-for-rbac -n $($bootstrapValues.global.servicePrincipal) --role contributor --keyvault $($bootstrapValues.kv.name) --cert $certName | Out-Null
    $sp = az ad sp list --display-name $($bootstrapValues.global.servicePrincipal) | ConvertFrom-Json
    LogInfo -Message "Granting spn '$($bootstrapValues.global.servicePrincipal)' 'contributor' role to subscription" 
    az role assignment create --assignee $sp.appId --role Contributor --scope "/subscriptions/$($azureAccount.id)" | Out-Null

    LogInfo -Message "Granting spn '$($bootstrapValues.global.servicePrincipal)' permissions to keyvault '$($bootstrapValues.kv.name)'" 
    az keyvault set-policy `
        --name $($bootstrapValues.kv.name) `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $sp.objectId `
        --spn $sp.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete | Out-Null
}
else {
    LogInfo -Message "Service principal '$($bootstrapValues.global.servicePrincipal)' already exists." 
}


if ($bootstrapValues.global.aks -eq $true) {
    LogStep -Step 5 -Message "Ensuring AKS service principal '$($bootstrapValues.aks.servicePrincipal)' is created..." 
    $aksrg = az group list --query "[?name=='$($bootstrapValues.aks.resourceGroup)']" | ConvertFrom-Json
    if (!$aksrg) {
        az group create --name $bootstrapValues.aks.resourceGroup --location $bootstrapValues.aks.location | Out-Null
    }

    Get-OrCreateAksServicePrincipal `
        -ServicePrincipalName $bootstrapValues.aks.servicePrincipal `
        -ServicePrincipalPwdSecretName $bootstrapValues.aks.servicePrincipalPassword `
        -VaultName $($bootstrapValues.kv.name) `
        -EnvRootFolder $envFolder `
        -EnvName $EnvName | Out-Null
    
    $aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
    LogInfo -Message "set groupMembershipClaims to [All] to spn '$($bootstrapValues.aks.servicePrincipal)'"
    $aksServerApp = az ad app show --id $aksSpn.appId | ConvertFrom-Json
    if ($aksServerApp.additionalProperties -and $aksServerApp.additionalProperties.groupMembershipClaims -eq "All") {
        LogInfo -Message "AKS server app manifest property 'groupMembershipClaims' is already set to true"
    }
    else {
        az ad app update --id $aksSpn.appId --set groupMembershipClaims=All | Out-Null
    }
    
    # write to values.yaml
    LogInfo -Message "Granting spn '$($bootstrapValues.aks.servicePrincipal)' 'Contributor' role to resource group '$($bootstrapValues.aks.resourceGroup)'" 
    az role assignment create `
        --assignee $aksSpn.appId `
        --role Contributor `
        --resource-group $bootstrapValues.aks.resourceGroup | Out-Null
    LogInfo -Message "Granting spn '$($bootstrapValues.aks.servicePrincipal)' permissions to keyvault '$($bootstrapValues.kv.name)'" 
    az keyvault set-policy `
        --name $($bootstrapValues.kv.name) `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $aksSpn.objectId `
        --spn $aksSpn.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete | Out-Null

    LogInfo -Message "Ensuring AKS Client App '$($bootstrapValues.aks.clientAppName)' is created..."
    Get-OrCreateAksClientApp -EnvRootFolder $envFolder -EnvName $EnvName | Out-Null
}

# connect as service principal 
# LoginAsServicePrincipal -EnvName $EnvName -ScriptFolder $envFolder
LogTitle "Remember to manually grant aad app request before creating aks cluster!"