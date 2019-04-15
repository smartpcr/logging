param(
    [string] $SpaceName = "xd"
)

function EnsureFolder {
    param(
        [string] $FolderPath,
        [switch] $CleanFolder
    )

    if (Test-Path $FolderPath) {
        if ($CleanFolder) {
            Remove-Item -Recurse -Force $FolderPath -ErrorAction SilentlyContinue | Out-Null
        }
    }
    New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
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

if ($settings.global.network) {
    Write-Host "Create docker network '$($settings.global.network)'..." -ForegroundColor Green
    docker network create $settings.global.network 
}

if ($settings.global.sharedDrive) {
    Write-Host "Make host folder '$($settings.global.sharedDrive)' is shared with docker containers ..." -ForegroundColor Green
    docker run -v "$($settings.global.sharedDrive):/etc/test" alpine 
}

$confFolder = Join-Path (Join-Path (Join-Path (Join-Path $gitRootFolder "deploy") "docker") "infra") "conf"
$hostRunFolder = Join-Path $settings.global.sharedDrive "run"
if (-not (Test-Path $hostRunFolder)) {
    New-Item -Path $hostRunFolder -ItemType Directory -Force | Out-Null
}
$net = $settings.global.network

if ($settings.global.bootstrap.installInfluxDb) {
    $influxdbPort = $settings.influxDb.port
    $imageName = $settings.influxDb.image 
    RemoveContainerByImageName -ImageName $imageName
    
    Write-Host "Deploying 'influxdb' on port '$influxdbPort'..." -ForegroundColor Green 
    $hostInfluxFolder = Join-Path $settings.global.sharedDrive $settings.influxDb.sharedFolder
    EnsureFolder -FolderPath $hostInfluxFolder -CleanFolder
    $influxdbConfFile = Join-Path $confFolder "influxdb.conf"
    Copy-Item $influxdbConfFile -Destination $hostInfluxFolder -Force | Out-Null
    $maxDataSize = $settings.influxDb.maxSize
    docker.exe volume create --driver local --name influxdb --opt o=size=$maxDataSize --opt device=tmpfs --opt type=tmpfs 
    
    docker.exe run -d --name influxdb --net=$net -p "$($influxdbPort):8086" `
        -v "$(Join-Path $hostInfluxFolder "influxdb.conf"):/etc/influxdb/influxdb.conf:ro" `
        -v "influxdb:/var/lib/influxdb:rw" `
        -config /etc/influxdb/influxdb.conf $imageName
}

if ($settings.global.bootstrap.installTelegraf) {
    Write-Host "Deploying telegraf..." -ForegroundColor Green
    $imageName = $settings.telegraf.image
    RemoveContainerByImageName -ImageName $imageName

    $hostTelegrafFolder = Join-Path $settings.global.sharedDrive $settings.telegraf.sharedFolder
    EnsureFolder -FolderPath $hostTelegrafFolder -CleanFolder
    $telegrafSourceConfFile = Join-Path $confFolder "telegraf.conf"
    $telegrafConfFile = Join-Path $hostTelegrafFolder "telegraf.conf"
    Copy-Item -Path $telegrafSourceConfFile -Destination $telegrafConfFile
    $telegrafSocketFolder = Join-Path $hostRunFolder "telegraf"
    EnsureFolder -FolderPath $telegrafSocketFolder -CleanFolder
    
    docker.exe run -d --name telegraf --net=$net `
        -v "$($telegrafConfFile):/etc/telegraf/telegraf.conf:ro" `
        -v "$($telegrafSocketFolder):/var/run/telegraf:rw" `
        -v "/var/run/docker.sock:/var/run/docker.sock" `
        $imageName 
}

if ($settings.global.bootstrap.installChronograf) {
    if (!$settings.global.bootstrap.installInfluxDb) {
        throw "Chronograf is dependent on influxdb, please enable influxdb installation on your settings."
    }

    $chronografPort = $settings.chronograf.port
    $imageName = $settings.chronograf.image
    RemoveContainerByImageName -ImageName $imageName

    Write-Host "Deploy chronograf on '$chronografPort'..." -ForegroundColor Green
    $influxdbUrl = $settings.chronograf.influxDbUrl
    docker run -d --name chronograf -p "$($chronografPort):8888" --net=$net --influxdb-url=$influxdbUrl $imageName
}

if ($settings.global.bootstrap.installFluentd) {
    $hostFluentFolder = Join-Path $settings.global.sharedDrive $settings.fluentd.sharedFolder 
    EnsureFolder -FolderPath $hostFluentFolder -CleanFolder
    $fluentdPort = $settings.fluentd.port
    $fluentdUdpPort = $settings.fluentd.udpPort
    $imageName = $settings.fluentd.image
    Write-Host "Deploy fluentd on '$fluentdPort'..." -ForegroundColor Green
    RemoveContainerByImageName -ImageName $imageName

    docker run -d --name fluentd -p "$($fluentdPort):24224" -p "$($fluentdUdpPort):24224/udp" -v "$($hostFluentFolder):/fluentd/log:rw" --net=$net $imageName
}

if ($settings.global.bootstrap.installGrafana) {
    $grafanaPort = $settings.grafana.port
    $imageName = $settings.grafana.image
    Write-Host "Deploy grafana on port '$grafanaPort'..." -ForegroundColor Green
    RemoveContainerByImageName -ImageName $imageName

    docker run -d --name=grafana -p "$($grafanaPort):3000" --net=$net $imageName
}

if ($settings.global.bootstrap.installPrometheus) {
    $prometheusPort = $settings.prometheus.port
    $imageName = $settings.prometheus.image
    Write-Host "Deploy prometheus on port '$prometheusPort'..." -ForegroundColor Green

    $hostPrometheusFolder = Join-Path $settings.global.sharedDrive $settings.prometheus.sharedFolder
    EnsureFolder -FolderPath $hostPrometheusFolder -CleanFolder
    $srcPrometheusConfFile = Join-Path $confFolder "prometheus.yml"
    $prometheusConfFile = Join-Path $hostPrometheusFolder "prometheus.yml"
    Copy-Item -Path $srcPrometheusConfFile -Destination $prometheusConfFile -Force | Out-Null

    $installMethod = $settings.prometheus.installMethod 
    if ($installMethod -eq "choco") {
        Get-Process | Where-Object { $_.Name -contains "prom" } | Stop-Process
        choco.exe install prometheus /y 
        Start-Process prometheus.exe --config.file="$($prometheusConfFile)" 
    }
    else {
        RemoveContainerByImageName -ImageName $imageName
        docker.exe run -d --name prometheus -p "$($prometheusPort):9090" -v "$($hostPrometheusFolder)/prometheus.yml:/etc/prometheus/prometheus.yml:ro" $imageName
    }

    if ($settings.prometheus.exporters -and $settings.prometheus.exporters.node_exporter) {
        $nodeExporter = $settings.prometheus.exporters.node_exporter
        $nodeExporterImageName = $nodeExporter.image 
        $nodeExporterPort = $nodeExporter.port 
        Write-Host "Deploy '$($nodeExporterImageName)' on port '$nodeExporterPort'..." -ForegroundColor Green
        RemoveContainerByImageName -ImageName $nodeExporterImageName

        docker run -d --name node_exporter -p "$($nodeExporterPort):9100" -v "/proc:/host/proc" -v "/sys:/host/sys" -v "/:/rootfs" --net=$net $nodeExporterImageName `
            --path.procfs /host/proc --path.sysfs /host/proc --collector.filesystem.ignored-mount-points "^/(sys|proc|dev|host|etc)($|/)"

    }
}