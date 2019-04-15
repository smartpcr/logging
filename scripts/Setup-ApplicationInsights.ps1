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
$templateFolder = Join-Path $envRootFolder "templates"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up App Insights for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
$existingAppInsights = az resource list --resource-group $bootstrapValues.appInsights.resourceGroup --name $bootstrapValues.appInsights.name | ConvertFrom-Json
if (!$existingAppInsights -or ($existingAppInsights -is [array] -and $existingAppInsights.Count -eq 0)) {
    LoginRmSubscription -SubscriptionName $bootstrapValues.global.subscriptionName
    $appInsightTemplateFile = Join-Path $templateFolder "AppInsights.json"
    New-AzureRmResourceGroupDeployment -ResourceGroupName $bootstrapValues.appInsights.resourceGroup -TemplateFile $appInsightTemplateFile `
        -appName $bootstrapValues.appInsights.name `
        -appLocation $bootstrapValues.appInsights.location `
        -appType $bootstrapValues.appInsights.applicationType
}

$instrumentationKey = az resource show -g $bootstrapValues.appInsights.resourceGroup -n $bootstrapValues.appInsights.name --resource-type "Microsoft.Insights/components" --query properties.InstrumentationKey
az keyvault secret set --vault-name $bootstrapValues.kv.name --name $bootstrapValues.appInsights.instrumentationKeySecret --value $instrumentationKey | Out-Null