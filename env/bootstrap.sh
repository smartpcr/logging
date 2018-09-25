
echo "deploy influxdb..."
sudo rm -rf /tmp/influxdb
sudo mkdir -p /tmp/influxdb
sudo cp ./influxdb.conf /tmp/influxdb 
sudo chmod 777 /tmp/influxdb
docker network create influxdb
docker run -d --name influxdb --net=influxdb -p 8086:8086 \
      -v /tmp/influxdb/influxdb.conf:/etc/influxdb/influxdb.conf:ro \
      -v /tmp/influxdb:/var/lib/influxdb:rw \
      influxdb -config /etc/influxdb/influxdb.conf

echo "deploy telegraf..."
sudo rm -rf /tmp/telegraf
sudo mkdir -p /tmp/telegraf
sudo chmod 777 /tmp/telegraf
sudo cp ./telegraf.conf /tmp/telegraf 
docker run -d --name=telegraf --net=influxdb \
      -v /tmp/telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:ro telegraf 


echo "deploy grafana..."
docker run -d --name=grafana --net=influxdb -p 3000:3000 grafana/grafana

echo "deploy fluentd..."
New-Item -Path c:\fluentd -ItemType Directory | Out-Null
docker run -d --name fluentd --net=influxdb -p 24224:24224 -p 24224:24224/udp \
      -v c:\fluentd:/fluentd/log:rw fluent/fluentd

echo "build web..."

docker run -d --name web -p 8000:80 --net=influxdb web

echo "run EFK stack..."
docker-compose up 

dotnet build 
dotnet run 