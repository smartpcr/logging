Remove-Item -Recurse -Force C:\influxdb
New-Item -Path c:\influxdb -ItemType Directory | Out-Null
docker network create influxdb
docker run -d --name influxdb -p 8083:8083 --net=influxdb -v c:\influxdb:/var/lib/influxdb:rw influxdb

Remove-Item -Recurse -Force c:\telegraf 
New-Item -Path c:\telegraf -ItemType Directory | Out-Null
Copy-Item -Path $PWD\telegraf.conf -Destination C:\telegraf\telegraf.conf 
docker run -d --name telegraf --net=influxdb -v C:\telegraf\telegraf.conf:/etc/telegraf/telegraf.conf:ro telegraf 

docker run -d --name chronograf -p 8888:8888 --net=container:influxdb chronograf --influxdb-url=http://localhost:8086

docker run -d --name=grafana -p 3000:3000 --net=container:influxdb grafana/grafana

New-Item -Path c:\fluentd -ItemType Directory | Out-Null
docker run -d --name fluentd -p 24224:24224 -p 24224:24224/udp -v c:\fluentd:/fluentd/log:rw fluent/fluentd

dotnet build 
dotnet run 