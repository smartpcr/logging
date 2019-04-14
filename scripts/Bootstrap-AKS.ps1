param([string] $EnvName = "dev")

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

$envRootFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder

LogTitle -Message "Setting up App Insights for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and retrieve env settings..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

& $scriptFolder\Setup-ServicePrincipal2.ps1 -EnvName $EnvName 
& $scriptFolder\Setup-ContainerRegistry.ps1 -EnvName $EnvName
if ($bootstrapValues.global.appInsights) {
    & $scriptFolder\Setup-ApplicationInsights.ps1 -EnvName $EnvName
}
if ($bootstrapValues.global.mongoDb) {
    & $scriptFolder\Setup-CosmosDb.ps1 -EnvName $EnvName
}

& $scriptFolder\Setup-AksCluster.ps1 -EnvName $EnvName
