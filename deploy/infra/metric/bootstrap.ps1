Write-Host "Get git root folder..."
$currentLocation = Get-Location
while (-not (Test-Path (Join-Path $currentLocation ".git") -PathType Container)) {
    $currentLocation = Split-Path $currentLocation -Parent 
}
Write-Host "Git root folder found: '$currentLocation'"
$GitRoot = $currentLocation

Write-Host "Deploy influxdb on 8086..."
Remove-Item -Recurse -Force C:\influxdb -ErrorAction SilentlyContinue
New-Item -Path c:\influxdb -ItemType Directory | Out-Null
Copy-Item $GitRoot\deploy\infra\metric\influxdb.conf -Destination c:\influxdb 
docker network create influxdb
docker volume create --driver local --name influxdb --opt o=size=200m --opt device=tmpfs --opt type=tmpfs 
docker run -d --name influxdb --net=influxdb -p 8086:8086 `
    -v c:\influxdb\influxdb.conf:/etc/influxdb/influxdb.conf:ro `
    -v influxdb:/var/lib/influxdb:rw `
    influxdb -config /etc/influxdb/influxdb.conf

Write-Host "Deploy telegraf..."
Remove-Item -Recurse -Force c:\telegraf -ErrorAction SilentlyContinue
New-Item -Path c:\telegraf -ItemType Directory | Out-Null
Copy-Item -Path $GitRoot\deploy\infra\metric\telegraf.conf -Destination C:\telegraf\telegraf.conf 
Remove-Item -Recurse -Force c:\run\telegraf -ErrorAction SilentlyContinue
New-Item -Path c:\run\telegraf -ItemType Directory | Out-Null

docker run -d --name telegraf --net=influxdb `
    -v C:\telegraf\telegraf.conf:/etc/telegraf/telegraf.conf:ro `
    -v /var/run/telegraf:/var/run/telegraf:rw `
    -v /var/run/docker.sock:/var/run/docker.sock `
    telegraf 


Write-Host "Deploy chronograf on 8888..."
docker run -d --name chronograf -p 8888:8888 --net=influxdb chronograf --influxdb-url=http://influxdb:8086


Write-Host "Deploy grafana on 3000..."
docker run -d --name=grafana -p 3000:3000 --net=influxdb grafana/grafana


Write-Host "Deploy fluentd on 24224..."
New-Item -Path c:\fluentd -ItemType Directory | Out-Null
docker run -d --name fluentd -p 24224:24224 -p 24224:24224/udp -v c:\fluentd:/fluentd/log:rw fluent/fluentd


Write-Host "Deploy web on 8000..."
docker build -t web "$GitRoot\src"
docker run -d --name web -p 8000:80 --net=influxdb `
      -v /var/run/telegraf:/var/run/telegraf:rw `
      web

$chromeExe = "'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
Write-Host "Openning grafana and set user/password (default to admin/admin)"
start-process -FilePath $chromeExe -ArgumentList "http://localhost:3000"