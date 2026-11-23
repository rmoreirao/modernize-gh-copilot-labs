---
name: plan-cross-language-migration
description: Convert an approved C# API assessment into a Python migration plan, then separately approved dependency-ordered tasks with explicit files and unchanged-baseline acceptance criteria.
---

# Plan, then tasks

Read `assessment.md`, source evidence, `target-architecture`, the generated current-state contract/cases, and actual Before report. Establish explicit approval of the current assessment AND baseline. Use `baseline-tests` to seal that reviewed passing set before writing a plan; verify an existing freeze rather than overwriting it.

## Plan stage

Write `.github\upgrades\dotnet-to-fastapi\plan.md` from [the plan template](templates/plan.md). Map actual C# components to Python modules and behaviors, rather than saying only "rewrite in Python."

Include:

- Python interpreter, local environment, verified/pinned dependency approach, package layout, and startup command.
- Applicable public-name mappings and observed integer bounds/coercion.
- Observed numeric precision/JSON types, validated outputs, and truthful OpenAPI.
- Discovered routes, statuses, error shapes and headers; validation adapters only where required by characterization.
- Observed state lifetime, concurrency boundaries, identity, mutations, and repeated-operation behavior.
- The generic Before/After launch configuration, approved baseline identities/hash set, and independent-host comparison.
- Preserving the legacy starter and keeping generated source in the application root.

Do not create Python source, its dependency manifest, or executable tasks yet. Leave status Draft and stop for plan approval.

## Task stage

Only after explicit approval of the current plan, write `tasks.md` from [the task template](templates/tasks.md). Keep a small list of coherent tasks, not a task per line of code.

Each task needs an ID, prerequisites, affected files, pending status, concrete acceptance criteria, and a validation command/result field. Suggested grouping: environment/package and target ignore rules; models/business state; HTTP/serialization/error adapters; Python checks; unchanged baseline comparison. Do not regenerate or replace the approved characterization as an implementation task.

Dependencies must reflect actual prerequisites. Do not execute while producing the task breakdown. Leave it Draft and stop for explicit task/execution approval.

Any revision to an approved upstream artifact invalidates dependent approvals. Re-review rather than relying on stale Approved markers.
