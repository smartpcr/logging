using System;

namespace Web.PerfCounters
{
    public class OperationContext
    {
        public string ActivityId { get; set; }
        public string Name { get; set; }
        public string User { get; set; }
        public DateTimeOffset Time { get; set; }
        public TimeSpan Duration { get; set; }
    }
}