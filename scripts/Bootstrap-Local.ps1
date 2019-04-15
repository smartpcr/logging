param(
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
$localSettingFile = Join-Path $envRootFolder "local.yaml"
$localSettings = Get-Content $localSettingFile -Raw | ConvertFrom-Yaml2
if ($SpaceName) {
    $spaceSettingFile = Join-Path $envRootFolder "local.$SpaceName.yaml"
    if (Test-Path $spaceSettingFile) {
        $spaceOverrideValues = Get-Content $spaceSettingFile -Raw | ConvertFrom-Yaml2
        Copy-YamlObject -fromObj $spaceOverrideValues -toObj $localSettings
    }
}

if ($localSettings.global.network) {
    Write-Host "Create docker network '$($localSettings.global.network)'..." -ForegroundColor Green
    docker network create $localSettings.global.network 
}

if ($localSettings.global.sharedDrive) {
    Write-Host "Make host folder '$($localSettings.global.sharedDrive)' is shared with docker containers ..." -ForegroundColor Green
    docker run -v "$($localSettings.global.sharedDrive):/etc/test" alpine 
}

$confFolder = Join-Path (Join-Path (Join-Path (Join-Path $gitRootFolder "deploy") "docker") "infra") "conf"
$hostRunFolder = Join-Path $localSettings.global.sharedDrive "run"
if (-not (Test-Path $hostRunFolder)) {
    New-Item -Path $hostRunFolder -ItemType Directory -Force | Out-Null
}
$net = $localSettings.global.network

if ($localSettings.global.installInfluxDb) {
    $influxdbPort = $localSettings.influxDb.port
    Write-Host "Deploying 'influxdb' on port '$influxdbPort'..." -ForegroundColor Green 
    $hostInfluxFolder = Join-Path $localSettings.global.sharedDrive $localSettings.influxDb.sharedFolder
    if (Test-Path $hostInfluxFolder) {
        Remove-Item -Path $hostInfluxFolder -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
    New-Item -Path $hostInfluxFolder -ItemType Directory | Out-Null
    $influxdbConfFile = Join-Path $confFolder "influxdb.conf"
    Copy-Item $influxdbConfFile -Destination $hostInfluxFolder -Force | Out-Null
    $maxDataSize = $localSettings.influxDb.maxSize
    docker.exe volume create --driver local --name influxdb --opt o=size=$maxDataSize --opt device=tmpfs --opt type=tmpfs 
    
    docker.exe run -d --name influxdb --net=$net -p "$($influxdbPort):8086" `
        -v "$(Join-Path $hostInfluxFolder "influxdb.conf"):/etc/influxdb/influxdb.conf:ro" `
        -v "influxdb:/var/lib/influxdb:rw" `
        influxdb -config /etc/influxdb/influxdb.conf 
}

if ($localSettings.global.installTelegraf) {
    Write-Host "Deploying telegraf..." -ForegroundColor Green
    $hostTelegrafFolder = Join-Path $localSettings.global.sharedDrive $localSettings.telegraf.sharedFolder
    if (Test-Path $hostTelegrafFolder) {
        Remove-Item -Recurse -Force $hostTelegrafFolder -ErrorAction SilentlyContinue
    }
    New-Item -Path $hostTelegrafFolder -ItemType Directory | Out-Null
    $telegrafSourceConfFile = Join-Path $confFolder "telegraf.conf"
    $telegrafConfFile = Join-Path $hostTelegrafFolder "telegraf.conf"
    Copy-Item -Path $telegrafSourceConfFile -Destination $telegrafConfFile
    $telegrafSocketFolder = Join-Path $hostRunFolder "telegraf"
    if (Test-Path $telegrafSocketFolder) {
        Remove-Item -Recurse -Force $telegrafSocketFolder -ErrorAction SilentlyContinue
    }
    New-Item -Path $telegrafSocketFolder -ItemType Directory -Force | Out-Null

    docker.exe run -d --name telegraf --net=$net `
        -v "$($telegrafConfFile):/etc/telegraf/telegraf.conf:ro" `
        -v "$($telegrafSocketFolder):/var/run/telegraf:rw" `
        -v "/var/run/docker.sock:/var/run/docker.sock" `
        telegraf 
}

if ($localSettings.global.installChronograf) {
    if (!$localSettings.global.installInfluxDb) {
        throw "Chronograf is dependent on influxdb, please enable influxdb installation on your settings."
    }

    $chronografPort = $localSettings.chronograf.port
    Write-Host "Deploy chronograf on '$chronografPort'..." -ForegroundColor Green
    $influxdbUrl = $localSettings.chronograf.influxDbUrl
    docker run -d --name chronograf -p "$($chronografPort):8888" --net=$net chronograf --influxdb-url=$influxdbUrl
}

if ($localSettings.global.installFluentd) {
    $hostFluentDrive = Join-Path $localSettings.global.sharedDrive $localSettings.fluentd.sharedFolder 
    if (Test-Path $hostFluentDrive) {
        Remove-Item -Recurse -Force $hostFluentDrive -ErrorAction SilentlyContinue
    }
    New-Item -Path $hostFluentDrive -ItemType Directory -Force | Out-Null
    $fluentdPort = $localSettings.fluentd.port
    $fluentdUdpPort = $localSettings.fluentd.udpPort
    Write-Host "Deploy fluentd on '$fluentdPort'..." -ForegroundColor Green

    docker run -d --name fluentd -p "$($fluentdPort):24224" -p "$($fluentdUdpPort):24224/udp" -v "$($hostFluentDrive):/fluentd/log:rw" --net=$net fluent/fluentd
}

if ($localSettings.global.installGrafana) {
    $grafanaPort = $localSettings.grafana.port
    Write-Host "Deploy grafana on port '$grafanaPort'..." -ForegroundColor Green

    docker run -d --name=grafana -p "$($grafanaPort):3000" --net=$net grafana/grafana
}

if ($localSettings.installPrometheus) {
    $prometheusPort = $localSettings.prometheus.port
    Write-Host "Deploy prometheus on port '$prometheusPort'..." -ForegroundColor Green
    $hostPrometheusDrive = Join-Path $localSettings.global.sharedDrive $localSettings.prometheus.sharedFolder
    if (Test-Path $hostPrometheusDrive) {
        Remove-Item -Recurse -Force $hostPrometheusDrive -ErrorAction SilentlyContinue
    }
    New-Item -Path $hostPrometheusDrive -ItemType Directory -Force | Out-Null
    $srcPrometheusConfFile = Join-Path $confFolder "prometheus.yml"
    $prometheusConfFile = Join-Path $hostPrometheusDrive "prometheus.yml"
    Copy-Item -Path $srcPrometheusConfFile -Destination $prometheusConfFile -Force | Out-Null

    docker run -d --name prometheus -p "$($prometheusPort):9090" -v "$($hostPrometheusDrive)/prometheus.yml:/etc/prometheus/prometheus.yml:ro" prom/prometheus 
}