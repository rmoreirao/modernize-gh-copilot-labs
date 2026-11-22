using System;
using System.Configuration;
using System.Threading;
using Microsoft.Owin.Hosting;

namespace OrderDesk.Legacy
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            try
            {
                var url = ConfigurationManager.AppSettings["ListenUrl"];
                if (args.Length != 0)
                {
                    if (args.Length != 2 || args[0] != "--url")
                        throw new ArgumentException("Usage: OrderDesk.Legacy.exe [--url http://localhost:PORT/]");
                    url = args[1];
                }

                Uri address;
                if (!Uri.TryCreate(url, UriKind.Absolute, out address) ||
                    address.Scheme != "http" || !address.IsLoopback ||
                    address.AbsolutePath != "/" || address.Query.Length != 0)
                    throw new ArgumentException("The listen URL must be an HTTP localhost URL with a root path.");

                using (var stopped = new ManualResetEventSlim())
                using (WebApp.Start<Startup>(url))
                {
                    Console.CancelKeyPress += (sender, e) =>
                    {
                        e.Cancel = true;
                        stopped.Set();
                    };
                    Console.WriteLine("OrderDesk.Legacy listening on " + url + " (Ctrl+C to stop)");
                    stopped.Wait();
                }
                return 0;
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(exception);
                return 1;
            }
        }
    }
}
