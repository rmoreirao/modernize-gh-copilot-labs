---
name: plan-cross-language-migration
description: Convert an approved C# API assessment into a Python migration plan, then separately approved dependency-ordered tasks with explicit files and unchanged-baseline acceptance criteria.
---

# Plan, then tasks

Read `assessment.md`, the source evidence, `target-architecture`, the contract, and actual baseline report. Establish explicit user approval of the current assessment before writing a plan.

## Plan stage

Write `.github\upgrades\dotnet-to-fastapi\plan.md` from [the plan template](templates/plan.md). Map actual C# components to Python modules and behaviors, rather than saying only "rewrite in Python."

Include:

- Python interpreter, local environment, verified/pinned dependency approach, package layout, and startup command.
- DTO aliases and integer bounds/coercion.
- Decimal math, exact numeric JSON output, validated models, and truthful OpenAPI.
- Four routes, statuses, errors and Location semantics, including the FastAPI validation adapter.
- Shared store lifetime, lock scope, independent order IDs, and idempotent cancellation.
- The unchanged baseline command, source-integrity checks, and independent-host comparison.
- Preserving the legacy starter and keeping generated source in the application root.

Do not create Python source, its dependency manifest, or executable tasks yet. Leave status Draft and stop for plan approval.

## Task stage

Only after explicit approval of the current plan, write `tasks.md` from [the task template](templates/tasks.md). Keep a small list of coherent tasks, not a task per line of code.

Each task needs an ID, prerequisites, affected files, pending status, concrete acceptance criteria, and a validation command/result field. Suggested grouping: environment/package; models/store; HTTP/serialization/error adapters; Python checks; unchanged baseline comparison.

Dependencies must reflect actual prerequisites. Do not execute while producing the task breakdown. Leave it Draft and stop for explicit task/execution approval.

Any revision to an approved upstream artifact invalidates dependent approvals. Re-review rather than relying on stale Approved markers.
