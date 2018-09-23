
echo "run influxdb..."
mkdir -p ./influxdb 
docker run -d -p 8086:8086 -v ./influxdb:/var/lib/influxdb:rw influxdb

echo "run grafana..."
docker run -d --name=grafana -p 3000:3000 grafana/grafana

echo "run EFK stack..."
docker-compose up 

dotnet build 
dotnet run 