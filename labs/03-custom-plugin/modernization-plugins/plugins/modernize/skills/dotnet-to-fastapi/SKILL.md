---
name: dotnet-to-fastapi
description: Execute approved C# to Python FastAPI migration tasks, translating real business behavior and fixing compatibility failures against a frozen external HTTP baseline.
---

# Execute the Python port

Require explicit approval of the current assessment, plan, and tasks. Read them and `target-architecture` before changing anything. A request to assess or plan is not execution approval.

Mark a ready task in progress before implementing it. Keep the C# source and `tests\baseline` unchanged. Work only under the application root; do not put the answer in the plugin.

## Environment and package

Generate the approved few-module `src\orderdesk_python` package, root `requirements.txt`, and local `.venv`. Use Python 3.12. Verify compatible published dependency versions before pinning FastAPI, Pydantic 2, Uvicorn, and simplejson.

Use normal package tools:

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Do not install globally or add unrelated tooling. If setup fails, show the failure and required remediation.

## Translate behavior, not syntax

Read the actual C# DTOs, controllers, and store. Reimplement their approved behavior in Python: seed, IDs, lookup, stock reservation, error precedence, and cancellation. No CLR, subprocess to the C# host, HTTP forwarding, or legacy-server fallback.

Use Pydantic input/output models, explicit camelCase aliases, signed 32-bit input limits and the characterized integer-string handling. Preserve the specified statuses, error messages, and Location path.

Use a specific FastAPI request-validation handler for the contract's 400/message shape. Handle known business failures explicitly. Unexpected exceptions must remain visible and logged; do not turn them into successful responses.

Use Decimal values from strings, one shared store, protected compound state changes, and synchronous handlers for this synchronous store. Run Uvicorn with one worker and no reload process.

## Numeric JSON and schemas

Follow `target-architecture`'s Decimal response recipe: validate models; dump in Python mode with aliases; render retained decimals with simplejson; return a direct JSON Response. Do not pass money through float, `jsonable_encoder`, or Pydantic JSON-mode string serialization.

Declare response/error schemas in OpenAPI, including numeric money fields. A direct Response bypasses automatic response-model validation; constructing validated model instances before rendering is required.

## Verify and finish

Run Python compilation/dependency checks and use `baseline-tests`:

```powershell
.\scripts\Test-Baseline.ps1 -Target Python
```

The helper launches `orderdesk_python.app:app` from the application's `src` folder using the local virtual environment. Do not leave a manually launched host occupying its port.

When a baseline case fails, inspect the actual HTTP difference and fix the Python behavior. Never edit frozen tests, remove cases, relax exact decimals, refresh hashes, or report zero tests as a pass.

Record commands/results in `tasks.md`, including unsuccessful attempts and their resolutions. Only mark completion after the real unchanged baseline and integrity check pass with the old host stopped. Link the actual report and state focused-test limitations; do not claim production readiness.
