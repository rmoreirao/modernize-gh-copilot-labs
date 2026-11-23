// Tooling regression cases only. The initializer never generates this file.
using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json;
using Xunit;
using Xunit.Abstractions;

namespace HttpBaseline.Tests;

public sealed class FixtureProbes(ITestOutputHelper output)
{
    [Fact]
    public async Task RunnerConfiguredHostUsesForwardedLaunchInputs()
    {
        await using var host = await ExternalHost.StartAsync(output);
        using var response = await host.Client.GetAsync("/probe-ready");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(37, body.RootElement.GetProperty("value").GetInt32());
    }

    [Fact]
    public async Task ConfiguredReadinessReturnsExactResponseAndStopsOwnedTree()
    {
        using var configuration = Configure("Ready");
        var capture = new CaptureOutput(output);
        var host = await ExternalHost.StartAsync(capture);
        int parent;
        int child;
        try
        {
            using var response = await host.Client.GetAsync("/probe-ready");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal(37, body.RootElement.GetProperty("value").GetInt32());
            parent = ReadPid(configuration.Root, "host");
            child = ReadPid(configuration.Root, "child");
            Assert.True(IsAlive(parent));
            Assert.True(IsAlive(child));
        }
        finally { await host.DisposeAsync(); }
        await AssertStopped(parent);
        await AssertStopped(child);
        Assert.False(PortOccupied(configuration.Port));
        Assert.Contains("probe-listening-Ready", capture.Text);
        Assert.Contains($"PID {parent}", capture.Text);
    }

    [Fact]
    public async Task OccupiedPortLeavesExistingOwnerAlive()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        using var configuration = Configure("Ready", port);
        var error = await Assert.ThrowsAsync<InvalidOperationException>(
            () => ExternalHost.StartAsync(output));
        Assert.Contains("occupied", error.InnerException!.Message);
        Assert.True(PortOccupied(port));
        Assert.False(File.Exists(Path.Combine(configuration.Root, "host.pid")));
        // The unowned socket remains functional, not merely present in a listener list.
        using var connect = new TcpClient();
        await connect.ConnectAsync(IPAddress.Loopback, port);
        using var accepted = await listener.AcceptTcpClientAsync();
        Assert.True(accepted.Connected);
    }

    [Fact]
    public async Task EarlyExitIncludesOwnedHostLogs()
    {
        using var configuration = Configure("Exit");
        var error = await Assert.ThrowsAsync<InvalidOperationException>(
            () => ExternalHost.StartAsync(output));
        Assert.Contains("probe-exit-23", error.ToString());
        Assert.Contains("exit 23", error.ToString());
        await AssertStopped(ReadPid(configuration.Root, "host"));
        Assert.False(PortOccupied(configuration.Port));
    }

    [Fact]
    public async Task ReadinessTimeoutStopsOwnedTreeAndPreservesLogs()
    {
        using var configuration = Configure("Unready");
        var stopwatch = Stopwatch.StartNew();
        var error = await Assert.ThrowsAsync<InvalidOperationException>(
            () => ExternalHost.StartAsync(output));
        Assert.IsType<TimeoutException>(error.InnerException);
        Assert.Contains("GET /probe-ready returned 503", error.ToString());
        Assert.Contains("probe-listening-Unready", error.ToString());
        Assert.InRange(stopwatch.Elapsed.TotalSeconds, 15, 30);
        await AssertStopped(ReadPid(configuration.Root, "host"));
        await AssertStopped(ReadPid(configuration.Root, "child"));
        Assert.False(PortOccupied(configuration.Port));
    }

    [Theory]
    [InlineData("ORDERDESK_HOST_EXE")]
    [InlineData("ORDERDESK_HOST_ARGS")]
    [InlineData("ORDERDESK_HOST_WORKDIR")]
    [InlineData("ORDERDESK_BASE_URL")]
    [InlineData("ORDERDESK_READY_PATH")]
    public async Task MissingLaunchConfigurationCannotStartHost(string key)
    {
        using var configuration = Configure("Ready");
        Environment.SetEnvironmentVariable(key, null);
        var error = await Assert.ThrowsAsync<InvalidOperationException>(
            () => ExternalHost.StartAsync(output));
        Assert.Contains($"{key} is required", error.Message);
        Assert.False(File.Exists(Path.Combine(configuration.Root, "host.pid")));
    }

    private static Configuration Configure(string mode, int? port = null) => new(mode, port);

    private sealed class Configuration : IDisposable
    {
        private readonly Dictionary<string, string?> saved;
        public string Root { get; }
        public int Port { get; }

        public Configuration(string mode, int? port)
        {
            string executable = Environment.GetEnvironmentVariable("HTTP_BASELINE_PROBE_EXE")!;
            string script = Environment.GetEnvironmentVariable("HTTP_BASELINE_PROBE_SCRIPT")!;
            Root = Path.Combine(Environment.GetEnvironmentVariable("HTTP_BASELINE_SCRATCH")!, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Root);
            if (port.HasValue) Port = port.Value;
            else
            {
                using var reservation = new TcpListener(IPAddress.Loopback, 0);
                reservation.Start();
                Port = ((IPEndPoint)reservation.LocalEndpoint).Port;
            }
            var values = new Dictionary<string, string>
            {
                ["ORDERDESK_HOST_EXE"] = executable,
                ["ORDERDESK_HOST_WORKDIR"] = Root,
                ["ORDERDESK_HOST_ARGS"] = JsonSerializer.Serialize(new[] {
                    "-NoProfile", "-File", script, "-Port", Port.ToString(),
                    "-StateRoot", Root, "-Mode", mode }),
                ["ORDERDESK_BASE_URL"] = $"http://127.0.0.1:{Port}/",
                ["ORDERDESK_READY_PATH"] = "/probe-ready"
            };
            saved = values.Keys.ToDictionary(key => key, Environment.GetEnvironmentVariable);
            foreach (var pair in values) Environment.SetEnvironmentVariable(pair.Key, pair.Value);
        }

        public void Dispose()
        {
            foreach (var pair in saved) Environment.SetEnvironmentVariable(pair.Key, pair.Value);
        }
    }

    private sealed class CaptureOutput(ITestOutputHelper inner) : ITestOutputHelper
    {
        public string Text { get; private set; } = "";
        public void WriteLine(string message) { Text += message + "\n"; inner.WriteLine(message); }
        public void WriteLine(string format, params object[] args) => WriteLine(string.Format(format, args));
    }

    private static int ReadPid(string root, string name) => int.Parse(File.ReadAllText(Path.Combine(root, $"{name}.pid")));
    private static bool IsAlive(int pid)
    {
        try { using var process = Process.GetProcessById(pid); return !process.HasExited; }
        catch (ArgumentException) { return false; }
    }
    private static async Task AssertStopped(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5));
            Assert.True(process.HasExited);
        }
        catch (ArgumentException) { } // Already reaped.
        Assert.False(IsAlive(pid));
    }
    private static bool PortOccupied(int port) =>
        IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners().Any(endpoint => endpoint.Port == port);
}
