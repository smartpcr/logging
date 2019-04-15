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

$aksDeployFolder = Join-Path (Join-Path $gitRootFolder "deploy") "aks"
$manifestFile = Join-Path (Join-Path $aksDeployFolder "prom") "manifest-all.yaml"
if (-not (Test-Path $manifestFile)) {
    throw "Unable to find prometheus manifest file '$manifestFile'"
}
kubectl.exe apply -f $manifestFile

Write-Host "Browse grafana dashboard..." -ForegroundColor Green
$GrafanaPodName = $(kubectl get pods --namespace monitoring -l "app=grafana,component=core" -o jsonpath="{.items[0].metadata.name}")
Start-Process powershell "kubectl port-forward --namespace monitoring $GrafanaPodName 3000:3000"

Write-Host "Browse prometheus web ui..." -ForegroundColor Green
$prometheusPodName=$(kubectl get pods --namespace monitoring -l "app=prometheus,component=core" -o jsonpath="{.items[0].metadata.name}")
Start-Process powershell "kubectl  port-forward --namespace monitoring $prometheusPodName 9090"

Write-Host "Browse alert manager web ui..." -ForegroundColor Green
$alertManagerPodName=$(kubectl get pods --namespace monitoring -l "app=alertmanager" -o jsonpath="{.items[0].metadata.name}")
Start-Process powershell "kubectl port-forward --namespace monitoring $alertManagerPodName 9093"
