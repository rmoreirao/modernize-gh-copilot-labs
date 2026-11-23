# Lab 3: Port a C# API to Python with a custom plugin

Start with an ordinary **C# / .NET Framework 4.8 Web API 2** application. Use the complete **orderdesk-migrator** plugin in **VS Code** to discover its behavior, generate a reviewed HTTP baseline, and then migrate it to **Python / FastAPI**.

Unlike a .NET version upgrade, this exercise translates models, business logic, validation, state, and hosting into another language. Discovery is part of the exercise: the original application does not describe its replacement or supply a migration specification. The agent-generated baseline becomes the unchanged oracle only after review.

**Scope:** Run locally on Windows. No database, authentication, UI, deployment, CLR bridge, or proxy to the legacy host. The plugin is complete; you do not build it or edit a skill.

## How the custom plugin works

### The mental model

The plugin packages a migration workflow, not an application or a finished Python port. Copilot runs **one coordinating agent** that loads five skills: specialized instructions, not separate agents. Scripts and templates support repeatable operations; application-specific tests and code are generated from discovery and approved execution.

```text
Learner in VS Code / Copilot
             |
             v
  orderdesk-migrator agent
             |
             +--> Five skills: guidance + procedures
             |         |
             |         v
             |    Generic scripts / templates
             |
             v
  Application checkout: generated evidence + code
  (not the installed plugin folder)
```

### Components at a glance

The workshop's plugin source is organized as follows:

```text
modernization-plugins\
+-- .github\plugin\marketplace.json  Optional distribution catalog
`-- plugins\orderdesk-migrator\      Install this package folder
    +-- plugin.json                 Package identity
    +-- com.github.copilot\agents\   Copilot coordinator definition
    `-- skills\                     One SKILL.md per skill
        +-- target-architecture\
        +-- assess-dotnet-api\       templates\: assessment
        +-- baseline-tests\         scripts\, templates\, tests\
        +-- plan-cross-language-migration\  templates\: plan/tasks
        `-- dotnet-to-fastapi\
```

The [manifest](modernization-plugins/plugins/orderdesk-migrator/plugin.json) identifies the package; the [catalog](modernization-plugins/.github/plugin/marketplace.json) demonstrates central distribution, not an execution step. Local installation uses the plugin folder.

`com.github.copilot` holds harness-specific customization; `skills` holds portable instructions. Within skills, `scripts` contains executable helpers and `templates` contains reusable scaffolding. Crucially, `baseline-tests\tests` checks **plugin tooling**, not application behavior: the application-specific contract and cases do not ship here.

| Component | Responsibility |
| --- | --- |
| [orderdesk-migrator agent](modernization-plugins/plugins/orderdesk-migrator/com.github.copilot/agents/orderdesk-migrator.agent.md) | Coordinate stages, workspace boundaries, approvals, and recovery. |
| [target-architecture](modernization-plugins/plugins/orderdesk-migrator/skills/target-architecture/SKILL.md) | Define destination rules, not facts about the source API. |
| [assess-dotnet-api](modernization-plugins/plugins/orderdesk-migrator/skills/assess-dotnet-api/SKILL.md) | Discover source and live HTTP behavior; assemble the assessment. |
| [baseline-tests](modernization-plugins/plugins/orderdesk-migrator/skills/baseline-tests/SKILL.md) | Bootstrap the harness, guide case authoring, run, seal, and recheck. |
| [plan-cross-language-migration](modernization-plugins/plugins/orderdesk-migrator/skills/plan-cross-language-migration/SKILL.md) | Produce the plan, then tasks after plan approval. |
| [dotnet-to-fastapi](modernization-plugins/plugins/orderdesk-migrator/skills/dotnet-to-fastapi/SKILL.md) | Implement approved tasks; verify the unchanged contract. |

### Workflow and approval gates

A **baseline** is the contract and HTTP checks discovered from the actual application. It must pass against .NET and receive learner review before freezing:

```text
Discover source + HTTP behavior
              |
              v
Assessment + candidate contract/tests + passing .NET run
              |
       [Learner approves]
              v
Seal baseline --> Plan --> [Learner approves]
                              |
                              v
                            Tasks
                              |
                    [Learner approves execution]
                              v
                    Implement Python API
                              |
                              v
Same frozen HTTP tests --> Python, with C# stopped
                              |
                              v
                    Results + integrity evidence
```

The expectations stay unchanged; only host launch inputs differ. Fix target failures, not frozen tests. Approvals are review guardrails, not security boundaries.

Generated files belong to the **application checkout**: contract/cases in `tests\baseline`, reports/plan/tasks in `.github\upgrades\dotnet-to-fastapi`, and approved Python code in `src\orderdesk_python`. They never belong in the installed plugin cache.

### Explore the plugin

For a read-only tour, start with the linked agent definition, follow `assess-dotnet-api` into `baseline-tests`, then compare its [initializer](modernization-plugins/plugins/orderdesk-migrator/skills/baseline-tests/scripts/Initialize-Baseline.ps1) with the [runner template](modernization-plugins/plugins/orderdesk-migrator/skills/baseline-tests/templates/Test-Baseline.ps1). Use the other skill links to follow destination guidance, planning, and execution.

## Prerequisites

| Tool | Why / installation |
| --- | --- |
| Git and VS Code | Keep this workshop checkout for the plugin and clone the separate application repository. [VS Code installation](https://code.visualstudio.com/docs/setup/windows). |
| GitHub Copilot access in VS Code | Sign in and use the **Copilot** harness. [Copilot setup](https://code.visualstudio.com/docs/copilot/setup). |
| Agent plugin support | Use a VS Code version supporting Agent Plugins 1.0. See [plugin installation](https://code.visualstudio.com/docs/agent-customization/agent-plugins). |
| .NET Framework 4.8 runtime and Developer Pack | Run and compile the legacy Windows application. [Developer Pack](https://dotnet.microsoft.com/en-us/download/dotnet-framework/net48). |
| Visual Studio or Build Tools with MSBuild | Build the classic project. Include the .NET desktop build tools/targeting pack. [Build Tools](https://visualstudio.microsoft.com/downloads/). |
| PowerShell 7 | Run the plugin's characterization/verification tooling. [PowerShell installation](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows). |
| .NET 10 SDK | Run the HTTP project generated during assessment, **not** the original API or migrated service. [SDK installation](https://learn.microsoft.com/en-us/dotnet/core/install/windows). |
| Python 3.12 with pip | Used during approved execution for the generated target's local environment. [Python installation](https://www.python.org/downloads/windows/). Verify `py -3.12 --version`. |

Initial restores need access to NuGet and the configured Python package feed. You do not need IIS, SQL Server, a separate NuGet CLI, or an Azure subscription.

## 1. Clone the application and locate the plugin

Use the real application repository separately from this workshop's plugin source:

| Location | Role |
| --- | --- |
| [rmoreirao/orderdesk-dotnet48](https://github.com/rmoreirao/orderdesk-dotnet48) | Original application repository: source and ordinary .NET build/run documentation |
| [modernization-plugins](modernization-plugins/README.md) in this workshop | Shared plugin source: destination guidance, discovery workflow, and generic verification scaffolding |

From the **workshop repository root**, clone a fresh application checkout beside it and open that checkout:

```powershell
$workshopRoot = (Get-Location).Path
$appRoot = Join-Path (Split-Path -Parent $workshopRoot) 'orderdesk-dotnet48-lab3'
if (Test-Path -LiteralPath $appRoot) { throw 'Choose a new application folder; do not overwrite or reuse an earlier run.' }
git clone https://github.com/rmoreirao/orderdesk-dotnet48.git $appRoot
if ($LASTEXITCODE -ne 0) { throw 'Application clone failed.' }
code $appRoot
```

Open only the **cloned application folder** as the application workspace, not the workshop root or a combined workspace. Keep the workshop checkout available for plugin installation; you may inspect it in a separate window. All following application build/run commands and chat requests belong in the application's VS Code window. Do not supply reference tests, an earlier rehearsal, or a previous target answer to the application chat.

The application's own README describes only its current operation. No characterization contract, baseline project, target launcher, or upgrade report is prepopulated there.

## 2. Build and explore the original application

In a terminal rooted at the cloned application, follow its [.NET-only README](https://github.com/rmoreirao/orderdesk-dotnet48/blob/main/README.md):

```powershell
.\scripts\Build-Legacy.ps1
.\src\OrderDesk.Legacy\bin\Debug\OrderDesk.Legacy.exe --url http://localhost:5088/
```

In another terminal, try `GET http://localhost:5088/api/products`. Stop your manually launched host with Ctrl+C afterward so the agent can own fresh hosts during characterization.

**Continue when:** the original application builds, starts, and responds. You have not established migration expectations yet; the agent must discover and characterize behavior rather than read a supplied solution.

## 3. Install and inspect the plugin

1. In the application window, choose the **Copilot** harness.
2. Run **Chat: Install Plugin from Source** from the Command Palette.
3. Enter the absolute path to the **workshop checkout's** `labs\03-custom-plugin\modernization-plugins\plugins\orderdesk-migrator` folder, not a path inside the cloned application. In a terminal at the workshop repository root, `(Resolve-Path .\labs\03-custom-plugin\modernization-plugins\plugins\orderdesk-migrator).Path` prints that path.
4. Review the local package and any trust/installation prompt before confirming.
5. Run **Chat: Open Customizations**, open **Plugins**, and confirm **orderdesk-migrator 1.1.0** is installed/enabled in the intended context.
6. Inspect its agent and five skills. In a fresh application chat, use **Add Context (+) > Agent...** (or the current agent-name button) to select **orderdesk-migrator**.

If replacing an earlier workshop package, update only that local plugin and verify its version in a fresh chat. Version 1.0.1 expected a prepared baseline and is not the cold-start exercise. Leave Azure modernization agents, Upgrade, and unrelated extensions untouched.

If Customizations shows the new version but the agent picker is stale, use **Developer: Reload Window**, then reopen the picker in a fresh chat. Verify the selected agent's description mentions discovery and generated characterization; do not copy agent files into the original application to work around discovery.

If plugin support is disabled, consult the [VS Code plugin settings](https://code.visualstudio.com/docs/agent-customization/agent-plugins); do not bypass organization policy or trust prompts. If the agent or skills do not appear, stop and resolve installation/discovery before the exercise.

## 4. Discover, characterize, and review

Send:

```text
Assess this .NET application for an independent Python/FastAPI migration.
First inspect its source and running HTTP behavior. Use the plugin's generic
scaffolding to generate a current-state contract and characterization tests
from that evidence, then run them against .NET.
Present the assessment, contract, cases, actual results, and limitations.
Do not change production source or create the Python environment/implementation.
Stop for my review of the assessment and candidate baseline.
```

Inspect the newly generated artifacts:

- `.github\upgrades\dotnet-to-fastapi\assessment.md`: source/HTTP evidence and proposed changes.
- `tests\baseline\contract.md` and the generated cases: target-neutral observations, meaningful assertions, and explicit comparison normalizations.
- `baseline-report.md` and its real TRX: the Before run actually discovered and passed tests against .NET.

Check that findings came from this application, not from assumptions or a supplied reference suite. Does the characterization cover the observed routes, JSON types, errors, boundaries, and state effects? What remains uncharacterized? A passing suite is useful evidence, not proof of comprehensive coverage.

**Continue when:** the candidate tests genuinely pass, you have reviewed their meaning, and the agent has stopped. Zero discovery, skipped/incomplete outcomes, or startup alone is not success. No Python code/environment should exist yet.

## 5. Approve the assessment/baseline and review the plan

Send:

```text
I approve the current assessment and characterization contract/tests/results.
Seal this passing baseline, then create the Python migration plan.
Stop for my review; do not create executable tasks or target code yet.
```

The baseline skill seals the reviewed passing Before run only if its current inputs and actual TRX still match. If you revised the cases, they need a new real run and review first. Do not overwrite an existing freeze.

Open `plan.md` in the scenario folder. Require an evidence-backed mapping, not just "rewrite in Python":

| Legacy behavior | Plan must preserve |
| --- | --- |
| Observed numeric semantics and JSON types | Exact preservation, not a framework-default conversion |
| Public names, routes, headers, and errors | The characterized wire contract, not assumed target conventions |
| State lifetime, mutations, and repeated operations | The behavior evidenced in the original implementation |
| Input boundaries and coercion | Constraints supported by source and characterization |
| Frozen test inputs and host configuration | The same assertions with explicit, separate target launch inputs |

Ask for a plan revision if one is missing. A revision requires a new review; the agent should not start implementation.

## 6. Approve the plan and review tasks

Send:

```text
I approve the current plan. Create dependency-ordered tasks with files and acceptance criteria.
Do not execute them yet.
```

Open `tasks.md`. Check environment/package and ignore-rule setup, business/model translation, HTTP adapters, runtime/schema checks, and unchanged-baseline verification. Each task needs prerequisites, files, acceptance criteria, and real command/result fields. Replacing the characterization suite is not an implementation task.

**Continue when:** you have reviewed the tasks and the agent has stopped for execution approval.

## 7. Execute the approved tasks

Send:

```text
I approve the current tasks for execution. Implement the Python API.
Keep the original production source and frozen baseline unchanged.
Run the same characterized HTTP expectations against the independent target.
```

Follow task progress and inspect the changes. Expected generated files include `src\orderdesk_python`, root `requirements.txt`, and a local `.venv`. The Python service must contain the business implementation; it must not call a CLR or forward to the C# host.

Review the actual package install and command output. The agent must fix migration-caused failures rather than edit tests, refresh hashes, or claim success from compilation alone.

## 8. Verify behavior and evidence

Read `baseline-report.md`, actual TRX, and `tasks.md` for real Before/After commands, outcomes, test identities, integrity, and cleanup. The generic runner uses `-Phase Before` / `-Phase After` with explicit host inputs, not a built-in `-Target Python` mode. Re-run the exact After command recorded in the task evidence if needed; use the actual approved executable/arguments and readiness path.

The target comparison must work with C# stopped. Confirm that assertions did not change between hosts, Python genuinely implements the behavior, and runtime/OpenAPI checks describe the responses actually sent.

No instructor reference suite is supplied or required. Review the generated cases against the observed application behavior; the suite does not need to reproduce a predetermined case count.

**Finish when:** both hosts pass the same reviewed frozen expectations, covered files/hashes and actual identities match, and evidence is recorded. Focused characterization does not prove exhaustive compatibility or production readiness.

## Troubleshooting and limitations

- **Legacy build fails:** check MSBuild and the .NET Framework targeting pack; `scripts\Build-Legacy.ps1` discovers MSBuild rather than assuming a machine-specific path.
- **Port occupied:** stop the specific host you started, not every Python/.NET process. The generated fixture must not reuse or kill an unrelated listener.
- **OWIN access denied:** an administrator may need a URL reservation for exactly `http://localhost:5088/` and your Windows account. Review that setup with them; do not grant wildcard URLs or Everyone access. The lab does not modify reservations automatically.
- **Python environment absent:** execution must generate its package, pinned `requirements.txt`, and `.venv`; the starter intentionally contains no answer.
- **Contract or harness absent before assessment:** this is expected. Verify plugin 1.1.0 and let its baseline skill initialize infrastructure and author cases from actual discovery. Do not copy cases from another run into the application.
- **Initializer finds existing files:** inspect them and resume only if valid; do not overwrite unrelated tests or reset the application.
- **Reusing an earlier application checkout:** generated `tests\baseline`, upgrade evidence, or target files mean it is not a clean start. Preserve that work and clone into a different fresh folder for this exercise; do not overwrite an existing suite or reuse its approvals.
- **Python package pin unavailable:** a configured mirror can lag public releases. Resolve compatible published versions available through the approved feed and update the generated pins before installing; do not silently change package-index settings.
- **Baseline changed:** inspect the diff and fix the migration. Do not re-freeze to hide a failing port.

Approval markers and hashes are review guardrails/tamper detection, not security enforcement. Follow normal tool/trust approvals.

**Rehearsal status:** Plugin **1.1.0** completed a fresh-clone SDK rehearsal of [orderdesk-dotnet48](https://github.com/rmoreirao/orderdesk-dotnet48) at commit `63058721f6bf89b5696db47920e56b1b7ac6da75`. The agent discovered the application and generated **33 characterization cases**; the same frozen cases passed against .NET and the independent Python target, with zero failed, skipped, or incomplete outcomes and C# stopped for the Python comparison. The retained generic tooling passed **26/26 checks**, and **17 live HTTP/OpenAPI exchanges** passed. The run used .NET SDK **10.0.403** and Python **3.12.10**.

An initial target OpenAPI schema defect was corrected and rechecked without changing the frozen expectations. All twelve starter files, the approved plan, seal, and original Before evidence remained unchanged; all owned hosts were stopped. Generated answers and full reports remain in the isolated rehearsal checkout, not in this workshop or the public starter. These are this run's observed counts, not required counts for learner-generated suites.

**Verification boundary:** The automated rehearsal uses SDK-agent execution and coordinator review at each stage, not human interaction with native VS Code chat/approval UI. The participant workflow remains VS Code. No independent reference suite is included in this verification.

**References:** [Plugin authoring](https://code.visualstudio.com/docs/agents/reference/agent-plugin-reference), [FastAPI validation/errors](https://fastapi.tiangolo.com/tutorial/handling-errors/), [Pydantic Decimal serialization](https://docs.pydantic.dev/latest/api/standard_library_types/), and [simplejson decimal support](https://simplejson.readthedocs.io/en/latest/).
