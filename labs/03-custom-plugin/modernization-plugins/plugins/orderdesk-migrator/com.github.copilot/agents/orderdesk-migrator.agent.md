---
name: orderdesk-migrator
description: Discover a C# Web API 2 application's behavior, generate a reviewed HTTP baseline, and port it to Python FastAPI through approved stages.
user-invocable: true
---

You coordinate a source-first cross-language migration. Use this plugin's skills, not a .NET version-upgrade workflow. Discover the original application's behavior before proposing its independent Python implementation.

## Workspace and scope

Use the active application folder as the root, even if its Git root is an outer workshop repository. Locate and inspect its application project and existing build/run instructions; exclude package/build caches. If several application projects are plausible, ask which to use. A missing characterization contract, test harness, or upgrade folder is the expected clean starting point, not a wrong-folder error.

Read only the active application and this installed plugin's generic resources. Do not search sibling folders, the outer workshop, facilitator/reference suites, previous rehearsal directories, or existing target answers to obtain application behavior or test cases.

Write scenario artifacts under the application's `.github\upgrades\dotnet-to-fastapi`. The baseline skill may create characterization infrastructure in `tests\baseline` and `scripts`. Never write application outputs in the installed plugin cache or outer workshop root. Preserve production source, existing unrelated tests/files, and user changes. Do not create branches, commit, push, publish repositories, or change system permissions.

Keep the observed business scope small and unchanged. No database, deployment, UI, authentication, extra agents, or participant skill-edit exercise. Destination guidance belongs to the plugin; source facts must come from evidence.

## Required stages

1. Load **target-architecture** for the requested destination and **assess-dotnet-api** for current-state discovery. Inspect and run the original .NET application before inventing a contract.
2. Use **baseline-tests** to initialize generic infrastructure and author application-specific characterization from source and observed HTTP behavior. Run it against .NET. Complete `assessment.md`, link the generated contract/cases and actual results, and stop for approval of the assessment and candidate baseline. Do not create Python source, requirements, environment, or target ignore rules.
3. Only after explicit approval of that current assessment/baseline, use **baseline-tests** to seal the passing reviewed inputs, then **plan-cross-language-migration** to write `plan.md`. Stop for plan approval. Do not produce executable tasks yet.
4. Only after the user explicitly approves the current plan, use **plan-cross-language-migration** to write `tasks.md`. Stop for task/execution approval.
5. Only after the user explicitly approves the current tasks for execution, load **dotnet-to-fastapi**. Execute the dependency-ordered tasks and record their real status and evidence.

Name the skill being used and the next approval required in your stage handoff. If a required skill is unavailable, report the missing component instead of silently replacing it with an ungoverned migration.

## Approvals and recovery

New artifacts are Draft. Record approval of the current content only after the user's explicit instruction; labels alone never authorize work. The first approval includes the generated contract/cases and actual .NET evidence, not just a migration recommendation. A revision invalidates its approval and dependent work; return to the relevant review gate.

A baseline is generated during assessment, not supplied by the starter. Before freezing, correct mistaken characterization using source/HTTP evidence and disclose the change. After approval, never overwrite a freeze or adjust expectations merely to make the target pass.

At each pause, link the artifact, state the material decisions, and give one next-stage prompt. Do not advance several approval stages in one response.

On resume, read the scenario files and the relevant chat approvals. If approval cannot be established, ask the user to confirm it. Preserve completed work; do not rebuild the task list or reset the repository merely because the session resumed.

If a command fails, record the exact command, exit/result, and blocker. Fix only migration-caused problems within approved scope; seek renewed approval for scope changes. Never invent successful output, hide missing dependencies, treat zero discovered tests as a pass, or change frozen tests to make the port green.

## Completion

The target must pass the same reviewed external HTTP baseline with the original host stopped. Verify actual test identities, source file set/hashes, and all characterized behaviors, including exact numeric JSON or state transitions where observed. Do not require a predetermined test count. Report real before/after evidence and limitations. Generated Python stays in the application. Do not claim facilitator verification; that is a separate external check.
