#requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$AppRoot)

$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathFullyQualified($AppRoot) -or
    -not (Test-Path -LiteralPath $AppRoot -PathType Container)) {
    throw '-AppRoot must be an absolute existing application directory.'
}
$AppRoot = (Resolve-Path -LiteralPath $AppRoot).Path
$templates = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates'
$outputs = [ordered]@{
    'tests/baseline/HttpBaseline.Tests.csproj' = 'HttpBaseline.Tests.csproj'
    'tests/baseline/ExternalHost.cs' = 'ExternalHost.cs'
    'tests/baseline/global.json' = 'global.json'
    'scripts/Test-Baseline.ps1' = 'Test-Baseline.ps1'
}
# An existing suite (even one with differently named files) is never merged/reset.
$baseline = Join-Path $AppRoot 'tests/baseline'
if (Test-Path -LiteralPath $baseline) {
    throw "Output collision: $baseline already exists. Resume its runner; initialization never overwrites a suite."
}
foreach ($relative in $outputs.Keys) {
    $target = Join-Path $AppRoot $relative
    if (-not (Test-Path -LiteralPath (Join-Path $templates $outputs[$relative]) -PathType Leaf)) {
        throw "Missing bootstrap template: $($outputs[$relative])"
    }
    if (Test-Path -LiteralPath $target) { throw "Output collision: $target" }
    $parent = Split-Path -Parent $target
    while ($parent -and $parent -ne $AppRoot) {
        if (Test-Path -LiteralPath $parent) {
            $item = Get-Item -LiteralPath $parent -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Output collision or linked ancestor: $parent"
            }
        }
        $parent = Split-Path -Parent $parent
    }
}
$createdFiles = [Collections.Generic.List[string]]::new()
$createdDirectories = [Collections.Generic.List[string]]::new()
try {
    foreach ($relative in $outputs.Keys) {
        $target = Join-Path $AppRoot $relative
        $missing = [Collections.Generic.List[string]]::new()
        $parent = Split-Path -Parent $target
        while (-not (Test-Path -LiteralPath $parent)) {
            $missing.Add($parent)
            $parent = Split-Path -Parent $parent
        }
        for ($i = $missing.Count - 1; $i -ge 0; $i--) {
            [IO.Directory]::CreateDirectory($missing[$i]) | Out-Null
            $createdDirectories.Add($missing[$i])
        }
        $bytes = [IO.File]::ReadAllBytes((Join-Path $templates $outputs[$relative]))
        $stream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $createdFiles.Add($target)
        try { $stream.Write($bytes) } finally { $stream.Dispose() }
    }
} catch {
    # Roll back only paths this invocation created, never pre-existing content.
    foreach ($file in $createdFiles) { [IO.File]::Delete($file) }
    for ($i = $createdDirectories.Count - 1; $i -ge 0; $i--) {
        if ([IO.Directory]::GetFileSystemEntries($createdDirectories[$i]).Length -eq 0) {
            [IO.Directory]::Delete($createdDirectories[$i])
        }
    }
    throw
}
Write-Host 'Created generic HTTP harness only. Author contract.md and real characterization tests from source and observed behavior before running it.'
$outputs.Keys
