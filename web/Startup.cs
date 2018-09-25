using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Sockets;
using System.Threading.Tasks;
using App.Metrics;
using App.Metrics.Formatters.InfluxDB;
using App.Metrics.Reporting.Socket;
using App.Metrics.Reporting.Socket.Client;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.HttpsPolicy;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Web
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            var metrics = AppMetrics.CreateDefaultBuilder()
                .Report.ToInfluxDb(options =>
                {
                    options.InfluxDb.BaseUri = new Uri("http://localhost:8086"); // TODO: read from appSettings
                    options.InfluxDb.Database = "appmetric";
                    options.InfluxDb.CreateDataBaseIfNotExists = true;
                })
                .Report.OverUds(new MetricsReportingSocketOptions()
                {
                    SocketSettings = new SocketSettings()
                    {
                        ProtocolType = ProtocolType.IP,
                        Address = "//tmp/telegraf.sock"
                    },
                    MetricsOutputFormatter = new MetricsInfluxDbLineProtocolOutputFormatter(new MetricsInfluxDbLineProtocolOptions()),
                    FlushInterval = TimeSpan.FromSeconds(30)
                })
                .Build();
            services.AddMetrics(metrics);
            services.AddMetricsTrackingMiddleware();
            services.AddMetricsReportScheduler();
            
            services.Configure<CookiePolicyOptions>(options =>
            {
                // This lambda determines whether user consent for non-essential cookies is needed for a given request.
                options.CheckConsentNeeded = context => true;
                options.MinimumSameSitePolicy = SameSiteMode.None;
            }); 


            services.AddMvc().SetCompatibilityVersion(CompatibilityVersion.Version_2_1).AddMetrics();
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IHostingEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }
            else
            {
                app.UseExceptionHandler("/Home/Error");
                app.UseHsts();
            }

            app.UseHttpsRedirection();
            app.UseStaticFiles();
            app.UseCookiePolicy();
            app.UseMetricsAllMiddleware();

            app.UseMvc(routes =>
            {
                routes.MapRoute(
                    name: "default",
                    template: "{controller=Home}/{action=Index}/{id?}");
            });
        }
    }
}
