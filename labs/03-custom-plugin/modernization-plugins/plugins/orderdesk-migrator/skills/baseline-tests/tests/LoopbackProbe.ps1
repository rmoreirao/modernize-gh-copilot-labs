# Test-only host; never copied by Initialize-Baseline.ps1.
param([int]$Port, [string]$StateRoot, [ValidateSet('Ready', 'Unready', 'Exit')][string]$Mode = 'Ready')
$ErrorActionPreference = 'Stop'
[IO.Directory]::CreateDirectory($StateRoot) | Out-Null
[IO.File]::WriteAllText((Join-Path $StateRoot 'host.pid'), [string]$PID)
if ($Mode -eq 'Exit') { [Console]::Error.WriteLine('probe-exit-23'); exit 23 }
$childInfo = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
$childInfo.UseShellExecute = $false
foreach ($arg in @('-NoProfile', '-Command', 'Start-Sleep -Seconds 120')) { $childInfo.ArgumentList.Add($arg) }
$child = [Diagnostics.Process]::Start($childInfo)
[IO.File]::WriteAllText((Join-Path $StateRoot 'child.pid'), [string]$child.Id)
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
    [Console]::WriteLine("probe-listening-$Mode")
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $client.ReceiveTimeout = 2000
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
            $line = $reader.ReadLine()
            while ($reader.ReadLine()) { }
            $ready = $Mode -eq 'Ready' -and $line -match '^GET /probe-ready HTTP/'
            $code = if ($ready) { '200 OK' } else { '503 Service Unavailable' }
            $body = if ($ready) { '{"value":37}' } else { '{"value":-1}' }
            $message = "HTTP/1.1 $code`r`nContent-Type: application/json`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n$body"
            $bytes = [Text.Encoding]::ASCII.GetBytes($message)
            $stream.Write($bytes)
            $stream.Flush()
            $reader.Dispose()
        } finally { $client.Dispose() }
    }
} finally {
    $listener.Stop()
    if (-not $child.HasExited) { $child.Kill($true); $child.WaitForExit(5000) | Out-Null }
    $child.Dispose()
}
