#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Legacy', 'Python')]
    [string]$Target,
    [string]$AppRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Freeze
)

$ErrorActionPreference = 'Stop'
$AppRoot = (Resolve-Path -LiteralPath $AppRoot).Path
$baseline = Join-Path $AppRoot 'tests\baseline'
$project = Join-Path $baseline 'OrderDesk.Baseline.Tests.csproj'
$upgrade = Join-Path $AppRoot '.github\upgrades\dotnet-to-fastapi'
$manifestPath = Join-Path $upgrade 'baseline-files.json'
$reportPath = Join-Path $upgrade 'baseline-report.md'

function Get-BaselineSnapshot {
    if (-not (Test-Path -LiteralPath $project -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $baseline 'contract.md') -PathType Leaf)) {
        throw 'The baseline test project and contract.md are required.'
    }
    $files = @(Get-ChildItem -LiteralPath $baseline -Recurse -File | Where-Object {
        $relative = [IO.Path]::GetRelativePath($baseline, $_.FullName).Replace('\', '/')
        $relative -notmatch '(^|/)(bin|obj|TestResults)/' -and
        ($relative -eq 'contract.md' -or $_.Extension -in '.cs', '.csproj')
    } | Sort-Object FullName)
    if (@($files | Where-Object Extension -eq '.cs').Count -eq 0) {
        throw 'No baseline C# test sources were found.'
    }
    foreach ($file in $files) {
        [ordered]@{
            path = [IO.Path]::GetRelativePath($AppRoot, $file.FullName).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}

function Assert-SameSnapshot($Expected, $Actual) {
    $known = @{}
    foreach ($file in $Expected) {
        if ($file.path -notmatch '^tests/baseline/(?!.*(?:^|/)\.\.(?:/|$)).+\.(cs|csproj|md)$' -or
            $file.sha256 -notmatch '^[a-f0-9]{64}$' -or $known.ContainsKey([string]$file.path)) {
            throw 'Invalid baseline freeze: unsafe/duplicate path or invalid SHA256.'
        }
        $known[[string]$file.path] = [string]$file.sha256
    }
    $current = @{}
    foreach ($file in $Actual) { $current[[string]$file.path] = [string]$file.sha256 }
    $differences = @(
        foreach ($path in $known.Keys) {
            if (-not $current.ContainsKey($path)) { "missing: $path" }
            elseif ($current[$path] -cne $known[$path]) { "modified: $path" }
        }
        foreach ($path in $current.Keys) {
            if (-not $known.ContainsKey($path)) { "added: $path" }
        }
    )
    if ($known.Count -eq 0 -or $differences.Count -gt 0) {
        throw "Baseline integrity check failed: $($differences -join '; '). Do not refresh the freeze to bypass a mismatch."
    }
}

function Read-Trx([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "No real TRX was produced: $Path"
    }
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    $xml = [Xml.XmlDocument]::new()
    $xml.XmlResolver = $null
    try { $xml.Load($reader) } finally { $reader.Dispose() }
    $ns = [Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('t', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
    $summary = $xml.SelectSingleNode('/t:TestRun/t:ResultSummary', $ns)
    $counters = $xml.SelectSingleNode('/t:TestRun/t:ResultSummary/t:Counters', $ns)
    $results = @($xml.SelectNodes('/t:TestRun/t:Results/t:UnitTestResult', $ns))
    $definitions = @($xml.SelectNodes('/t:TestRun/t:TestDefinitions/t:UnitTest', $ns))
    if ($null -eq $summary -or $null -eq $counters) { throw 'TRX has no result summary/counters.' }
    $counts = @{}
    foreach ($attribute in $counters.Attributes) {
        [long]$count = 0
        if (-not [long]::TryParse($attribute.Value, [ref]$count) -or $count -lt 0) {
            throw "Invalid TRX counter: $($attribute.Name)"
        }
        $counts[$attribute.Name] = $count
    }
    foreach ($name in @('total', 'executed', 'passed', 'failed')) {
        if (-not $counts.ContainsKey($name)) { throw "TRX is missing its $name counter." }
    }
    $names = @($results | ForEach-Object { $_.GetAttribute('testName') })
    $problems = @(
        if ($counts.total -le 0 -or $results.Count -eq 0 -or $definitions.Count -eq 0) {
            'zero discovered/executed tests'
        }
        if ($counts.total -ne $results.Count -or $counts.executed -ne $counts.total -or
            $counts.passed -ne $counts.total) { 'inconsistent or incomplete result counters' }
        if ($definitions.Count -ne $results.Count) { 'discovered definitions and results do not match' }
        foreach ($name in $counts.Keys) {
            if ($name -notin 'total', 'executed', 'passed' -and $counts[$name] -ne 0) {
                "$name=$($counts[$name])"
            }
        }
        if ($summary.GetAttribute('outcome') -notin 'Passed', 'Completed') { 'run outcome is not successful' }
        foreach ($result in $results) {
            if ($result.GetAttribute('outcome') -cne 'Passed') {
                "$($result.GetAttribute('testName')): $($result.GetAttribute('outcome'))"
            }
        }
        if (@($names | Sort-Object -Unique).Count -ne $names.Count) { 'duplicate report IDs' }
        if (@($names | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -match '[^\x20-\x7e]' }).Count) {
            'empty or non-report-safe test names'
        }
    )
    [ordered]@{
        total = $counts.total
        passed = $counts.passed
        failed = $counts.failed
        discovered = $definitions.Count
        testNames = $names
        problems = $problems
    }
}

function Write-BaselineReport($Result, $Snapshot) {
    $state = @{ schemaVersion = 1; results = @{} }
    if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
        $prior = [IO.File]::ReadAllText($reportPath)
        $match = [regex]::Match($prior,
            '(?s)<!-- baseline-results:start -->\s*```json\s*(.*?)\s*```\s*<!-- baseline-results:end -->')
        if (-not $match.Success) { throw 'Existing baseline report has no readable outcome record; refusing to discard it.' }
        $state = ConvertFrom-Json -InputObject $match.Groups[1].Value -AsHashtable
        if ($state.schemaVersion -ne 1 -or $state.results -isnot [Collections.IDictionary]) {
            throw 'Existing baseline report has an unsupported outcome record.'
        }
    }
    $state.results[$Target] = $Result
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# OrderDesk HTTP baseline results')
    $lines.Add('')
    $lines.Add('Real external-host HTTP results. Guardrails detect baseline changes; they are not tamper-proof security.')
    $lines.Add('')
    $lines.Add('| Phase | Outcome | Passed / total | Failed | Discovered | TRX |')
    $lines.Add('| --- | --- | --- | --- | --- | --- |')
    foreach ($mode in @('Legacy', 'Python')) {
        $phase = if ($mode -eq 'Legacy') { 'Before (Legacy)' } else { 'After (Python)' }
        if ($state.results.ContainsKey($mode)) {
            $run = $state.results[$mode]
            $lines.Add("| $phase | $($run.outcome) | $($run.passed) / $($run.total) | $($run.failed) | $($run.discovered) | $($run.trx) |")
        } else { $lines.Add("| $phase | Not run | - | - | - | - |") }
    }
    $lines.Add('')
    $lines.Add('## Baseline source hashes')
    $lines.Add('')
    $lines.Add('Only contract.md, .cs, and .csproj under tests/baseline; bin/obj/TestResults are excluded.')
    $lines.Add('The result record preserves each run''s before/after source hashes and exact command/test names.')
    $lines.Add('')
    $lines.Add('| Relative path | SHA256 |')
    $lines.Add('| --- | --- |')
    foreach ($file in $Snapshot) { $lines.Add("| $($file.path) | $($file.sha256) |") }
    $lines.Add('')
    $lines.Add('<!-- baseline-results:start -->')
    $lines.Add('```json')
    $lines.Add(($state | ConvertTo-Json -Depth 20))
    $lines.Add('```')
    $lines.Add('<!-- baseline-results:end -->')
    [IO.File]::WriteAllText($reportPath, ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
}

if ($Freeze -and $Target -ne 'Legacy') { throw '-Freeze is supported only for a successful Legacy baseline.' }
$before = @(Get-BaselineSnapshot)
$frozen = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $frozen = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($frozen.schemaVersion -ne 1 -or $frozen.frozenByTarget -cne 'Legacy' -or
        $frozen.expectedTestCount -le 0 -or @($frozen.expectedTestNames).Count -ne $frozen.expectedTestCount) {
        throw 'Unsupported baseline freeze.'
    }
    Assert-SameSnapshot $frozen.files $before
    if ($Freeze) { throw 'A baseline freeze already exists. Refusing to overwrite it; run Legacy without -Freeze.' }
} elseif ($Target -eq 'Python') { throw 'Python requires a frozen successful Legacy baseline. Run Legacy -Freeze first.' }

$environmentNames = @('ORDERDESK_HOST_EXE', 'ORDERDESK_HOST_ARGS', 'ORDERDESK_HOST_WORKDIR', 'ORDERDESK_BASE_URL')
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$locationPushed = $false
try {
    Push-Location -LiteralPath $AppRoot
    $locationPushed = $true
    if ($Target -eq 'Legacy') {
        & (Join-Path $AppRoot 'scripts\Build-Legacy.ps1') -AppRoot $AppRoot
        if ($LASTEXITCODE -ne 0) { throw "Legacy build failed with exit code $LASTEXITCODE." }
        $hostExe = Join-Path $AppRoot 'src\OrderDesk.Legacy\bin\Debug\OrderDesk.Legacy.exe'
        $baseUrl = 'http://localhost:5088/'
        $hostArguments = @('--url', $baseUrl)
    } else {
        $hostExe = Join-Path $AppRoot '.venv\Scripts\python.exe'
        foreach ($required in @('src\orderdesk_python\app.py', 'requirements.txt', '.venv\Scripts\python.exe')) {
            if (-not (Test-Path -LiteralPath (Join-Path $AppRoot $required) -PathType Leaf)) {
                throw "Python target is not generated/prepared: missing $required. Generate the independent port and its local .venv during the exercise."
            }
        }
        & $hostExe -m compileall -q (Join-Path $AppRoot 'src\orderdesk_python')
        if ($LASTEXITCODE -ne 0) { throw "Python module compilation failed with exit code $LASTEXITCODE." }
        & $hostExe -m pip check
        if ($LASTEXITCODE -ne 0) { throw "Python pip check failed with exit code $LASTEXITCODE." }
        $baseUrl = 'http://localhost:5089/'
        $hostArguments = @('-m', 'uvicorn', 'orderdesk_python.app:app', '--app-dir', 'src',
            '--host', 'localhost', '--port', '5089', '--workers', '1')
    }
    [Environment]::SetEnvironmentVariable('ORDERDESK_HOST_EXE', $hostExe, 'Process')
    [Environment]::SetEnvironmentVariable('ORDERDESK_HOST_ARGS', (ConvertTo-Json -InputObject $hostArguments -Compress), 'Process')
    [Environment]::SetEnvironmentVariable('ORDERDESK_HOST_WORKDIR', $AppRoot, 'Process')
    [Environment]::SetEnvironmentVariable('ORDERDESK_BASE_URL', $baseUrl, 'Process')

    $runName = "$Target-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))-$([Guid]::NewGuid().ToString('N'))"
    $resultsDirectory = Join-Path $baseline "TestResults\$runName"
    New-Item -ItemType Directory -Path $resultsDirectory | Out-Null
    & dotnet test $project --logger 'trx;LogFileName=baseline.trx' --results-directory $resultsDirectory --verbosity minimal
    $testExit = $LASTEXITCODE
    $trxPath = Join-Path $resultsDirectory 'baseline.trx'
    $validation = $null
    $problems = [Collections.Generic.List[string]]::new()
    if ($testExit -ne 0) { $problems.Add("dotnet test exited $testExit.") }
    try {
        $validation = Read-Trx $trxPath
        foreach ($problem in $validation.problems) { $problems.Add($problem) }
        if ($null -ne $frozen -and
            ($validation.total -ne $frozen.expectedTestCount -or
            @(Compare-Object -ReferenceObject @($frozen.expectedTestNames) -DifferenceObject @($validation.testNames)).Count -ne 0)) {
            $problems.Add('Test discovery/report IDs do not match the frozen successful Legacy run.')
        }
    } catch { $problems.Add($_.Exception.Message) }
    $after = @(Get-BaselineSnapshot)
    try {
        Assert-SameSnapshot $before $after
        if ($null -ne $frozen) { Assert-SameSnapshot $frozen.files $after }
    } catch { $problems.Add($_.Exception.Message) }
    $outcome = if ($problems.Count -eq 0) { 'Passed' } else { 'Failed' }
    $result = [ordered]@{
        outcome = $outcome
        completedAtUtc = [DateTime]::UtcNow.ToString('o')
        command = "& '$PSCommandPath' -Target $Target -AppRoot '$AppRoot'$(if ($Freeze) { ' -Freeze' })"
        testCommand = "dotnet test '$project' --logger 'trx;LogFileName=baseline.trx' --results-directory '$resultsDirectory' --verbosity minimal"
        exitCode = $testExit
        total = if ($null -ne $validation) { $validation.total } else { 0 }
        passed = if ($null -ne $validation) { $validation.passed } else { 0 }
        failed = if ($null -ne $validation) { $validation.failed } else { 0 }
        discovered = if ($null -ne $validation) { $validation.discovered } else { 0 }
        trx = [IO.Path]::GetRelativePath($AppRoot, $trxPath).Replace('\', '/')
        testNames = if ($null -ne $validation) { $validation.testNames } else { @() }
        problems = @($problems.ToArray())
        beforeHashes = $before
        afterHashes = $after
    }
    New-Item -ItemType Directory -Path $upgrade -Force | Out-Null
    Write-BaselineReport $result $after
    if ($problems.Count -gt 0) { throw "Baseline validation failed: $($problems -join '; ')" }
    if ($Freeze) {
        $manifest = [ordered]@{
            schemaVersion = 1
            frozenByTarget = 'Legacy'
            frozenAtUtc = [DateTime]::UtcNow.ToString('o')
            files = $after
            expectedTestCount = $validation.total
            expectedTestNames = $validation.testNames
        } | ConvertTo-Json -Depth 10
        # CreateNew refuses a concurrent/existing freeze rather than silently refreshing it.
        $stream = [IO.File]::Open($manifestPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
            try { $writer.WriteLine($manifest) } finally { $writer.Dispose() }
        } finally { $stream.Dispose() }
    }
    Write-Host "$Target baseline: $($validation.passed)/$($validation.total) passed; $($validation.discovered) discovered; no skips/incomplete outcomes."
    if ($Freeze) { Write-Host "Frozen baseline: $manifestPath" }
} finally {
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    if ($locationPushed) { Pop-Location }
}
