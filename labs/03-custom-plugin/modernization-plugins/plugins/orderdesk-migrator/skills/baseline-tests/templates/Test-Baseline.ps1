#requires -Version 7.0
[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [string]$AppRoot,
    [Parameter(ParameterSetName = 'Run')][ValidateSet('Before', 'After')][string]$Phase,
    [Parameter(ParameterSetName = 'Run')][string]$HostExecutable,
    [Parameter(ParameterSetName = 'Run')][string]$HostArgumentsJson,
    [Parameter(ParameterSetName = 'Run')][string]$BaseUrl,
    [Parameter(ParameterSetName = 'Run')][string]$ReadyPath,
    [Parameter(ParameterSetName = 'Run')][string]$HostWorkingDirectory,
    [string]$BaselineRoot,
    [string]$EvidenceDirectory,
    [Parameter(Mandatory, ParameterSetName = 'Freeze')][switch]$Freeze
)

$ErrorActionPreference = 'Stop'

function Get-BaselineHash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-BaselineSnapshot($Expected, $Actual) {
    $known = @{}
    foreach ($file in @($Expected)) {
        $id = [string]$file.id
        $segments = $id.Split('/')
        if (($id -cne 'runner/Test-Baseline.ps1' -and -not $id.StartsWith('baseline/')) -or
            $segments.Count -lt 2 -or
            @($segments | Where-Object { $_ -in '', '.', '..' -or $_ -match '[\\:\x00-\x1f]' }).Count -gt 0 -or
            $file.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $known.ContainsKey($id)) {
            throw 'Invalid baseline snapshot: unsafe/duplicate identifier or invalid SHA256.'
        }
        # Identifiers are compared only; NEVER resolve a manifest path on disk.
        $known[$id] = [string]$file.sha256
    }
    $current = @{}
    foreach ($file in @($Actual)) { $current[[string]$file.id] = [string]$file.sha256 }
    $differences = @(
        foreach ($id in $known.Keys) {
            if (-not $current.ContainsKey($id)) { "missing: $id" }
            elseif ($current[$id] -cne $known[$id]) { "modified: $id" }
        }
        foreach ($id in $current.Keys) {
            if (-not $known.ContainsKey($id)) { "added: $id" }
        }
    )
    if ($known.Count -eq 0 -or $differences.Count -gt 0) {
        throw "Baseline integrity check failed: $($differences -join '; '). Never refresh a freeze to bypass a mismatch."
    }
}

function Get-BaselineSnapshot([string]$Root, [string]$Runner) {
    foreach ($required in @('contract.md', 'global.json')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $required) -PathType Leaf)) {
            throw "Baseline prerequisite missing: $required. Author the contract and characterization tests before running."
        }
    }
    $projects = @(Get-ChildItem -LiteralPath $Root -File -Filter '*.csproj')
    if ($projects.Count -ne 1) { throw 'Baseline prerequisite: exactly one root test .csproj is required.' }
    function Get-Inputs([string]$Directory) {
        foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
            if ($item.PSIsContainer -and $item.Name -in 'bin', 'obj', 'TestResults') { continue }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked baseline input is not supported: $($item.FullName)"
            }
            if ($item.PSIsContainer) { Get-Inputs $item.FullName } else { $item }
        }
    }
    $inputs = @(Get-Inputs $Root | Sort-Object FullName)
    if (@($inputs | Where-Object Extension -eq '.cs').Count -eq 0) { throw 'No baseline C# sources were found.' }
    $snapshot = @(
        foreach ($file in $inputs) {
            [ordered]@{
                id = 'baseline/' + [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
                sha256 = Get-BaselineHash $file.FullName
            }
        }
        [ordered]@{ id = 'runner/Test-Baseline.ps1'; sha256 = Get-BaselineHash $Runner }
    )
    Assert-BaselineSnapshot $snapshot $snapshot
    $snapshot
}

function Read-BaselineTrx([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "No real TRX was produced: $Path" }
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
    $entries = @($xml.SelectNodes('/t:TestRun/t:TestEntries/t:TestEntry', $ns))
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
    $problems = [Collections.Generic.List[string]]::new()
    if ($counts.total -le 0 -or $results.Count -eq 0) { $problems.Add('zero discovered/executed tests') }
    if ($counts.total -ne $results.Count -or $counts.executed -ne $counts.total -or
        $counts.passed -ne $counts.total -or $definitions.Count -ne $results.Count -or
        $entries.Count -ne $results.Count) { $problems.Add('inconsistent or incomplete result counters/definitions/entries') }
    foreach ($name in $counts.Keys) {
        if ($name -notin 'total', 'executed', 'passed' -and $counts[$name] -ne 0) { $problems.Add("$name=$($counts[$name])") }
    }
    if ($summary.GetAttribute('outcome') -notin 'Passed', 'Completed') { $problems.Add('run outcome is not successful') }
    $definitionMap = @{}
    foreach ($definition in $definitions) {
        $id = $definition.GetAttribute('id')
        $method = $definition.SelectSingleNode('t:TestMethod', $ns)
        $execution = $definition.SelectSingleNode('t:Execution', $ns)
        if (-not $id -or $definitionMap.ContainsKey($id) -or $null -eq $method -or $null -eq $execution -or
            -not $method.GetAttribute('className') -or -not $method.GetAttribute('name')) {
            throw 'TRX has invalid/duplicate test definitions.'
        }
        $definitionMap[$id] = @{
            name = $definition.GetAttribute('name')
            method = $method.GetAttribute('className') + '.' + $method.GetAttribute('name')
            execution = $execution.GetAttribute('id')
        }
    }
    $entryMap = @{}
    foreach ($entry in $entries) {
        $id = $entry.GetAttribute('testId')
        if (-not $id -or $entryMap.ContainsKey($id)) { throw 'TRX has invalid/duplicate test entries.' }
        $entryMap[$id] = $entry.GetAttribute('executionId')
    }
    $names = [Collections.Generic.List[string]]::new()
    $identities = [Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($result in $results) {
        $id = $result.GetAttribute('testId')
        $name = $result.GetAttribute('testName')
        $execution = $result.GetAttribute('executionId')
        if ($seen.ContainsKey($id) -or -not $definitionMap.ContainsKey($id) -or -not $entryMap.ContainsKey($id)) {
            throw 'TRX results do not map one-to-one to discovered definitions/entries.'
        }
        $seen[$id] = $true
        if ($result.GetAttribute('outcome') -cne 'Passed') { $problems.Add("$name`: $($result.GetAttribute('outcome'))") }
        if ($name -cne $definitionMap[$id].name -or -not $execution -or
            $execution -cne $definitionMap[$id].execution -or $execution -cne $entryMap[$id]) {
            $problems.Add('TRX definition/result/entry identity mismatch')
        }
        $names.Add($name)
        $identities.Add("$name|$($definitionMap[$id].method)")
    }
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) { $problems.Add('duplicate report IDs') }
    if (@($names | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -match '[^\x20-\x7e]' }).Count) {
        $problems.Add('empty or non-report-safe test names')
    }
    if ($problems.Count) { throw "TRX rejected: $($problems -join '; ')" }
    [ordered]@{
        total = $counts.total; executed = $counts.executed; passed = $counts.passed; failed = $counts.failed
        discovered = $definitions.Count
        testNames = @($names | Sort-Object)
        testIdentities = @($identities | Sort-Object)
    }
}

function Assert-BaselineIdentities($Expected, $Actual) {
    if (@($Expected).Count -eq 0 -or @($Expected).Count -ne @($Actual).Count -or
        @(Compare-Object -ReferenceObject @($Expected) -DifferenceObject @($Actual) -CaseSensitive).Count) {
        throw 'Test discovery/report identities do not match the recorded successful Before run.'
    }
}

function Read-BaselineJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required evidence is missing: $Path" }
    ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Path)) -AsHashtable
}

function Write-BaselineJson([string]$Path, $Value, [switch]$CreateNew) {
    $mode = if ($CreateNew) { [IO.FileMode]::CreateNew } else { [IO.FileMode]::Create }
    $stream = [IO.File]::Open($Path, $mode, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
        try { $writer.WriteLine(($Value | ConvertTo-Json -Depth 30)) } finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-BaselineEvidencePath([string]$Root, [string]$Id, [string]$FileName) {
    # Only runner-issued IDs, not arbitrary paths from the manifest, can be opened.
    if ($Id -cnotmatch '^runs/(Before|After)-[a-f0-9]{32}/run\.json$') { throw 'Unsafe evidence record identifier.' }
    $directory = Join-Path $Root ($Id.Substring(0, $Id.LastIndexOf('/')))
    foreach ($path in @((Join-Path $Root 'runs'), $directory, (Join-Path $directory $FileName))) {
        if ((Test-Path -LiteralPath $path) -and
            ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Linked evidence paths are not supported.'
        }
    }
    Join-Path $directory $FileName
}

function Assert-BaselineBeforeRecord([string]$Evidence, [string]$RecordId, $Snapshot) {
    $recordPath = Get-BaselineEvidencePath $Evidence $RecordId 'run.json'
    $record = Read-BaselineJson $recordPath
    if ($record.schemaVersion -ne 2 -or $record.phase -cne 'Before' -or $record.outcome -cne 'Passed' -or
        $record.exitCode -ne 0 -or $record.buildExitCode -ne 0 -or
        @($record.problems).Count -ne 0 -or $record.trxSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Freeze requires the latest actual passing Before result (no failed/skipped/incomplete outcomes).'
    }
    Assert-BaselineSnapshot $record.beforeHashes $Snapshot
    Assert-BaselineSnapshot $record.afterHashes $Snapshot
    $trxPath = Get-BaselineEvidencePath $Evidence $RecordId 'baseline.trx'
    if ((Get-BaselineHash $trxPath) -cne $record.trxSha256) { throw 'Recorded real Before TRX has changed.' }
    $validation = Read-BaselineTrx $trxPath
    Assert-BaselineIdentities $record.validation.testIdentities $validation.testIdentities
    Assert-BaselineIdentities $record.validation.testNames $validation.testNames
    foreach ($name in @('total', 'executed', 'passed', 'failed', 'discovered')) {
        if ($record.validation[$name] -ne $validation[$name]) { throw "Recorded TRX $name does not match real outcomes." }
    }
    $record
}

function Assert-BaselineFreeze($Manifest, [string]$Evidence, $Snapshot) {
    if ($Manifest.schemaVersion -ne 2 -or $Manifest.beforeRecordSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Unsupported baseline freeze.'
    }
    Assert-BaselineSnapshot $Manifest.files $Snapshot
    $recordPath = Get-BaselineEvidencePath $Evidence $Manifest.beforeRecord 'run.json'
    if ((Get-BaselineHash $recordPath) -cne $Manifest.beforeRecordSha256) { throw 'Frozen Before evidence record has changed.' }
    $record = Assert-BaselineBeforeRecord $Evidence $Manifest.beforeRecord $Snapshot
    Assert-BaselineIdentities $Manifest.testIdentities $record.validation.testIdentities
    Assert-BaselineIdentities $Manifest.testNames $record.validation.testNames
    if ($Manifest.expectedTestCount -ne $record.validation.total) { throw 'Frozen test count does not match real Before TRX.' }
}

# Dot-sourcing exposes the pure validators for focused regression checks, not a bypassing CLI mode.
if ($MyInvocation.InvocationName -eq '.') { return }

if (-not [IO.Path]::IsPathFullyQualified($AppRoot) -or -not (Test-Path -LiteralPath $AppRoot -PathType Container)) {
    throw '-AppRoot must be an absolute existing application directory.'
}
$AppRoot = (Resolve-Path -LiteralPath $AppRoot).Path
if (-not $BaselineRoot) { $BaselineRoot = Join-Path $AppRoot 'tests/baseline' }
if (-not $EvidenceDirectory) { $EvidenceDirectory = Join-Path $AppRoot '.github/upgrades/http-baseline' }
if (-not [IO.Path]::IsPathFullyQualified($BaselineRoot) -or -not (Test-Path -LiteralPath $BaselineRoot -PathType Container)) {
    throw '-BaselineRoot must be an absolute existing test directory.'
}
$BaselineRoot = (Resolve-Path -LiteralPath $BaselineRoot).Path
if (-not [IO.Path]::IsPathFullyQualified($EvidenceDirectory)) { throw '-EvidenceDirectory must be absolute.' }
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\', '/')
$relativeEvidence = [IO.Path]::GetRelativePath($BaselineRoot, $EvidenceDirectory).Replace('\', '/')
if ($relativeEvidence -eq '.' -or (-not [IO.Path]::IsPathRooted($relativeEvidence) -and
    $relativeEvidence -ne '..' -and -not $relativeEvidence.StartsWith('../'))) {
    throw 'EvidenceDirectory must be outside BaselineRoot so generated reports cannot become frozen inputs.'
}
foreach ($path in @($BaselineRoot, $EvidenceDirectory)) {
    $cursor = $path
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Linked baseline/evidence root is not supported: $cursor"
        }
        $cursor = Split-Path -Parent $cursor
    }
}
$snapshot = @(Get-BaselineSnapshot $BaselineRoot $PSCommandPath)
$manifestPath = Join-Path $EvidenceDirectory 'baseline-files.json'
$statePath = Join-Path $EvidenceDirectory 'baseline-results.json'
$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
    if ($Freeze) { throw 'A baseline freeze already exists; refusing to re-freeze or overwrite it.' }
    $manifest = Read-BaselineJson $manifestPath
    Assert-BaselineFreeze $manifest $EvidenceDirectory $snapshot
}
if ($Freeze) {
    $state = Read-BaselineJson $statePath
    if ($state.schemaVersion -ne 2 -or -not $state.results.Before) { throw 'No latest Before result exists to freeze.' }
    $recordId = [string]$state.results.Before
    $record = Assert-BaselineBeforeRecord $EvidenceDirectory $recordId $snapshot
    Assert-BaselineSnapshot $snapshot @(Get-BaselineSnapshot $BaselineRoot $PSCommandPath)
    Write-BaselineJson $manifestPath ([ordered]@{
        schemaVersion = 2; frozenAtUtc = [DateTime]::UtcNow.ToString('o')
        files = $snapshot; expectedTestCount = $record.validation.total
        testNames = $record.validation.testNames; testIdentities = $record.validation.testIdentities
        beforeRecord = $recordId
        beforeRecordSha256 = Get-BaselineHash (Get-BaselineEvidencePath $EvidenceDirectory $recordId 'run.json')
    }) -CreateNew
    Write-Host "Sealed unchanged passing Before evidence without rerunning tests: $manifestPath"
    return
}
if (-not $Phase) { throw '-Phase Before|After is required for a test run.' }
if ($Phase -eq 'After' -and $null -eq $manifest) { throw 'After requires a valid frozen passing Before baseline.' }
if (-not [IO.Path]::IsPathFullyQualified($HostExecutable) -or -not (Test-Path -LiteralPath $HostExecutable -PathType Leaf)) {
    throw '-HostExecutable must name an absolute existing executable.'
}
if (-not $HostWorkingDirectory) { $HostWorkingDirectory = $AppRoot }
if (-not [IO.Path]::IsPathFullyQualified($HostWorkingDirectory) -or -not (Test-Path -LiteralPath $HostWorkingDirectory -PathType Container)) {
    throw '-HostWorkingDirectory must be an absolute existing directory.'
}
try { $arguments = ConvertFrom-Json -InputObject $HostArgumentsJson -NoEnumerate } catch { throw '-HostArgumentsJson must be a JSON string array.' }
if ($arguments -isnot [array] -or @($arguments | Where-Object { $_ -isnot [string] }).Count) {
    throw '-HostArgumentsJson must be a JSON string array (no null/nonstring elements).'
}
$url = $null
if (-not [Uri]::TryCreate($BaseUrl, [UriKind]::Absolute, [ref]$url) -or
    $url.Scheme -ne 'http' -or -not $url.IsLoopback -or $url.AbsolutePath -ne '/' -or
    $url.Query -or $url.Fragment -or $url.UserInfo) { throw '-BaseUrl must be an HTTP loopback root URL.' }
if (-not $ReadyPath -or -not $ReadyPath.StartsWith('/') -or $ReadyPath.StartsWith('//') -or
    $ReadyPath -match '[\\#\x00-\x20]' -or ([Uri]::new($url, $ReadyPath)).Authority -ne $url.Authority) {
    throw '-ReadyPath must be a configured same-host GET path starting with one slash.'
}
if ([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners().Port -contains $url.Port) {
    throw "Port $($url.Port) is occupied; the runner will not reuse or kill its owner."
}
$dotnet = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue
if (-not $dotnet) { throw 'dotnet SDK is required for the separate HTTP test harness.' }
$state = @{ schemaVersion = 2; results = @{} }
if (Test-Path -LiteralPath $statePath) {
    $state = Read-BaselineJson $statePath
    if ($state.schemaVersion -ne 2 -or $state.results -isnot [Collections.IDictionary]) { throw 'Unsupported existing outcome record.' }
}
$runId = "$Phase-$([Guid]::NewGuid().ToString('N'))"
$runDirectory = Join-Path $EvidenceDirectory "runs/$runId"
[IO.Directory]::CreateDirectory($runDirectory) | Out-Null
$trxPath = Join-Path $runDirectory 'baseline.trx'
$project = @(Get-ChildItem -LiteralPath $BaselineRoot -Filter '*.csproj' -File)[0].FullName
$launch = [ordered]@{
    ORDERDESK_HOST_EXE = $HostExecutable; ORDERDESK_HOST_ARGS = $HostArgumentsJson
    ORDERDESK_HOST_WORKDIR = $HostWorkingDirectory; ORDERDESK_BASE_URL = $BaseUrl
    ORDERDESK_READY_PATH = $ReadyPath
}
$saved = @{}
$buildExit = -1
$testExit = -1
$validation = $null
$problems = [Collections.Generic.List[string]]::new()
try {
    foreach ($name in $launch.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $launch[$name], 'Process')
    }
    Push-Location -LiteralPath $BaselineRoot
    try {
        # A hash snapshot alone does not prove an incrementally cached assembly
        # contains those inputs (for example after timestamp-preserving edits).
        & $dotnet.Source build $project --no-incremental --verbosity minimal
        $buildExit = $LASTEXITCODE
        if ($buildExit -eq 0) {
            & $dotnet.Source test $project --logger 'trx;LogFileName=baseline.trx' --results-directory $runDirectory --verbosity minimal
            $testExit = $LASTEXITCODE
        }
    } finally { Pop-Location }
} catch { $problems.Add($_.Exception.Message) } finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
if ($buildExit -ne 0) { $problems.Add("dotnet build --no-incremental exited $buildExit.") }
if ($testExit -ne 0) { $problems.Add("dotnet test exited $testExit.") }
try {
    $validation = Read-BaselineTrx $trxPath
    if ($null -ne $manifest) { Assert-BaselineIdentities $manifest.testIdentities $validation.testIdentities }
} catch { $problems.Add($_.Exception.Message) }
$after = @()
try {
    $after = @(Get-BaselineSnapshot $BaselineRoot $PSCommandPath)
    Assert-BaselineSnapshot $snapshot $after
    if ($null -ne $manifest) { Assert-BaselineFreeze $manifest $EvidenceDirectory $after }
} catch { $problems.Add($_.Exception.Message) }
$outcome = if ($problems.Count) { 'Failed' } else { 'Passed' }
$record = [ordered]@{
    schemaVersion = 2; phase = $Phase; outcome = $outcome; completedAtUtc = [DateTime]::UtcNow.ToString('o')
    buildExitCode = $buildExit; exitCode = $testExit; validation = $validation; problems = @($problems.ToArray())
    beforeHashes = $snapshot; afterHashes = $after
    trxSha256 = if (Test-Path -LiteralPath $trxPath -PathType Leaf) { Get-BaselineHash $trxPath } else { $null }
    testCommand = @($dotnet.Source, 'test', $project, '--logger', 'trx;LogFileName=baseline.trx', '--results-directory', $runDirectory, '--verbosity', 'minimal')
    buildCommand = @($dotnet.Source, 'build', $project, '--no-incremental', '--verbosity', 'minimal')
    testWorkingDirectory = $BaselineRoot; launchConfiguration = $launch
}
Write-BaselineJson (Join-Path $runDirectory 'run.json') $record -CreateNew
$state.results[$Phase] = "runs/$runId/run.json"
Write-BaselineJson $statePath $state
$lines = @('# HTTP characterization results', '', 'Actual outcomes; a freeze is an integrity/review guardrail, not permission enforcement.', '',
    '| Phase | Outcome | Passed / total | Record / real TRX directory |', '| --- | --- | --- | --- |')
foreach ($mode in @('Before', 'After')) {
    if ($state.results[$mode]) {
        $prior = Read-BaselineJson (Get-BaselineEvidencePath $EvidenceDirectory $state.results[$mode] 'run.json')
        $lines += "| $mode | $($prior.outcome) | $($prior.validation.passed) / $($prior.validation.total) | $($state.results[$mode]) |"
    } else { $lines += "| $mode | Not run | - | - |" }
}
[IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'baseline-report.md'), ($lines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
if ($problems.Count) { throw "Baseline validation failed: $($problems -join '; ')" }
Write-Host "$Phase baseline: $($validation.passed)/$($validation.total) passed; $($validation.discovered) discovered; no skips/incomplete outcomes."
