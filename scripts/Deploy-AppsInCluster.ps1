param(
    [ValidateSet("dev", "int", "prod")]
    [string] $EnvName = "dev",
    [ValidateSet("xiaodong", "xd")]
    [string] $SpaceName = "xd"
)

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

$envRootFolder = Join-Path $gitRootFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up prometheus for AKS cluster in '$EnvName'..."
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az acr login --name $bootstrapValues.acr.name
az acr helm list 
Invoke-Expression "$scriptFolder\ConnectTo-AksCluster -EnvName $EnvName -AsAdmin"

$aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
$servicePrincipalPwd = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $bootstrapValues.aks.servicePrincipalPassword | ConvertFrom-Json
$kvSettings = @{
    vault_name    = $bootstrapValues.kv.name
    client_id     = $aksSpn.appId
    client_secret = $servicePrincipalPwd.value
}

$chartFolder = Join-Path $gitRootFolder "charts"

$bootstrapValues.global.apps | ForEach-Object {
    $appName = $_ 
    LogStep -Step 1 -Message "Retrieving settings for app '$appName'..."
    $appSettings = $bootstrapValues.apps[$appName]
    $dockerFile = Join-Path $gitRootFolder $AppSettings.dockerFile
    $dockerContext = [System.IO.Path]::GetDirectoryName($dockerFile)
    $acr = az acr show -g $bootstrapValues.acr.resourceGroup -n $bootstrapValues.acr.name | ConvertFrom-Json
    $localImageWithTag = "$($appSettings.image.name):$($appSettings.image.tag)"
    
    if ($appSettings.useKeyVault) {
        docker build $dockerContext -t $localImageWithTag --build-arg client_id=$kvSettings.client_id --build-arg client_secret=$kvSettings.client_secret --build-arg vault_name=$KVSettings.vault_name
    }
    else {
        docker build -t $localImageWithTag $dockerContext 
    }

    
    docker push $localImageWithTag 
    
}

LogStep -Step 2 -Message "Building docker image with tag ''..."


LogStep -Step 3 -Message "Publishing docker image..."

LogStep -Step 4 -Message "Updating chart values..."

LogStep -Step 5 -Message "Deploy chart to K8S..."