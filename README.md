# Goals

- Poc for logging/metrics
- A simple .net core webapi following [generator]() that will inject the following features:
    - Prometheus
    - Serilog
    - Open tracing
    - App Insights
- Deployments
    1. bootstrap azure resources, including (currently it's using AZ cli, will consider migrate to terraform if that's simpler):
        - resource group 
        - container registry (helm)
        - service principals 
        - key vault 
        - cert to access key vault 
        - aks cluster with AAD integration
        - application insights 
        - cosmos db 
        - aks addons
            - prometheus operator (includes grafana)

    2. solution deployment 
        1. setting hierarchy for solutions
            - global settings: shared settings across all environments (dev, int and prod)
            - target env: target single AKS cluster (including SPN, KV, and ACR)
            - devspace: personal space (target a single namespace within AKS)
        2. prep
            - each project has Dockerfile, image was published to ACR repo
            - key vault secrets are synchronized and published to AKS as secrets under namespace
        3. helm install for each chart


# Solution layout
- env 
    infrastructure settings, specify resources to be provisioned within azure
- deploy
    PS scripts to deploy both infrastructure and applications
- src 
    source code including tests
    - services 
        - Generator.Api
        - Generator.Api.UnitTests: unit tests 
        - Generator.Api.IntegrationTests: integration tests
- charts
    helm charts 

# Hot Path

Uses telegraf to collect the following machine metrics
- CPU
- Memory
- Disk
- Network

Use appmetrics to collect the following app perf counters
- Call rate
- Call latency
- Failure rate
- Circuit breaker
- Timeout/Cancellation 
- Throughput

The following sink will be supported:
1. influxdb
2. unix socket

# Warm Path

Use serilog to collect trace messages 
- eventId, activityId, level, userId, service, version, action, parameters
- exception message/stacktrace

The following sink will be supported:
1. fluentd+elastic search+kabana

