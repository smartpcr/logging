
echo "run influxdb..."
sudo rm -rf /var/lib/influxdb
sudo mkdir -p /var/lib/influxdb
sudo cp ./influxdb.conf /var/lib/influxdb 
# docker run -d --name influxdb -p 8086:8086 -v /var/lib/influxdb:/var/lib/influxdb:rw influxdb
docker run -d --name influxdb 8086:8086 \
      -v /var/lib/influxdb/influxdb.conf:/etc/influxdb/influxdb.conf:ro \
      -v /var/lib/influxdb:/var/lib/influxdb:rw \
      influxdb -config /etc/influxdb/influxdb.conf

echo "run telegraf..."
sudo rm -rf /var/lib/telegraf
sudo mkdir -p /var/lib/telegraf
sudo cp ./telegraf.conf /var/lib/telegraf 
docker run -d --name=telegraf -v /var/lib/telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:ro telegraf 


echo "run grafana..."
docker run -d --name=grafana -p 3000:3000 grafana/grafana


echo "run EFK stack..."
docker-compose up 

dotnet build 
dotnet run 