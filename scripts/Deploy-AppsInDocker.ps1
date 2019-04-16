param(
    [string] $SpaceName = "xd"
)

function DeployApp {
    param([object] $AppSetting)

    $imageName = $AppSetting.image.name
    $imageTag = $AppSetting.image.tag
    RemoveContainerByImageName -ImageName "$($imageName):$($imageTag)"

    $dockerFile = Join-Path $gitRootFolder $AppSetting.dockerFile

    # check kv setting and inject secret as environment variables 
    $dockerSettings = Get-Content $dockerFile -Raw | ConvertFrom-Yaml2
    

    $dockerContext = [System.IO.Path]::GetDirectoryName($dockerFile)
    docker build -t "$($imageName):$($imageTag)" $dockerContext
    docker run -d --name $imageName -p "$($AppSetting.port):80" --net=$net "$($imageName):$($imageTag)"
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

if ($settings.global.apps) {
    $settings.global.apps | ForEach-Object {
        $appName = $_ 
        if ($settings.ContainsKey($appName)) {
            $appSetting = $settings[$appName]
            DeployApp -AppSetting $appSetting
        }
        
    }
}
