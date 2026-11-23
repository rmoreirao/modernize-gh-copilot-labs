#requires -Version 7.0
[CmdletBinding()]
param([string]$ScratchRoot = (Join-Path ([IO.Path]::GetTempPath()) "http-baseline-checks-$([Guid]::NewGuid().ToString('N'))"))

$ErrorActionPreference = 'Stop'
if (-not [IO.Path]::IsPathFullyQualified($ScratchRoot)) { throw '-ScratchRoot must be absolute.' }
if ((Test-Path -LiteralPath $ScratchRoot) -and @(Get-ChildItem -LiteralPath $ScratchRoot -Force).Count) {
    throw 'ScratchRoot must be new or empty; never reuse an earlier rehearsal.'
}
[IO.Directory]::CreateDirectory($ScratchRoot) | Out-Null
$resources = Split-Path -Parent $PSScriptRoot
$initializer = Join-Path $resources 'scripts/Initialize-Baseline.ps1'
$templateRunner = Join-Path $resources 'templates/Test-Baseline.ps1'
# Pure report/snapshot functions are also tested against deliberately damaged real reports.
. $templateRunner
$pwsh = (Get-Command pwsh -CommandType Application).Source
$app = Join-Path $ScratchRoot 'external application with spaces'
$baseline = Join-Path $app 'tests/baseline'
$runner = Join-Path $app 'scripts/Test-Baseline.ps1'
$evidence = Join-Path $ScratchRoot 'evidence'
$outcomes = [Collections.Generic.List[object]]::new()

function Assert-Equal($Expected, $Actual, [string]$Because) {
    if ($Expected -cne $Actual) { throw "$Because`: expected <$Expected>, got <$Actual>." }
}
function Assert-True([bool]$Condition, [string]$Because) { if (-not $Condition) { throw $Because } }
function Assert-Rejected([scriptblock]$Action, [string]$Pattern) {
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_ }
    if ($null -eq $failure) { throw "Expected rejection matching: $Pattern" }
    if ($failure.ToString() -notmatch $Pattern) { throw "Unexpected rejection: $failure (expected $Pattern)" }
}
function Check([string]$Name, [scriptblock]$Action) {
    try {
        & $Action | Out-Null
        $outcomes.Add([ordered]@{ name = $Name; outcome = 'Passed' })
        Write-Host "PASS $Name"
    } catch {
        $outcomes.Add([ordered]@{ name = $Name; outcome = 'Failed'; diagnostic = $_.ToString(); stack = $_.ScriptStackTrace })
        Write-Host "FAIL $Name`: $_"
    }
}
function Tree-Hashes([string]$Root) {
    @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
        [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/') + ':' + (Get-BaselineHash $_.FullName)
    }) -join "`n"
}
function New-App([string]$Name) {
    $root = Join-Path $ScratchRoot $Name
    [IO.Directory]::CreateDirectory((Join-Path $root 'src')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'src/Original.cs'), '// immutable source sentinel')
    $root
}
function New-Port {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { $listener.LocalEndpoint.Port } finally { $listener.Stop() }
}
function Copy-Evidence([string]$Name) {
    $destination = Join-Path $ScratchRoot $Name
    [IO.Directory]::CreateDirectory($destination) | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $evidence -Force) {
        if ($item.Name -ne 'baseline-files.json') { Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse }
    }
    $destination
}

Check 'PristineBootstrapPreservesSource' {
    [IO.Directory]::CreateDirectory((Join-Path $app 'src')) | Out-Null
    $source = Join-Path $app 'src/Original.cs'
    [IO.File]::WriteAllText($source, '// unmodified application source')
    $hash = Get-BaselineHash $source
    & $initializer -AppRoot $app
    Assert-Equal $hash (Get-BaselineHash $source) 'Bootstrap source integrity'
    $files = @(Get-ChildItem -LiteralPath $baseline -File).Name | Sort-Object
    Assert-Equal 'ExternalHost.cs,global.json,HttpBaseline.Tests.csproj' ($files -join ',') 'Only harness files'
    Assert-Equal (Get-BaselineHash $templateRunner) (Get-BaselineHash $runner) 'Exact runner template'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $app 'global.json'))) 'No SDK pin at application root'
}
Check 'CollisionPreflightIsAtomic' {
    foreach ($collision in @('ExistingRunner', 'ExistingSuite', 'AncestorFile')) {
        $root = New-App $collision
        switch ($collision) {
            'ExistingRunner' {
                [IO.Directory]::CreateDirectory((Join-Path $root 'scripts')) | Out-Null
                [IO.File]::WriteAllText((Join-Path $root 'scripts/Test-Baseline.ps1'), 'do not overwrite')
            }
            'ExistingSuite' {
                [IO.Directory]::CreateDirectory((Join-Path $root 'tests/baseline')) | Out-Null
                [IO.File]::WriteAllText((Join-Path $root 'tests/baseline/unrelated.txt'), 'keep unrelated tests')
            }
            'AncestorFile' { [IO.File]::WriteAllText((Join-Path $root 'tests'), 'not a directory') }
        }
        $before = Tree-Hashes $root
        Assert-Rejected { & $initializer -AppRoot $root } 'collision'
        Assert-Equal $before (Tree-Hashes $root) "Atomic preflight $collision"
    }
    $before = Tree-Hashes $app
    Assert-Rejected { & $initializer -AppRoot $app } 'collision'
    Assert-Equal $before (Tree-Hashes $app) 'Repeated initializer preserves all files'
}
Check 'ScaffoldsContainNoBusinessCases' {
    $content = @(Get-ChildItem -LiteralPath (Join-Path $resources 'templates') -File | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
    Assert-True ($content -notmatch '\[(Fact|Theory)|InlineData|api/products|api/orders|Notebook|Pencil|FastAPI|uvicorn|python|Invalid order|Insufficient stock') 'No app-specific scenarios/target launcher or passing placeholders'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $baseline 'contract.md'))) 'No prewritten contract'
    Assert-True ($content.Contains('ORDERDESK_READY_PATH')) 'Readiness must be configured'
}

$port = New-Port
$probeArguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'LoopbackProbe.ps1'),
    '-Port', [string]$port, '-StateRoot', (Join-Path $ScratchRoot 'runner-host'))
$common = @{
    AppRoot = $app; HostExecutable = $pwsh
    HostArgumentsJson = (ConvertTo-Json -InputObject $probeArguments -Compress)
    BaseUrl = "http://127.0.0.1:$port/"; ReadyPath = '/probe-ready'
    EvidenceDirectory = $evidence
}
Check 'PrerequisitesFailExplicitly' {
    Assert-Rejected { & $initializer -AppRoot 'relative-app' } 'absolute'
    Assert-Rejected { & $runner @common -Phase Before } 'contract.md'
    [IO.File]::WriteAllText((Join-Path $baseline 'contract.md'), '# Test-only probe contract: configured readiness returns value 37.')
    $source = Join-Path $baseline 'FixtureProbes.cs'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'FixtureProbes.cs') -Destination $source
    Assert-Rejected { & $runner @common -Phase After } 'requires a valid frozen'
    foreach ($item in @(
        @{ key = 'HostExecutable'; value = (Join-Path $ScratchRoot 'absent.exe'); error = 'HostExecutable' },
        @{ key = 'HostWorkingDirectory'; value = (Join-Path $ScratchRoot 'absent-workdir'); error = 'HostWorkingDirectory' },
        @{ key = 'HostArgumentsJson'; value = '{}'; error = 'JSON string array' },
        @{ key = 'HostArgumentsJson'; value = '[null]'; error = 'JSON string array' },
        @{ key = 'HostArgumentsJson'; value = '[23]'; error = 'JSON string array' },
        @{ key = 'HostArgumentsJson'; value = 'not-json'; error = 'JSON string array' },
        @{ key = 'BaseUrl'; value = 'https://127.0.0.1/'; error = 'loopback root' },
        @{ key = 'BaseUrl'; value = 'http://example.invalid/'; error = 'loopback root' },
        @{ key = 'BaseUrl'; value = 'http://127.0.0.1/path'; error = 'loopback root' },
        @{ key = 'ReadyPath'; value = '//example.invalid/'; error = 'same-host GET path' },
        @{ key = 'ReadyPath'; value = ''; error = 'same-host GET path' },
        @{ key = 'EvidenceDirectory'; value = (Join-Path $baseline 'reports'); error = 'outside BaselineRoot' },
        @{ key = 'EvidenceDirectory'; value = (Join-Path $baseline '..reports'); error = 'outside BaselineRoot' }
    )) {
        $invalid = $common.Clone()
        $invalid[$item.key] = $item.value
        Assert-Rejected { & $runner @invalid -Phase Before } $item.error
    }
    foreach ($missing in @('contract.md', 'global.json', 'HttpBaseline.Tests.csproj')) {
        $file = Join-Path $baseline $missing
        $bytes = [IO.File]::ReadAllBytes($file)
        [IO.File]::Delete($file) # This is our isolated scratch, never repository content.
        try { Assert-Rejected { & $runner @common -Phase Before } 'prerequisite' }
        finally { [IO.File]::WriteAllBytes($file, $bytes) }
    }
    $path = $env:PATH
    try {
        $env:PATH = ''
        Assert-Rejected { & $runner @common -Phase Before } 'dotnet SDK is required'
    } finally { $env:PATH = $path }
    Assert-True (-not (Test-Path -LiteralPath $evidence)) 'Prerequisite failures do not manufacture result records'
}

$environmentKeys = @('HTTP_BASELINE_PROBE_EXE', 'HTTP_BASELINE_PROBE_SCRIPT', 'HTTP_BASELINE_SCRATCH')
$saved = @{}
foreach ($key in $environmentKeys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    $env:HTTP_BASELINE_PROBE_EXE = $pwsh
    $env:HTTP_BASELINE_PROBE_SCRIPT = Join-Path $PSScriptRoot 'LoopbackProbe.ps1'
    $env:HTTP_BASELINE_SCRATCH = Join-Path $ScratchRoot 'owned-hosts'
    [IO.Directory]::CreateDirectory($env:HTTP_BASELINE_SCRATCH) | Out-Null
    Check 'FreezeRequiresRealPassingBefore' {
        Assert-Rejected { & $runner -AppRoot $app -EvidenceDirectory $evidence -Freeze } 'missing'
        & $runner @common -Phase Before
        $state = Read-BaselineJson (Join-Path $evidence 'baseline-results.json')
        $record = Read-BaselineJson (Get-BaselineEvidencePath $evidence $state.results.Before 'run.json')
        Assert-Equal 'Passed' $record.outcome 'Real Before outcome'
        Assert-Equal 10 $record.validation.total 'Ten actual lifecycle/configuration cases'
        Assert-Equal 10 $record.validation.passed 'All actual lifecycle/configuration cases pass'
        Assert-Equal $baseline $record.testWorkingDirectory 'SDK pin resolved from baseline-local working directory'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $evidence 'baseline-files.json'))) 'Before does not imply review/freeze'
        $recordPath = Get-BaselineEvidencePath $evidence $state.results.Before 'run.json'
        $trx = Get-BaselineEvidencePath $evidence $state.results.Before 'baseline.trx'
        $recordHash = Get-BaselineHash $recordPath
        $trxHash = Get-BaselineHash $trx
        & $runner -AppRoot $app -EvidenceDirectory $evidence -Freeze
        Assert-Equal $recordHash (Get-BaselineHash $recordPath) 'Freeze does not rerun or replace evidence record'
        Assert-Equal $trxHash (Get-BaselineHash $trx) 'Freeze does not rerun or replace real TRX'
        $manifest = Read-BaselineJson (Join-Path $evidence 'baseline-files.json')
        Assert-Equal 10 $manifest.expectedTestCount 'No required 42-case count'
        Assert-BaselineIdentities $record.validation.testIdentities $manifest.testIdentities
        Assert-Equal 1 @(Get-ChildItem -LiteralPath (Join-Path $evidence 'runs') -Directory).Count 'Freeze did not create another run'
    }

    $state = Read-BaselineJson (Join-Path $evidence 'baseline-results.json')
    $goodTrx = Get-BaselineEvidencePath $evidence $state.results.Before 'baseline.trx'
    $variants = [ordered]@{
        Zero = { param($x) $c = $x.TestRun.ResultSummary.Counters; $c.total = '0'; $c.executed = '0'; $c.passed = '0' }
        Failed = { param($x) $x.TestRun.Results.UnitTestResult[0].outcome = 'Failed'; $x.TestRun.ResultSummary.Counters.failed = '1' }
        Skipped = { param($x) $x.TestRun.Results.UnitTestResult[0].outcome = 'NotExecuted'; $x.TestRun.ResultSummary.Counters.notExecuted = '1' }
        NonPassingResultWithGreenCounters = { param($x) $x.TestRun.Results.UnitTestResult[0].outcome = 'NotExecuted' }
        Incomplete = { param($x) $x.TestRun.ResultSummary.Counters.executed = '8' }
        MissingDefinition = { param($x) $n = $x.TestRun.TestDefinitions.UnitTest[0]; $n.ParentNode.RemoveChild($n) | Out-Null }
        IdentityMismatch = { param($x) $x.TestRun.TestEntries.TestEntry[0].executionId = [Guid]::NewGuid().ToString() }
        DuplicateNames = { param($x) $x.TestRun.Results.UnitTestResult[1].testName = $x.TestRun.Results.UnitTestResult[0].testName }
        UnsafeName = { param($x) $x.TestRun.Results.UnitTestResult[0].testName = "unsafe$([char]0x2603)" }
        NegativeCounter = { param($x) $x.TestRun.ResultSummary.Counters.failed = '-1' }
        FailedSummary = { param($x) $x.TestRun.ResultSummary.outcome = 'Failed' }
    }
    foreach ($variant in $variants.Keys) {
        Check "TrxRejects$variant" {
            [xml]$xml = [IO.File]::ReadAllText($goodTrx)
            & $variants[$variant] $xml
            $damaged = Join-Path $ScratchRoot "damaged-$variant.trx"
            $xml.Save($damaged)
            Assert-Rejected { Read-BaselineTrx $damaged } 'TRX'
        }
    }
    Check 'FreezeRejectsFailedLatestAndEditedEvidence' {
        foreach ($kind in @('Failed', 'FailedExitCode', 'FailedBuild', 'EditedTrx', 'EditedCount', 'UnsafeRecord')) {
            $copy = Copy-Evidence "evidence-$kind"
            $state = Read-BaselineJson (Join-Path $copy 'baseline-results.json')
            $recordPath = Get-BaselineEvidencePath $copy $state.results.Before 'run.json'
            $record = Read-BaselineJson $recordPath
            switch ($kind) {
                'Failed' { $record.outcome = 'Failed'; Write-BaselineJson $recordPath $record }
                'FailedExitCode' { $record.exitCode = 1; Write-BaselineJson $recordPath $record }
                'FailedBuild' { $record.buildExitCode = 1; Write-BaselineJson $recordPath $record }
                'EditedTrx' { [IO.File]::AppendAllText((Get-BaselineEvidencePath $copy $state.results.Before 'baseline.trx'), ' ') }
                'EditedCount' { $record.validation.total = 42; Write-BaselineJson $recordPath $record }
                'UnsafeRecord' { $state.results.Before = '../outside.json'; Write-BaselineJson (Join-Path $copy 'baseline-results.json') $state }
            }
            Assert-Rejected { & $runner -AppRoot $app -EvidenceDirectory $copy -Freeze } 'passing Before|TRX|Unsafe evidence'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $copy 'baseline-files.json'))) "No invalid freeze: $kind"
        }
    }
    Check 'FreezeRejectsInputEditsBeforeApproval' {
        $copy = Copy-Evidence 'evidence-before-approval-edit'
        $contract = Join-Path $baseline 'contract.md'
        $bytes = [IO.File]::ReadAllBytes($contract)
        try {
            [IO.File]::AppendAllText($contract, "`nChanged after passing Before.")
            Assert-Rejected { & $runner -AppRoot $app -EvidenceDirectory $copy -Freeze } 'modified'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $copy 'baseline-files.json'))) 'Edited inputs cannot be approved from stale evidence'
        } finally { [IO.File]::WriteAllBytes($contract, $bytes) }
    }
    Check 'AfterRejectsFrozenRecordAndTrxTampering' {
        foreach ($kind in @('Record', 'Trx')) {
            $copy = Copy-Evidence "frozen-tamper-$kind"
            Copy-Item -LiteralPath (Join-Path $evidence 'baseline-files.json') -Destination $copy
            $manifest = Read-BaselineJson (Join-Path $copy 'baseline-files.json')
            $file = if ($kind -eq 'Record') { 'run.json' } else { 'baseline.trx' }
            [IO.File]::AppendAllText((Get-BaselineEvidencePath $copy $manifest.beforeRecord $file), ' ')
            $invalid = $common.Clone()
            $invalid.EvidenceDirectory = $copy
            Assert-Rejected { & $runner @invalid -Phase After } 'has changed'
            Assert-Equal 0 @(Get-ChildItem -LiteralPath (Join-Path $copy 'runs') -Directory -Filter 'After-*').Count 'No After is run from edited evidence'
        }
    }
    Check 'RunnerRejectsOccupiedPortWithoutReusingOwner' {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $invalid = $common.Clone()
            $invalid.BaseUrl = "http://127.0.0.1:$($listener.LocalEndpoint.Port)/"
            Assert-Rejected { & $runner @invalid -Phase Before } 'occupied'
            $client = [Net.Sockets.TcpClient]::new()
            try {
                $client.Connect([Net.IPAddress]::Loopback, $listener.LocalEndpoint.Port)
                $accepted = $listener.AcceptTcpClient()
                try { Assert-True $accepted.Connected 'Runner leaves unowned listener functional' }
                finally { $accepted.Dispose() }
            } finally { $client.Dispose() }
        } finally { $listener.Stop() }
    }
    Check 'FrozenInputsRejectTamperAddDelete' {
        foreach ($file in @('contract.md', 'ExternalHost.cs', 'HttpBaseline.Tests.csproj', 'global.json', 'FixtureProbes.cs', 'Runner')) {
            if ($file -eq 'Runner') { $target = $runner } else { $target = Join-Path $baseline $file }
            $bytes = [IO.File]::ReadAllBytes($target)
            try {
                [IO.File]::AppendAllText($target, "`n ")
                Assert-Rejected { & $runner @common -Phase After } 'modified'
            } finally { [IO.File]::WriteAllBytes($target, $bytes) }
        }
        $extra = Join-Path $baseline 'additional-fixture.json'
        [IO.File]::WriteAllText($extra, '{"changed":true}')
        try { Assert-Rejected { & $runner @common -Phase After } 'added' }
        finally { [IO.File]::Delete($extra) }
        $source = Join-Path $baseline 'FixtureProbes.cs'
        $bytes = [IO.File]::ReadAllBytes($source)
        [IO.File]::Delete($source)
        try { Assert-Rejected { & $runner @common -Phase After } 'missing' }
        finally { [IO.File]::WriteAllBytes($source, $bytes) }
        $manifest = Read-BaselineJson (Join-Path $evidence 'baseline-files.json')
        Assert-BaselineSnapshot $manifest.files @(Get-BaselineSnapshot $baseline $runner)
    }
    Check 'RefreezeIsRejected' {
        $path = Join-Path $evidence 'baseline-files.json'
        $hash = Get-BaselineHash $path
        Assert-Rejected { & $runner -AppRoot $app -EvidenceDirectory $evidence -Freeze } 'already exists'
        Assert-Equal $hash (Get-BaselineHash $path) 'Never overwrite freeze'
    }
    Check 'SnapshotRejectsUnsafeIdentifiers' {
        $snapshot = @(Get-BaselineSnapshot $baseline $runner)
        foreach ($id in @('baseline/../outside.cs', 'baseline//test.cs', 'C:/outside.cs', 'baseline/a\b.cs')) {
            Assert-Rejected { Assert-BaselineSnapshot @(@{ id = $id; sha256 = ('a' * 64) }) $snapshot } 'unsafe'
        }
    }
    Check 'ResumeAndAfterKeepExpectations' {
        $hash = Get-BaselineHash (Join-Path $evidence 'baseline-files.json')
        $inputHashes = @(Get-BaselineSnapshot $baseline $runner)
        & $runner @common -Phase Before
        $differentLaunch = $common.Clone()
        $newPort = New-Port
        $differentLaunch.BaseUrl = "http://127.0.0.1:$newPort/"
        $differentArguments = $probeArguments.Clone()
        $differentArguments[4] = [string]$newPort
        $differentLaunch.HostArgumentsJson = ConvertTo-Json -InputObject $differentArguments -Compress
        $differentLaunch.HostWorkingDirectory = $ScratchRoot
        & $runner @differentLaunch -Phase After
        Assert-Equal $hash (Get-BaselineHash (Join-Path $evidence 'baseline-files.json')) 'Resume/After preserve approved freeze'
        Assert-BaselineSnapshot $inputHashes @(Get-BaselineSnapshot $baseline $runner)
        $state = Read-BaselineJson (Join-Path $evidence 'baseline-results.json')
        $before = Read-BaselineJson (Get-BaselineEvidencePath $evidence $state.results.Before 'run.json')
        $after = Read-BaselineJson (Get-BaselineEvidencePath $evidence $state.results.After 'run.json')
        Assert-Equal 'Passed' $before.outcome 'Resume actual outcome'
        Assert-Equal 'Passed' $after.outcome 'After actual outcome'
        Assert-Equal 10 $after.validation.passed 'After actual count'
        Assert-BaselineIdentities $before.validation.testIdentities $after.validation.testIdentities
    }

    Check 'RealZeroFailedSkippedRunsCannotFreeze' {
        $root = New-App 'real-negative-outcomes'
        & $initializer -AppRoot $root
        $testRoot = Join-Path $root 'tests/baseline'
        $negativeRunner = Join-Path $root 'scripts/Test-Baseline.ps1'
        [IO.File]::WriteAllText((Join-Path $testRoot 'contract.md'), '# Tooling negative outcome probes, not application expectations.')
        $file = Join-Path $testRoot 'OutcomeProbe.cs'
        $cases = [ordered]@{
            Zero = 'using Xunit; public class OutcomeProbe { }'
            Failed = 'using Xunit; public class OutcomeProbe { [Fact] public void DeliberateFailure() { Assert.Fail("intentional tooling rejection probe"); } }'
            Skipped = 'using Xunit; public class OutcomeProbe { [Fact(Skip="intentional tooling rejection probe")] public void DeliberateSkip() { } }'
        }
        foreach ($kind in $cases.Keys) {
            [IO.File]::WriteAllText($file, $cases[$kind])
            $negative = $common.Clone()
            $negative.AppRoot = $root
            $negative.EvidenceDirectory = Join-Path $ScratchRoot "real-$kind-evidence"
            Assert-Rejected { & $negativeRunner @negative -Phase Before } 'Baseline validation failed'
            $state = Read-BaselineJson (Join-Path $negative.EvidenceDirectory 'baseline-results.json')
            $record = Read-BaselineJson (Get-BaselineEvidencePath $negative.EvidenceDirectory $state.results.Before 'run.json')
            Assert-Equal 'Failed' $record.outcome "Real $kind is not green"
            $trx = Get-BaselineEvidencePath $negative.EvidenceDirectory $state.results.Before 'baseline.trx'
            [xml]$actual = [IO.File]::ReadAllText($trx)
            $counters = $actual.TestRun.ResultSummary.Counters
            switch ($kind) {
                'Zero' {
                    Assert-Equal '0' $counters.total 'Real zero discovery, not another failure'
                    Assert-Equal '0' $counters.executed 'No hidden execution'
                }
                'Failed' {
                    Assert-Equal '1' $counters.failed 'Real failed test'
                    Assert-Equal 'Failed' $actual.TestRun.Results.UnitTestResult.outcome 'Actual failure outcome'
                    Assert-Equal 'OutcomeProbe.DeliberateFailure' $actual.TestRun.Results.UnitTestResult.testName 'Fresh failure identity'
                }
                'Skipped' {
                    # This pinned adapter emits notExecuted=0 even for a skip.
                    # Validate actual per-test outcome and execution, not that counter alone.
                    Assert-Equal 'NotExecuted' $actual.TestRun.Results.UnitTestResult.outcome 'Real skipped outcome'
                    Assert-Equal '1' $counters.total 'One genuinely discovered skipped test'
                    Assert-Equal '0' $counters.executed 'Skipped test did not execute'
                    Assert-Equal '0' $counters.failed 'Skip is a distinct partition'
                    Assert-Equal 'OutcomeProbe.DeliberateSkip' $actual.TestRun.Results.UnitTestResult.testName 'Fresh skip identity'
                }
            }
            Assert-Rejected { Read-BaselineTrx $trx } 'TRX'
            Assert-Rejected { & $negativeRunner -AppRoot $root -EvidenceDirectory $negative.EvidenceDirectory -Freeze } 'passing Before'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $negative.EvidenceDirectory 'baseline-files.json'))) "Real $kind cannot freeze"
        }
    }
    Check 'DuringRunInputEditIsRecordedAsFailure' {
        $root = New-App 'during-run-edit'
        & $initializer -AppRoot $root
        $testRoot = Join-Path $root 'tests/baseline'
        $contract = Join-Path $testRoot 'contract.md'
        [IO.File]::WriteAllText($contract, '# original contract')
        $literal = ConvertTo-Json -InputObject $contract -Compress
        [IO.File]::WriteAllText((Join-Path $testRoot 'EditProbe.cs'),
            "using Xunit; public class EditProbe { [Fact] public void DeliberateInputEdit() { System.IO.File.AppendAllText($literal, `"changed`"); Assert.EndsWith(`"changed`", System.IO.File.ReadAllText($literal)); } }")
        $negative = $common.Clone()
        $negative.AppRoot = $root
        $negative.EvidenceDirectory = Join-Path $ScratchRoot 'during-run-evidence'
        $negativeRunner = Join-Path $root 'scripts/Test-Baseline.ps1'
        Assert-Rejected { & $negativeRunner @negative -Phase Before } 'modified'
        $state = Read-BaselineJson (Join-Path $negative.EvidenceDirectory 'baseline-results.json')
        $record = Read-BaselineJson (Get-BaselineEvidencePath $negative.EvidenceDirectory $state.results.Before 'run.json')
        Assert-Equal 'Failed' $record.outcome 'A green test cannot hide edited inputs'
        Assert-Equal 1 $record.validation.passed 'Genuine passing test is independently rejected for edited input'
        $priorContract = @($record.beforeHashes | Where-Object id -eq 'baseline/contract.md')[0]
        $afterContract = @($record.afterHashes | Where-Object id -eq 'baseline/contract.md')[0]
        Assert-True ($priorContract.sha256 -cne $afterContract.sha256) 'Record preserves distinct contract hashes'
        Assert-Rejected { & $negativeRunner -AppRoot $root -EvidenceDirectory $negative.EvidenceDirectory -Freeze } 'passing Before'
    }
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}

$failed = @($outcomes | Where-Object outcome -ne 'Passed')
$report = [ordered]@{
    schemaVersion = 1; total = $outcomes.Count; passed = $outcomes.Count - $failed.Count; failed = $failed.Count
    tests = @($outcomes.ToArray()); scratchRoot = $ScratchRoot; evidenceDirectory = $evidence
}
Write-BaselineJson (Join-Path $ScratchRoot 'tooling-results.json') $report
Write-Host "Tooling checks: $($report.passed)/$($report.total) passed. Real report: $ScratchRoot\\tooling-results.json"
if ($failed.Count) { throw "$($failed.Count) tooling regression checks failed; inspect tooling-results.json." }
