Remove-Item -Recurse -Force C:\influxdb
mkdir -p c:\influxdb | Out-Null

docker run -d --name influxdb -p 8083:8083 -p 8086:8086 -v c:\influxdb:/var/lib/influxdb:rw influxdb

docker run -d --name telegraf --net=container:influxdb telegraf 

docker run -d --name=grafana -p 3000:3000 grafana/grafana

mkdir -p c:\fluentd 
docker run -d --name fluentd -p 24224:24224 -p 24224:24224/udp -v c:\fluentd:/fluentd/log:rw fluent/fluentd

dotnet build 
dotnet run 