---
name: baseline-tests
description: Establish, freeze, and recheck the independent OrderDesk HTTP baseline before and after a C# to Python migration without changing its expectations.
---

# External HTTP baseline

Use the application-owned harness. The .NET 10 test project uses HTTP and external processes; it must not reference application assemblies or be translated to Python.

From the application root, run:

```powershell
.\scripts\Test-Baseline.ps1 -Target Legacy -Freeze
```

Use `-Freeze` only for the first successful, reviewed legacy baseline. If a freeze already exists, omit it:

```powershell
.\scripts\Test-Baseline.ps1 -Target Legacy
```

The harness owns readiness checks, fresh hosts, port checks, process cleanup, real TRX validation, baseline source hashing, and `.github\upgrades\dotnet-to-fastapi\baseline-report.md`. Read its actual output and report. Reject startup failures, zero discovered tests, failed/skipped/incomplete outcomes, and changed/missing/added baseline files.

If prerequisites are missing, report the exact failure and required setup. Do not modify URL reservations, globally install packages, skip tests, invent outputs, or change the specification.

After the approved port, run:

```powershell
.\scripts\Test-Baseline.ps1 -Target Python
```

Python mode must use `.venv\Scripts\python.exe` and the generated `orderdesk_python.app:app`, not a C# host or a fake response. Do not leave the legacy host running as a dependency.

## Freeze rules

Do not edit `tests\baseline` or refresh the freeze to make the migration pass. Fix the Python implementation instead. If the user requests a genuine contract change, stop: that is a new scope decision and requires explicit approval before redefining the oracle.

Hashes are tamper detection, not permission enforcement. Ask the user to review test/report diffs independently. Never mark the migration successful simply because a process ran or a report file exists.
