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

