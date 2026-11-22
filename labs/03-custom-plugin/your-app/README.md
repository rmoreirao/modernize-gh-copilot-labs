# Application repository

OrderDesk is a small Windows-hosted **C# / .NET Framework 4.8 Web API 2** starter. The migration creates an independent **Python / FastAPI** implementation while preserving its HTTP contract.

```text
your-app\
  global.json
  src\OrderDesk.Legacy\
  tests\baseline\
    contract.md
    OrderDesk.Baseline.Tests.csproj
  scripts\
    Build-Legacy.ps1
    Test-Baseline.ps1
```

## Run from this folder

See the [lab prerequisites and walkthrough](../README.md). In a terminal whose working directory is `your-app`:

```powershell
.\scripts\Test-Baseline.ps1 -Target Legacy -Freeze
```

The helper restores/builds the classic project with Visual Studio MSBuild, runs the .NET 10 HTTP tests against real external hosts, validates the TRX result, and records the baseline. It starts fresh seeded state for each scenario and stops only its own processes. Omit `-Freeze` on subsequent runs with an existing freeze.

To inspect the API manually:

```powershell
.\scripts\Build-Legacy.ps1
.\src\OrderDesk.Legacy\bin\Debug\OrderDesk.Legacy.exe --url http://localhost:5088/
```

Then call `GET http://localhost:5088/api/products`. Stop that host with Ctrl+C before running the baseline again; the suite needs its port.

## After the approved migration

The agent generates:

```text
your-app\
  requirements.txt
  .venv\
  src\orderdesk_python\
  .github\upgrades\dotnet-to-fastapi\
    assessment.md
    plan.md
    tasks.md
    baseline-report.md
    baseline-files.json
```

Run the same test files against Python:

```powershell
.\scripts\Test-Baseline.ps1 -Target Python
```

The target must expose `orderdesk_python.app:app` in `src`, use `.venv\Scripts\python.exe`, and run as one Uvicorn worker on localhost:5089. The Python API must work without the C# host.

The baseline remains a .NET 10 `HttpClient` suite with no application-assembly references. Moving both the implementation and its oracle at once would make regressions harder to detect. Python alone runs the migrated service; .NET remains a workshop verification tool.

Review actual reports and diffs. Keep the baseline file set unchanged, including the [contract](tests/baseline/contract.md). Never change assertions or refresh hashes to hide a failed port. Neither hashes nor approval markers prevent tampering; they support independent review.

The starter intentionally has no Python answer or approved migration artifacts. It uses no database, authentication, customer data, deployment, or persistent multi-worker storage.
