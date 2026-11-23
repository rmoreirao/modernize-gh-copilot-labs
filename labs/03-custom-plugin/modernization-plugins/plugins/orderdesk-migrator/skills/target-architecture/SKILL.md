---
name: target-architecture
description: Establish the approved Python FastAPI target and wire-contract rules before assessing or executing the OrderDesk C# API migration.
---

# Target architecture

Read the application-owned `tests\baseline\contract.md` and the C# source. This skill defines the destination; it does not authorize implementation.

## Destination

- Python 3.12, FastAPI, Pydantic 2, and Uvicorn.
- A small `src\orderdesk_python` package: `__init__.py`, `app.py`, `models.py`, and `store.py`. Add only a small shared response helper if needed.
- An application-local `.venv` and pinned compatible dependencies in root `requirements.txt`: FastAPI, Pydantic, Uvicorn, and simplejson. Verify published versions support the chosen interpreter; do not assume a version exists.
- Synchronous routes for the synchronous store, standard logging, and OpenAPI describing the actual responses.
- One worker, no reload process, and one application-owned shared store. Protect compound stock changes with a lock; the GIL is not a transaction boundary.

Implement models and business logic in Python. Do not call a CLR, spawn the C# host from Python, forward HTTP to the old host, or change the C# project into a newer .NET target.

## Preserve the public contract

Keep endpoint paths/verbs, camelCase JSON, statuses, Location paths, seeded data, order identity, reservation, and cancellation behavior. Python internals may use snake_case with explicit Pydantic wire aliases.

Preserve request integer bounds and the characterized legacy input rules, including parseable integer strings. Python's unbounded integers and Pydantic's coercion are not automatically equivalent to C# `int`.

FastAPI validation normally returns 422 and `detail`. Install a specific `RequestValidationError` handler returning the contract's 400/`message` response. Map known business failures to their specified statuses/messages. Do not broadly catch exceptions and return success; unexpected failures must remain visible and be logged.

## Exact money, including its JSON type

Use `Decimal` from strings, never binary floats, for catalog prices and all arithmetic. Default Pydantic JSON serialization turns decimals into strings; FastAPI encoding can also turn them into floats.

Construct validated output models, dump them with `mode="python", by_alias=True`, and serialize retained `Decimal` values with `simplejson.dumps(..., use_decimal=True, allow_nan=False)`. Return a FastAPI/Starlette `Response` with `application/json` directly, avoiding `jsonable_encoder` or Pydantic JSON-mode preprocessing. One small response helper is enough.

Direct responses bypass automatic response-model validation: validate the models before rendering. Declare the actual success/error schemas and serialization-mode numeric money types in OpenAPI; do not document strings while sending numbers.

Read the pinned framework's relevant documentation if behavior differs. Do not weaken the baseline or convert money to floats merely to satisfy a framework default.

## Verification boundary

The .NET 10 HTTP baseline is an independent external oracle and stays unchanged. Only the production implementation moves to Python. Run the same harness against each independently hosted version; Python must pass with the C# service stopped.

No new business features, multiple order lines, database, authentication, UI, cloud resources, or deployment.
