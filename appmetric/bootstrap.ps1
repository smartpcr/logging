mkdir -p c:\influxdb 

docker run -d -p 8086:8086 `
    -v c:\influxdb:/var/lib/influxdb:rw `
    influxdb


docker run -d --name=grafana -p 3000:3000 grafana/grafana

mkdir -p c:\fluentd 
docker run -d -p 24224:24224 -p 24224:24224/udp -v c:\fluentd:/fluentd/log:rw fluent/fluentd

dotnet build 
dotnet run 