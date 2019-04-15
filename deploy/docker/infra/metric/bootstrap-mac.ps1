$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}

Write-Host "Deploy influxdb..."
$influxDbFolder = Join-Path $envFolder "influxdb"
Remove-Item -Recurse -Force $influxDbFolder
New-Item -Path $influxDbFolder -ItemType Directory | Out-Null
# docker network create influxdb
& docker run -d --name influxdb -p 8083:8083 -v $($influxDbFolder):/var/lib/influxdb:rw influxdb

Write-Host "Deploy telegraf..."
$telegrafFolder = Join-Path $envFolder "telegraf"
Remove-Item -Recurse -Force $telegrafFolder
New-Item -Path $telegrafFolder -ItemType Directory | Out-Null
Copy-Item -Path $envFolder/telegraf.conf -Destination $telegrafFolder/telegraf.conf 
docker run -d --name telegraf -v $($telegrafFolder)/telegraf.conf:/etc/telegraf/telegraf.conf:ro telegraf 

docker run -d --name chronograf -p 8888:8888 --net=container:influxdb chronograf --influxdb-url=http://localhost:8086

docker run -d --name=grafana -p 3000:3000 --net=container:influxdb grafana/grafana

New-Item -Path c:\fluentd -ItemType Directory | Out-Null
docker run -d --name fluentd -p 24224:24224 -p 24224:24224/udp -v c:\fluentd:/fluentd/log:rw fluent/fluentd

dotnet build 
dotnet run 