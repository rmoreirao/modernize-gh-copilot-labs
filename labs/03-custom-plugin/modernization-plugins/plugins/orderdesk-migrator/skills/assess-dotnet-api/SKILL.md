---
name: assess-dotnet-api
description: Discover a C# Web API 2 application's source and HTTP behavior, generate characterization evidence, and assess a Python FastAPI port without changing production source.
---

# Assess the C# API

Start from the application as it exists. No contract, baseline suite, freeze, or upgrade report is required beforehand. Load `target-architecture` for destination guidance, not as evidence of current behavior.

Inspect only the active application:

- Classic `.csproj` and `packages.config`: target framework, references, build toolchain.
- Startup/configuration: hosting, routes, JSON settings, URLs, shutdown, and startup errors.
- Controllers and DTOs: paths, methods, input binding, validation, status codes, errors, Location generation, and response property names.
- Business/state code: actual initial data, calculations, identity, lifetime, locking, mutations, and repeated-operation behavior.
- Existing application documentation/tests, if any: corroborate them with source and actual execution rather than assuming they are complete.

Use the application's .NET-only build/run instructions. Verify real responses and relevant failure/state paths using owned local hosts. Do not add a reset endpoint, change production behavior, or infer current behavior from a desired target. Missing tooling or a failed build is a reported limitation/blocker, not permission to fabricate observations.

Use `baseline-tests` after discovery to create generic infrastructure and author the current-state contract and characterization cases. Do not copy prewritten cases from the plugin, facilitator, outer workshop, or earlier answer. Separate observed API facts from comparison normalizations and future architecture. Run the new cases against the real .NET service before declaring the assessment ready for review.

Create `.github\upgrades\dotnet-to-fastapi\assessment.md` from [the assessment template](templates/assessment.md). Cite actual application paths and source lines; do not infer findings from framework names alone.

Identify applicable cross-language risks with evidence: integer bounds/coercion, numeric precision and JSON types, public naming, validation/errors, shared state, and startup differences. Do not assume a particular casing, error envelope/status, seed, endpoint count, or input coercion just because the implementation uses Web API 2. Inventory removed/replaced dependencies without proposing a retained .NET runtime behind Python.

Separate observations from recommendations and assumptions. Explain that focused baseline success is not proof of every possible legacy behavior.

Link the generated `tests\baseline\contract.md`, cases, runner, actual Before report/TRX, and uncharacterized behavior. Request explicit review of the assessment AND candidate baseline. The generated case count is evidence, not a goal of matching an external reference count.

Write only the assessment and characterization infrastructure/evidence. No Python source, requirements, environment, target ignore rules, executable migration tasks, or production changes. Leave Draft and stop. Freeze only after approval of the current passing baseline.
