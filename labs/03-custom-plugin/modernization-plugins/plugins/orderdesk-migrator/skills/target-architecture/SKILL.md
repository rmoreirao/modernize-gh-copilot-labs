---
name: target-architecture
description: Define Python FastAPI destination guidance while deriving preservation requirements from the assessed source application.
---

# Target architecture

This skill defines the destination, not facts about the source. Begin with the user's target and the actual .NET application. A characterization contract need not exist yet; `assess-dotnet-api` and `baseline-tests` create it from evidence.

## Destination

- Python 3.12, FastAPI, Pydantic 2, and Uvicorn.
- A small `src\orderdesk_python` package: `__init__.py`, `app.py`, `models.py`, and `store.py`. Add only a small shared response helper if needed.
- An application-local `.venv` and pinned compatible dependencies in root `requirements.txt`: FastAPI, Pydantic, Uvicorn, and simplejson. Verify published versions support the chosen interpreter; do not assume a version exists.
- Synchronous routes for the synchronous store, standard logging, and OpenAPI describing the actual responses.
- One worker, no reload process, and one application-owned shared store. Protect compound stock changes with a lock; the GIL is not a transaction boundary.

Implement models and business logic in Python. Do not call a CLR, spawn the C# host from Python, forward HTTP to the old host, or change the C# project into a newer .NET target.

## Preserve the public contract

Preserve the paths, verbs, public JSON names/types, statuses, headers, initial state, and state transitions established by the reviewed characterization. Do not assume four routes, camelCase, a particular seed, order model, or cancellation behavior. Python internals may use snake_case with explicit wire aliases where needed.

Preserve observed integer bounds/coercion. Python's unbounded integers and Pydantic defaults are not automatically equivalent to a C# field's declared type and actual binder. Accept integer strings only where source/HTTP characterization supports that behavior.

FastAPI validation normally returns 422 and `detail`. If that differs from the original's characterized errors, use a scoped `RequestValidationError` adapter preserving the observed status/body. Do not assume every original API returns 400/`message`. Map only known business failures; unexpected failures must remain visible and logged.

## Exact money, including its JSON type

Where the source uses exact decimal arithmetic and numeric JSON, preserve it with `Decimal` from strings, never binary floats. Default Pydantic JSON serialization turns decimals into strings; FastAPI encoding can also turn them into floats.

Construct validated output models, dump them with `mode="python", by_alias=True`, and serialize retained `Decimal` values with `simplejson.dumps(..., use_decimal=True, allow_nan=False)`. Return a FastAPI/Starlette `Response` with `application/json` directly, avoiding `jsonable_encoder` or Pydantic JSON-mode preprocessing. One small response helper is enough.

Direct responses bypass automatic response-model validation: validate the models before rendering. Declare the actual success/error schemas and serialization-mode numeric money types in OpenAPI; do not document strings while sending numbers.

Read the pinned framework's relevant documentation if behavior differs. Do not weaken the baseline or convert money to floats merely to satisfy a framework default.

## Verification boundary

The characterization suite is generated during assessment, run against .NET, reviewed, and frozen before translation. Thereafter its expectations stay unchanged. Run the same external HTTP harness against each independently hosted version; Python must pass with the C# service stopped. Do not read a facilitator reference suite as a substitute for discovery.

No new business features, multiple order lines, database, authentication, UI, cloud resources, or deployment.
