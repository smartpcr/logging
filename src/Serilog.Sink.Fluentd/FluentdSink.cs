using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using Serilog.Events;
using Serilog.Sinks.PeriodicBatching;

namespace Serilog.Sink.Fluentd
{
    public class FluentdSink : PeriodicBatchingSink
    {
        private readonly FluentdSinkClient _fluentdClient;

        public FluentdSink(FluentdSinkOptions options) : base(options.BatchPostingLimit, options.Period)
        {
            _fluentdClient = new FluentdSinkClient(options);
        }

        protected override async Task EmitBatchAsync(IEnumerable<LogEvent> events)
        {
            foreach (var logEvent in events)
            {
                await _fluentdClient.SendAsync(logEvent);
            }
        }
    }
}
