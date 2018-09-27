using System;
using System.Diagnostics;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Web.Models;
using App.Metrics;
using App.Metrics.Counter;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Primitives;

namespace Web.Controllers
{
    public class HomeController : Controller
    {
        private const string ACTIVITY_ID = "ActivityId";
        private readonly IMetrics _metrics;
        private readonly ILogger<HomeController> _logger;
        private readonly RequestDurationForApdexTesting _durationForApdexTesting = 
            new RequestDurationForApdexTesting(1.0);

        private readonly CounterOptions _counterOptions = new CounterOptions()
        {
            MeasurementUnit = Unit.Calls,
            Name = "Home",
            ResetOnReporting = true  
        };

        public HomeController(IMetrics metrics, ILogger<HomeController> logger)
        {
            _metrics = metrics;
            _logger = logger;
        }

        public override void OnActionExecuting(ActionExecutingContext context)
        {
            var actionName = context.ActionDescriptor.DisplayName;
            StringValues activityId;
            if (context.HttpContext.Request.Headers.TryGetValue(ACTIVITY_ID, out activityId))
            {
                activityId = Guid.NewGuid().ToString();
                context.HttpContext.Request.Headers.Add(ACTIVITY_ID, activityId);
                
            }
            base.OnActionExecuting(context);
        }

        public IActionResult Index()
        {
            return View();
        }

        public IActionResult About()
        {
            ViewData["Message"] = "Your application description page.";

            return View();
        }

        public IActionResult Contact()
        {
            ViewData["Message"] = "Your contact page.";

            return View();
        }

        public IActionResult Privacy()
        {
            return View();
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
        }

        public IActionResult PageNotFound()
        {
            return NotFound();
        }

        public IActionResult Fail()
        {
            throw new Exception("Error found");
        }

        public async Task<IActionResult> Wait()
        {
            var random = new Random();
            await Task.Delay(TimeSpan.FromSeconds(random.Next(10)));
            return Ok("long task");
        }

        public async Task<int> Abort()
        {
            var duration = _durationForApdexTesting.NextFrustratingDuration;
            await Task.Delay(duration, HttpContext.RequestAborted);
            return duration;
        }

        public IActionResult Increment(string tag = null)
        {
            var tags = new MetricTags("userTag", tag ?? "undefined");
            _metrics.Measure.Counter.Increment(_counterOptions, tags);
            _logger.LogInformation("Increment was hit with {tag}", tag);
            var info = new
            {
                ControllerName = "Home",
                Timestamp = DateTime.UtcNow,
                ClientAddress = HttpContext.Connection.RemoteIpAddress.ToString()
            };
            _logger.LogInformation("Increment was hit with {@info}", info);
            return Ok("done");
        }
    }
}
