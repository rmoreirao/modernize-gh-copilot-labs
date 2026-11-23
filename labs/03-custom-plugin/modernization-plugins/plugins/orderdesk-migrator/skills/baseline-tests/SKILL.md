---
name: baseline-tests
description: Bootstrap generic HTTP test infrastructure, characterize the observed .NET application, and freeze/recheck a reviewed passing baseline without supplying business assertions.
---

# External HTTP baseline

The application initially has no migration harness. Use the generic resources shipped with this skill; derive the contract and business assertions from `assess-dotnet-api` evidence and actual .NET responses, not from a supplied answer.

## Discover and initialize

Resolve `scripts\Initialize-Baseline.ps1` relative to this loaded skill's actual installed location. Do not guess a cache path. From the application root:

```powershell
& $initializer -AppRoot (Get-Location).Path
```

The initializer supplies `tests\baseline\HttpBaseline.Tests.csproj`, `ExternalHost.cs`, `global.json`, and `scripts\Test-Baseline.ps1`. It does not supply a contract or passing test cases. Do not overwrite existing application files/tests. On resume, inspect and reuse valid existing infrastructure rather than reinitializing or resetting it.

The .NET 10 HTTP project is verification tooling, not a retargeting of the .NET Framework service. Its runner selects the SDK from the harness directory. Missing .NET/PowerShell prerequisites must be reported explicitly; do not install globally or change machine settings.

## Author current-state characterization

Write `tests\baseline\contract.md` as target-neutral observations of the original API, with source/HTTP evidence and limitations. Keep comparison normalizations in a separate section; do not mix Python design requirements into current-state facts.

Author a focused HTTP test file in namespace `HttpBaseline.Tests` using `ExternalHost.StartAsync(output)` and its `Client`. Inspect the supplied fixture API rather than assuming an interface. Tests must not reference application assemblies.

Discover applicable routes, bodies/JSON types, statuses/errors, boundaries/coercions, initial state, identities, mutations, failure-state preservation, and repeated-operation behavior. Assert actual values and effects, not just presence or successful startup. Do not impose unobserved behavior or chase a predetermined case count. Use safe descriptive test names; raw malformed requests must not appear in reports.

Do not read facilitator suites, sibling workshop folders, previous rehearsal artifacts, or target answers. Generic templates are infrastructure, not an application specification.

## Run the original host

Build with the application's existing instructions. Derive the executable, JSON argument array, working directory, base URL, and GET readiness path from real source/startup evidence; do not change production code to fit the runner.

```powershell
.\scripts\Test-Baseline.ps1 -Phase Before -AppRoot $appRoot `
    -HostExecutable $sourceExe -HostArgumentsJson $sourceArgsJson `
    -BaseUrl $sourceUrl -ReadyPath $readyPath `
    -EvidenceDirectory .github\upgrades\dotnet-to-fastapi
```

Read actual output and `baseline-report.md`/TRX in that evidence directory. Require real nonzero discovery, all passed outcomes, and no skipped/incomplete results. A process, compilation, or report file alone is not success. The fixture owns fresh hosts, bounded readiness, occupied-port checks, logs, and cleanup of only its processes.

Present the contract, test assertions, result identities/count, and uncertainties with the assessment. Stop for approval. Before approval, correct incorrect characterization against real .NET evidence and disclose the correction; do not change production behavior.

## Seal only the reviewed passing baseline

After explicit approval of the current assessment/baseline:

```powershell
.\scripts\Test-Baseline.ps1 -Freeze -AppRoot $appRoot `
    -EvidenceDirectory .github\upgrades\dotnet-to-fastapi
```

This seals the latest genuine passing Before run only if its inputs and actual TRX still match. If inputs changed, rerun and obtain review; do not seal stale evidence. An existing freeze must be verified, never overwritten merely to continue a resumed session.

The frozen set includes expectations, fixture/project, SDK configuration, and runner. Target launch inputs and report/TRX outputs are separate. A frozen baseline is a review/integrity boundary, not a security or permission mechanism.

## Recheck the approved target

Use the target's actual executable and argument array from the approved plan, not a built-in Python mode or old host:

```powershell
.\scripts\Test-Baseline.ps1 -Phase After -AppRoot $appRoot `
    -HostExecutable $targetExe -HostArgumentsJson $targetArgsJson `
    -BaseUrl $targetUrl -ReadyPath $readyPath `
    -EvidenceDirectory .github\upgrades\dotnet-to-fastapi
```

Require identical frozen test identities, unchanged covered file set/hashes, and all-success actual results with the old host stopped. Fix target failures, not frozen expectations. A genuine contract revision requires a new scope decision and invalidated dependent approval.

Record exact commands and unsuccessful attempts. Do not modify URL reservations, kill unrelated processes, change package indexes, skip tests, invent outputs, or use facilitator expectations to fill discovery gaps. Independent facilitator checks are performed outside this agent workflow.
