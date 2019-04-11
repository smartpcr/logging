1. run bootstrap.ps1 within deploy\infra\metric folder
2. web app will create influxdb database `appmetric` (no user or password)
3. open grafana (localhost:3000) and add influxdb data source
    - url: http://localhost:8086
    - access: browser
    - database: appmetric
4. import dashboard template: 2125