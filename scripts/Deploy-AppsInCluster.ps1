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
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
Invoke-Expression "$scriptFolder\ConnectTo-AksCluster -EnvName $EnvName -AsAdmin"


LogStep -Step 1 -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
$azAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName 

LogStep -Step 2 -Message "Building docker image with tag ''..."

LogStep -Step 3 -Message "Publishing docker image..."

LogStep -Step 4 -Message "Updating chart values..."

LogStep -Step 5 -Message "Deploy chart to K8S..."