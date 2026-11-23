using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using Xunit;
using Xunit.Abstractions;

[assembly: CollectionBehavior(DisableTestParallelization = true)]

namespace HttpBaseline.Tests;

// A scenario owns this process. No reset endpoint, shared host, or ordered tests.
internal sealed class ExternalHost : IAsyncDisposable
{
    private readonly Process process;
    private readonly HttpClient client;
    private readonly Uri baseUrl;
    private readonly string readyPath;
    private readonly ITestOutputHelper output;
    private readonly StringBuilder logs = new();
    private readonly object logGate = new();
    private bool started;

    private ExternalHost(ITestOutputHelper output)
    {
        this.output = output;
        string executable = RequiredEnvironment("ORDERDESK_HOST_EXE");
        string workingDirectory = RequiredEnvironment("ORDERDESK_HOST_WORKDIR");
        string[] arguments = JsonSerializer.Deserialize<string[]>(
            RequiredEnvironment("ORDERDESK_HOST_ARGS"))
            ?? throw new InvalidOperationException("ORDERDESK_HOST_ARGS must be a JSON string array.");
        if (arguments.Any(argument => argument is null))
            throw new InvalidOperationException("ORDERDESK_HOST_ARGS cannot contain null arguments.");
        if (!Path.IsPathFullyQualified(executable) || !File.Exists(executable))
            throw new InvalidOperationException($"Host executable not found at an absolute path: {executable}");
        if (!Path.IsPathFullyQualified(workingDirectory) || !Directory.Exists(workingDirectory))
            throw new InvalidOperationException($"Host working directory not found: {workingDirectory}");
        if (!Uri.TryCreate(RequiredEnvironment("ORDERDESK_BASE_URL"), UriKind.Absolute, out Uri? url)
            || url.Scheme != Uri.UriSchemeHttp || !url.IsLoopback
            || url.AbsolutePath != "/" || url.Query.Length != 0 || url.Fragment.Length != 0
            || url.UserInfo.Length != 0)
            throw new InvalidOperationException("ORDERDESK_BASE_URL must be an HTTP loopback root URL.");
        baseUrl = url;
        readyPath = RequiredEnvironment("ORDERDESK_READY_PATH");
        if (!readyPath.StartsWith('/') || readyPath.StartsWith("//", StringComparison.Ordinal)
            || readyPath.Any(character => char.IsWhiteSpace(character) || char.IsControl(character))
            || readyPath.Contains('\\') || readyPath.Contains('#')
            || new Uri(baseUrl, readyPath).Authority != baseUrl.Authority)
            throw new InvalidOperationException("ORDERDESK_READY_PATH must be a same-host GET path starting with one slash.");

        var startInfo = new ProcessStartInfo(executable)
        {
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        foreach (string argument in arguments)
            startInfo.ArgumentList.Add(argument);
        process = new Process { StartInfo = startInfo };
        process.OutputDataReceived += (_, e) => Capture("stdout", e.Data);
        process.ErrorDataReceived += (_, e) => Capture("stderr", e.Data);
        client = new HttpClient(new HttpClientHandler { UseProxy = false })
        {
            BaseAddress = baseUrl,
            Timeout = TimeSpan.FromSeconds(5)
        };
        client.DefaultRequestHeaders.Accept.ParseAdd("application/json");
    }

    public HttpClient Client
    {
        get
        {
            EnsureAlive();
            return client;
        }
    }

    public static async Task<ExternalHost> StartAsync(ITestOutputHelper output)
    {
        var host = new ExternalHost(output);
        try
        {
            if (host.PortIsOccupied())
                throw new InvalidOperationException(
                    $"Port {host.baseUrl.Port} is occupied. Stop its owner; the baseline will not reuse or kill it.");
            if (!host.process.Start())
                throw new InvalidOperationException("The configured host process did not start.");
            host.started = true;
            host.process.BeginOutputReadLine();
            host.process.BeginErrorReadLine();

            var deadline = Stopwatch.StartNew();
            string lastProbe = "No HTTP response.";
            while (deadline.Elapsed < TimeSpan.FromSeconds(15))
            {
                host.EnsureAlive();
                try
                {
                    using var probeTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(1));
                    using HttpResponseMessage response = await host.client.GetAsync(
                        host.readyPath, probeTimeout.Token);
                    host.EnsureAlive();
                    if (response.StatusCode == HttpStatusCode.OK)
                        return host;
                    lastProbe = $"GET {host.readyPath} returned {(int)response.StatusCode}.";
                }
                catch (Exception exception) when (
                    exception is HttpRequestException or OperationCanceledException)
                {
                    lastProbe = exception.Message;
                }
                await Task.Delay(100);
            }
            throw new TimeoutException($"Host was not ready within 15 seconds. {lastProbe}");
        }
        catch (Exception exception)
        {
            string diagnostic = host.Diagnostics();
            await host.DisposeAsync();
            throw new InvalidOperationException($"External host setup failed. {diagnostic}", exception);
        }
    }

    public void EnsureAlive()
    {
        if (!started || process.HasExited)
            throw new InvalidOperationException($"Launched host is not alive. {Diagnostics()}");
    }

    public async ValueTask DisposeAsync()
    {
        try
        {
            if (started)
            {
                if (!process.HasExited)
                {
                    try
                    {
                        // Never look up a process by name or kill an existing port owner.
                        process.Kill(entireProcessTree: true);
                    }
                    catch (InvalidOperationException) when (process.HasExited)
                    {
                        // The launched process exited between the check and Kill.
                    }
                }
                await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
                var release = Stopwatch.StartNew();
                while (PortIsOccupied())
                {
                    if (release.Elapsed >= TimeSpan.FromSeconds(5))
                        throw new TimeoutException(
                            $"Launched PID {process.Id} exited but port {baseUrl.Port} remains occupied.");
                    await Task.Delay(100);
                }
            }
        }
        finally
        {
            output.WriteLine(Diagnostics());
            client.Dispose();
            process.Dispose();
        }
    }

    // Includes wildcard/IPv4/IPv6 listeners. This checks occupancy without binding
    // a port or mistaking Windows' slow refused TCP connections for an owner.
    private bool PortIsOccupied() =>
        IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners()
            .Any(endpoint => endpoint.Port == baseUrl.Port);

    private static string RequiredEnvironment(string name)
    {
        string? value = Environment.GetEnvironmentVariable(name);
        return !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new InvalidOperationException($"{name} is required. Run scripts/Test-Baseline.ps1.");
    }

    private void Capture(string stream, string? line)
    {
        if (line is null)
            return;
        lock (logGate)
        {
            if (logs.Length < 32_768)
                logs.AppendLine($"[{stream}] {line}");
        }
    }

    private string Diagnostics()
    {
        lock (logGate)
        {
            string identity = started
                ? $"PID {process.Id}{(process.HasExited ? $", exit {process.ExitCode}" : "")}"
                : "not started";
            return $"{process.StartInfo.FileName} ({identity}) at {baseUrl}{Environment.NewLine}{logs}";
        }
    }
}
