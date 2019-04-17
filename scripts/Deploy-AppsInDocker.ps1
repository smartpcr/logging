param(
    [string] $EnvName = "dev",
    [string] $SpaceName = "xd"
)

function DeployApp {
    param(
        [object] $AppSettings,
        [object] $KVSettings 
    )

    $imageName = $AppSettings.image.name
    $imageTag = $AppSettings.image.tag
    RemoveContainerByImageName -ImageName "$($imageName):$($imageTag)"

<<<<<<< HEAD
    $dockerFile = Join-Path $gitRootFolder $AppSettings.dockerFile
=======
    $dockerFile = Join-Path $gitRootFolder $AppSetting.dockerFile

    # check kv setting and inject secret as environment variables 
    $dockerSettings = Get-Content $dockerFile -Raw | ConvertFrom-Yaml2
    

>>>>>>> e1b928639bb91af6bbe1319d2b157ab765daabdb
    $dockerContext = [System.IO.Path]::GetDirectoryName($dockerFile)
    if ($AppSettings.useKeyVault) {
        docker build $dockerContext -t "$($imageName):$($imageTag)" --build-arg client_id=$kvSettings.client_id --build-arg client_secret=$kvSettings.client_secret --build-arg vault_name=$KVSettings.vault_name
    }
    else {
        docker build -t "$($imageName):$($imageTag)" $dockerContext 
    }

    docker run -d --name $imageName -p "$($AppSettings.port):80" --net=$net "$($imageName):$($imageTag)"
}

function RemoveContainerByImageName {
    param([string] $ImageName)

    $existingContainer = $(docker.exe ps -a -q --filter ancestor=$ImageName)
    if ($existingContainer) {
        Write-Host "`tRemoving existing container for image '$ImageName'..." -ForegroundColor Yellow
        docker.exe container stop $existingContainer | Out-Null
        docker.exe container rm $existingContainer | Out-Null
    }
}


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
$localSettingFile = Join-Path $envRootFolder "local.yaml"
$settings = Get-Content $localSettingFile -Raw | ConvertFrom-Yaml2
if ($SpaceName) {
    $spaceSettingFile = Join-Path $envRootFolder "local.$SpaceName.yaml"
    if (Test-Path $spaceSettingFile) {
        $spaceOverrideValues = Get-Content $spaceSettingFile -Raw | ConvertFrom-Yaml2
        Copy-YamlObject -fromObj $spaceOverrideValues -toObj $settings
    }
}
$net = $settings.global.network
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder -SpaceName $SpaceName
$aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
$servicePrincipalPwd = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $bootstrapValues.aks.servicePrincipalPassword | ConvertFrom-Json
$kvSettings = @{
    vault_name = $bootstrapValues.kv.name
    client_id  = $aksSpn.appId
    client_secret = $servicePrincipalPwd.value
}

if ($settings.global.apps) {
    $settings.global.apps | ForEach-Object {
        $appName = $_ 
        if ($settings.ContainsKey($appName)) {
            $appSettings = $settings[$appName]
            DeployApp -AppSettings $appSettings -KVSettings $kvSettings
        }
        
    }
}
