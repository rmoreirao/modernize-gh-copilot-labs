---
name: assess-dotnet-api
description: Assess a legacy C# Web API 2 application for a Python FastAPI port, recording concrete endpoint, type, state, dependency, and compatibility evidence without changing production source.
---

# Assess the C# API

Prerequisites: load `target-architecture` and use `baseline-tests` to establish a passing frozen legacy run. If build/hosting/tests are blocked, report the blocker; do not pretend the baseline exists.

Read only the application and its contract:

- Classic `.csproj` and `packages.config`: target framework, references, build toolchain.
- `Program.cs`, `Startup.cs`, and `App.config`: OWIN hosting, routes, JSON settings, localhost URL.
- Controllers and DTOs: paths, methods, input binding, validation, status codes, errors, Location generation, and response property names.
- `OrderStore.cs`: seed values, decimal calculations, IDs, locking, shared lifetime, and exactly-once stock restoration.
- Frozen baseline and actual report: what is proven and what is not.

Create `.github\upgrades\dotnet-to-fastapi\assessment.md` from [the assessment template](templates/assessment.md). Cite actual application paths and source lines; do not infer findings from framework names alone.

Identify concrete cross-language risks: C# integer bounds/coercion, Decimal arithmetic and numeric JSON, snake_case versus camelCase, FastAPI's validation/error defaults, shared state across requests, and process startup differences. Inventory dependencies that disappear versus Python replacements; do not suggest retaining the .NET runtime behind the target.

Separate observations from recommendations and assumptions. Explain that focused baseline success is not proof of every possible legacy behavior.

Write only the assessment (and baseline artifacts produced by the harness). No Python source, dependency manifest, executable task list, or production changes. Leave status Draft and stop for explicit assessment approval.
