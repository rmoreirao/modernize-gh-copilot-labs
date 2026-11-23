---
name: dotnet-to-fastapi
description: Execute approved C# to Python FastAPI migration tasks, translating real business behavior and fixing compatibility failures against a frozen external HTTP baseline.
---

# Execute the Python port

Require explicit approval of the current assessment, plan, and tasks. Read them and `target-architecture` before changing anything. A request to assess or plan is not execution approval.

Mark a ready task in progress before implementing it. Keep the C# source and `tests\baseline` unchanged. Work only under the application root; do not put the answer in the plugin.

## Environment and package

Only now add the appropriate `.venv`, `__pycache__`, and `.pyc` ignore rules, preserving existing patterns. Generate the approved few-module `src\orderdesk_python` package, root `requirements.txt`, and local `.venv`. Use Python 3.12. Verify compatible published dependencies through the configured feed before pinning FastAPI, Pydantic 2, Uvicorn, and simplejson. Resolve exact runtime pins without changing index settings.

Use normal package tools:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Do not install globally or add unrelated tooling. If setup fails, show the failure and required remediation.

## Translate behavior, not syntax

Read the C# source and reviewed characterization. Reimplement the actual models, initial state, calculations, identity, mutations, error precedence, and repeat behavior that were discovered. Do not substitute assumed sample behavior or copy a reference implementation. No CLR, C# subprocess, forwarding, or legacy-server fallback.

Use Pydantic input/output models, the characterized wire names/types, declared numeric bounds, and observed binding behavior. Do not assume camelCase, 32-bit integers, string coercion, or a particular error shape without evidence.

Adapt FastAPI validation only to the scoped error behavior established by the baseline. Handle known business failures explicitly; unexpected failures remain visible and logged, never converted into success.

Use Decimal values from strings, one shared store, protected compound state changes, and synchronous handlers for this synchronous store. Run Uvicorn with one worker and no reload process.

## Numeric JSON and schemas

Follow `target-architecture`'s Decimal response recipe: validate models; dump in Python mode with aliases; render retained decimals with simplejson; return a direct JSON Response. Do not pass money through float, `jsonable_encoder`, or Pydantic JSON-mode string serialization.

Declare response/error schemas in OpenAPI, including numeric money fields. A direct Response bypasses automatic response-model validation; constructing validated model instances before rendering is required.

## Verify and finish

Run compilation/dependency checks and live OpenAPI/HTTP probes for the actual responses. Use the generic runner from `baseline-tests` with target inputs derived from the approved plan:

```powershell
.\scripts\Test-Baseline.ps1 -Phase After -AppRoot $appRoot `
    -HostExecutable $targetExe -HostArgumentsJson $targetArgsJson `
    -BaseUrl $targetUrl -ReadyPath $readyPath `
    -EvidenceDirectory .github\upgrades\dotnet-to-fastapi
```

For the Python target, the executable is the real local environment's Python and arguments launch the generated application with one Uvicorn worker/no reload. The harness must not substitute a .NET executable. Stop the old host and any manually owned inspection host before the comparison; do not disturb unrelated port owners.

When a baseline case fails, inspect the actual HTTP difference and fix the Python behavior. Never edit frozen tests, remove cases, relax exact decimals, refresh hashes, or report zero tests as a pass.

Record commands/results in `tasks.md`, including unsuccessful attempts and their resolutions. Only mark completion after the real unchanged baseline and integrity check pass with the old host stopped. Link the actual report and state focused-test limitations; do not claim production readiness.

Do not read/run facilitator tests or previous answers. The instructor performs any separate reference verification outside this workflow.
