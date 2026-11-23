# Lab 3: Port a C# API to Python with a custom plugin

Use a packaged **orderdesk-migrator** agent and five skills in **VS Code** to migrate OrderDesk from **C# / .NET Framework 4.8 Web API 2** to **Python / FastAPI**.

Unlike a .NET version upgrade, this exercise translates models, business logic, validation, state, and hosting into another language. The API stays small: products, single-product orders, stock reservation, and cancellation. The unchanged HTTP baseline is the compatibility oracle.

**Scope:** Run locally on Windows. No database, authentication, UI, deployment, CLR bridge, or proxy to the legacy host. The plugin is complete; you do not build it or edit a skill.

## Prerequisites

| Tool | Why / installation |
| --- | --- |
| Git and VS Code | Open your workshop checkout. [VS Code installation](https://code.visualstudio.com/docs/setup/windows). |
| GitHub Copilot access in VS Code | Sign in and use the **Copilot** harness. [Copilot setup](https://code.visualstudio.com/docs/copilot/setup). |
| Agent plugin support | Use a VS Code version supporting Agent Plugins 1.0. See [plugin installation](https://code.visualstudio.com/docs/agent-customization/agent-plugins). |
| .NET Framework 4.8 runtime and Developer Pack | Run and compile the legacy Windows application. [Developer Pack](https://dotnet.microsoft.com/en-us/download/dotnet-framework/net48). |
| Visual Studio or Build Tools with MSBuild | Build the classic project. Include the .NET desktop build tools/targeting pack. [Build Tools](https://visualstudio.microsoft.com/downloads/). |
| .NET 10 SDK | Run the independent HTTP tests, **not** the migrated service. [SDK installation](https://learn.microsoft.com/en-us/dotnet/core/install/windows). |
| Python 3.12 with pip | Run the generated FastAPI application in a local virtual environment. [Python installation](https://www.python.org/downloads/windows/). Verify `py -3.12 --version`. |

Initial restores need access to NuGet and the configured Python package feed. You do not need IIS, SQL Server, a separate NuGet CLI, or an Azure subscription.

## 1. Open the two sides

These sibling folders represent separate repositories; the workshop does not create or publish repositories:

| Folder | Role |
| --- | --- |
| [modernization-plugins](modernization-plugins/README.md) | Shared marketplace, plugin, agent, and skills |
| [your-app](your-app/README.md) | Legacy source, baseline, and generated migration outputs |

Open `modernization-plugins` in one VS Code window to inspect the package. Open `your-app` in a second window for the exercise. Run the following commands in the **your-app** integrated terminal, not the outer workshop root.

The starter has no Python implementation or preapproved migration reports.

## 2. Establish the legacy baseline

1. Read `tests\baseline\contract.md`: seed values, JSON types, errors, and stock transitions.
2. Run:

   ```powershell
   .\scripts\Test-Baseline.ps1 -Target Legacy -Freeze
   ```

3. Read the actual result and `.github\upgrades\dotnet-to-fastapi\baseline-report.md`. Check that tests were discovered and passed.
4. Review the tests and frozen file manifest. The suite starts a fresh real host for each scenario and stops its own processes.

For a subsequent run with the existing freeze, omit `-Freeze`:

```powershell
.\scripts\Test-Baseline.ps1 -Target Legacy
```

**Continue when:** the legacy build and HTTP tests pass. Zero discovered tests, skipped tests, or a started process alone are not success. Fix setup failures before asking for the migration; do not weaken the baseline.

## 3. Install and inspect the plugin

1. In the application window, choose the **Copilot** harness.
2. Run **Chat: Install Plugin from Source** from the Command Palette.
3. Enter the absolute path to your checkout's `labs\03-custom-plugin\modernization-plugins\plugins\orderdesk-migrator` folder.
4. Review the local package and any trust/installation prompt before confirming.
5. Run **Chat: Open Customizations**, open **Plugins**, and confirm **orderdesk-migrator** is installed/enabled in the intended context.
6. Inspect its agent and five skills. Start a fresh application chat and select **orderdesk-migrator** in the agent picker.

If you installed the earlier workshop package named `modernize`, remove only that local plugin before installing the renamed package. Leave Azure modernization agents, Upgrade, and other extensions installed; they are separate tools.

If plugin support is disabled, consult the [VS Code plugin settings](https://code.visualstudio.com/docs/agent-customization/agent-plugins); do not bypass organization policy or trust prompts. If the agent or skills do not appear, stop and resolve installation/discovery before the exercise.

## 4. Assess and review

Send:

```text
Assess OrderDesk for a C#/.NET Framework 4.8 to Python/FastAPI migration.
Use the plugin's architecture and baseline skills.
Write the assessment and stop for my approval. Do not change production source.
```

Open `.github\upgrades\dotnet-to-fastapi\assessment.md`. Check actual source evidence and the frozen baseline. Identify a cross-language risk: numeric decimals, integer bounds, camelCase aliases, FastAPI error defaults, or shared stock state.

**Continue when:** the assessment is complete and the agent has stopped. No Python source or Python dependency manifest should exist yet.

## 5. Approve the assessment and review the plan

Send:

```text
I approve the current assessment. Create the Python migration plan and stop for my review.
```

Open `plan.md` in the scenario folder. Look for a concrete C#-to-Python mapping, not just "rewrite in Python":

| Legacy behavior | Plan must preserve |
| --- | --- |
| C# decimal prices/totals | Python Decimal arithmetic and JSON **numbers**, not strings or floats |
| DTO property names | camelCase on the wire, even if Python internals use snake_case |
| 400 with a message error | A validation adapter, not default 422/detail responses |
| Shared order/stock store | Shared lifetime, protected state changes, cancellation restores once |
| C# int inputs | Declared 32-bit bounds and characterized integer-string handling |

Ask for a plan revision if one is missing. A revision requires a new review; the agent should not start implementation.

## 6. Approve the plan and review tasks

Send:

```text
I approve the current plan. Create dependency-ordered tasks with files and acceptance criteria.
Do not execute them yet.
```

Open `tasks.md`. Check the Python environment/package, model/store translation, HTTP/serialization/error adapters, and unchanged baseline verification. Each task should have a state, prerequisites, files, and concrete evidence criteria.

**Continue when:** you have reviewed the tasks and the agent has stopped for execution approval.

## 7. Execute the approved tasks

Send:

```text
I approve the current tasks for execution. Implement the Python API.
Keep the legacy source and frozen baseline unchanged, and run the same HTTP tests against Python.
```

Follow task progress and inspect the changes. Expected generated files include `src\orderdesk_python`, root `requirements.txt`, and a local `.venv`. The Python service must contain the business implementation; it must not call a CLR or forward to the C# host.

Review the actual package install and command output. The agent must fix migration-caused failures rather than edit tests, refresh hashes, or claim success from compilation alone.

## 8. Verify behavior and evidence

With no manually started server occupying the test ports, run:

```powershell
.\scripts\Test-Baseline.ps1 -Target Python
```

Read `baseline-report.md` for real before/after results and baseline integrity. Inspect `tasks.md` for actual command outcomes. The Python comparison must work with the legacy host stopped.

The tests cover the stated contract: seeded catalog, creation/retrieval/Location, exact numeric decimals, validation and bounds, missing resources, insufficient stock without mutation, and cancellation without double-restocking.

**Finish when:** both independent hosts pass the same unchanged tests, the frozen file set/hashes match, and the agent has recorded the evidence. Focused contract tests do not prove general application compatibility or production readiness.

## Troubleshooting and limitations

- **Legacy build fails:** check MSBuild and the .NET Framework targeting pack; `scripts\Build-Legacy.ps1` discovers MSBuild rather than assuming a machine-specific path.
- **Port occupied:** stop the specific host you started, not every Python/.NET process. The harness owns localhost ports 5088 (legacy) and 5089 (Python).
- **OWIN access denied:** an administrator may need a URL reservation for exactly `http://localhost:5088/` and your Windows account. Review that setup with them; do not grant wildcard URLs or Everyone access. The lab does not modify reservations automatically.
- **Python environment absent:** execution must generate its package, pinned `requirements.txt`, and `.venv`; the starter intentionally contains no answer.
- **Python package pin unavailable:** a configured mirror can lag public releases. Resolve compatible published versions available through the approved feed and update the generated pins before installing; do not silently change package-index settings.
- **Baseline changed:** inspect the diff and fix the migration. Do not re-freeze to hide a failing port.

Approval markers and hashes are review guardrails/tamper detection, not security enforcement. Follow normal tool/trust approvals.

**Rehearsal status:** A live VS Code run of installed `orderdesk-migrator` v1.0.1 completed assessment, planning, task generation, and Python execution, with the approval stops observed. In an isolated application copy, the real legacy API and agent-generated FastAPI service each passed all 42 frozen HTTP cases. Actual TRX identities, baseline hashes, runtime pins, host cleanup, and the generated JSON/OpenAPI behavior were checked. The shipped starter remains legacy-only; the Python answer, local environment, and rehearsal reports are outside it.

**References:** [Plugin authoring](https://code.visualstudio.com/docs/agents/reference/agent-plugin-reference), [FastAPI validation/errors](https://fastapi.tiangolo.com/tutorial/handling-errors/), [Pydantic Decimal serialization](https://docs.pydantic.dev/latest/api/standard_library_types/), and [simplejson decimal support](https://simplejson.readthedocs.io/en/latest/).
