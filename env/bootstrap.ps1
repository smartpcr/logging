$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}

Write-Host "Deploy influxdb..."
Remove-Item -Recurse -Force C:\influxdb -ErrorAction SilentlyContinue
New-Item -Path c:\influxdb -ItemType Directory | Out-Null
Copy-Item $envFolder\influxdb.conf -Destination c:\influxdb 
docker network create influxdb
docker run -d --name influxdb --net=influxdb -p 8086:8086 `
    -v c:\influxdb\influxdb.conf:/etc/influxdb/influxdb.conf:ro `
    -v c:\influxdb:/var/lib/influxdb:rw `
    influxdb -config /etc/influxdb/influxdb.conf

Write-Host "run telegraf..."
Remove-Item -Recurse -Force c:\telegraf -ErrorAction SilentlyContinue
New-Item -Path c:\telegraf -ItemType Directory | Out-Null
Copy-Item -Path $envFolder\telegraf.conf -Destination C:\telegraf\telegraf.conf 
docker run -d --name telegraf --net=influxdb -v C:\telegraf\telegraf.conf:/etc/telegraf/telegraf.conf:ro telegraf 

docker run -d --name chronograf -p 8888:8888 --net=influxdb chronograf --influxdb-url=http://localhost:8086

docker run -d --name=grafana -p 3000:3000 --net=influxdb grafana/grafana

New-Item -Path c:\fluentd -ItemType Directory | Out-Null
docker run -d --name fluentd -p 24224:24224 -p 24224:24224/udp -v c:\fluentd:/fluentd/log:rw fluent/fluentd

dotnet build 
dotnet run 