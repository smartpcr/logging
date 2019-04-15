param(
    [string] $EnvName = "dev"
)


$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

$envFolder = Join-Path $gitRootFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

LogStep -Step 1 -Message "Delete AKS cluster '$($bootstrapValues.aks.clusterName)', this can take up to 10 min..."
az aks delete --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName -y

LogStep -Step 2 -Message "Delete AAD app and service principal associated with AKS..."
$clientAadApp = az ad app list --display-name $bootstrapValues.aks.clientAppName | ConvertFrom-Json
if ($clientAadApp) {
    LogInfo -Message "Remove client aad app '$($bootstrapValues.aks.clientAppName)'..."
    az ad app delete --id $clientAadApp.appId
}
else {
    LogInfo -Message "AAD client app '$($bootstrapValues.aks.clientAppName)' is already removed."
}
$aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
if ($aksSpn) {
    LogInfo -Message "Remove aks service principal '$bootstrapValues.aks.servicePrincipal'..."
    az ad sp delete --id $aksSpn.appId 
}
else {
    LogInfo -Message "AKS service principal '$($bootstrapValues.aks.servicePrincipal)' is already removed."
}

LogStep -Step 3 -Message "Remove resource group '$($bootstrapValues.aks.resourceGroup)'..."
az group delete -g $bootstrapValues.aks.resourceGroup -y