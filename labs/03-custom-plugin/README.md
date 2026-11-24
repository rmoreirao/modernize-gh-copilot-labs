# Lab 3: Port a C# API to Python with a custom plugin

Use the ready-made **orderdesk-migrator** plugin in **VS Code** to port the [OrderDesk API](https://github.com/rmoreirao/orderdesk-dotnet48) from **C# / .NET Framework 4.8** to **Python / FastAPI**.

**What you'll finish with:** An independent Python API that passes the same reviewed HTTP checks as the original application. Unlike Lab 2's in-place .NET upgrade, this lab keeps the original production source unchanged and compares behavior across languages.

**How the plugin helps:** One coordinating **agent** uses five **skills**: reusable instructions, not separate agents. You install the complete package; you do not build it or edit skills. The [plugin reference](modernization-plugins/README.md#how-the-custom-plugin-works) explains the components.

**Local only:** Windows, with no database, authentication, UI, cloud deployment, CLR bridge, or proxy to the original API.

## Prerequisites

| Tool | Why / installation |
| --- | --- |
| Git and VS Code | Clone both repositories and open the application. [Install Git](https://git-scm.com/install/windows) and [VS Code](https://code.visualstudio.com/docs/setup/windows). |
| GitHub Copilot access in VS Code | Sign in and use the **Copilot** harness. [Copilot setup](https://code.visualstudio.com/docs/copilot/setup). |
| Agent plugin support | Use a VS Code version supporting Agent Plugins 1.0. See [plugin installation](https://code.visualstudio.com/docs/agent-customization/agent-plugins). |
| .NET Framework 4.8 runtime and Developer Pack | Run and compile the legacy Windows application. [Developer Pack](https://dotnet.microsoft.com/en-us/download/dotnet-framework/net48). |
| Visual Studio or Build Tools with MSBuild | Build the classic project. Include the .NET desktop build tools/targeting pack. [Build Tools](https://visualstudio.microsoft.com/downloads/). |
| PowerShell 7 | Run the plugin's characterization/verification tooling. [PowerShell installation](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows). |
| .NET 10 SDK | Run the HTTP project generated during assessment, **not** the original API or migrated service. [SDK installation](https://learn.microsoft.com/en-us/dotnet/core/install/windows). |
| Python 3.12 with pip | Used during approved execution for the generated target's local environment. [Python installation](https://www.python.org/downloads/windows/). Verify `py -3.12 --version`. |

You can reuse applicable tools from earlier labs. Open a new terminal after installing tools. Initial restores need access to NuGet and the configured Python package feed; no IIS, SQL Server, separate NuGet CLI, or Azure subscription is needed.

**Verification note:** The recorded successful rehearsal used SDK execution, not native VS Code interaction. Native UI verification and screenshots are deferred; see the [rehearsal details](modernization-plugins/README.md#rehearsal-and-verification-boundary).

## Step 1 - Prepare two separate checkouts

**Where:** A local **PowerShell 7** window. For the existing-workshop option below, open it at your workshop repository root.

You need two repositories, with different roles:

| Checkout | Role |
| --- | --- |
| `modernize-gh-copilot-labs` | Workshop instructions and the plugin package you install. |
| `orderdesk-dotnet48-lab3` | A fresh application copy where Copilot will generate tests, reports, and Python code. |

1. Choose a parent folder. This default works under your own home directory; change only `$labRoot` if you prefer another writable location:

   ```powershell
   $labRoot = Join-Path $HOME 'copilot-labs'
   New-Item -ItemType Directory -Path $labRoot -Force -ErrorAction Stop | Out-Null
   ```

2. Choose **one** workshop option:

   **Option A - Clone the workshop for the first time:**

   ```powershell
   $workshopRoot = Join-Path $labRoot 'modernize-gh-copilot-labs'
   if (Test-Path -LiteralPath $workshopRoot) { throw 'Workshop folder already exists. Use Option B instead.' }
   git clone https://github.com/rmoreirao/modernize-gh-copilot-labs.git $workshopRoot
   if ($LASTEXITCODE -ne 0) { throw 'Workshop clone failed.' }
   ```

   **Option B - Use your existing workshop checkout:**

   Run this from the root of `modernize-gh-copilot-labs`, not from a lab subfolder:

   ```powershell
   $workshopRoot = (Get-Location).Path
   ```

3. In the **same PowerShell window**, resolve the plugin folder and clone a fresh application:

   ```powershell
   $pluginRoot = (Resolve-Path -LiteralPath (
       Join-Path $workshopRoot 'labs\03-custom-plugin\modernization-plugins\plugins\orderdesk-migrator'
   ) -ErrorAction Stop).Path
   $appRoot = Join-Path $labRoot 'orderdesk-dotnet48-lab3'
   if (Test-Path -LiteralPath $appRoot) { throw 'Choose a new application folder; do not overwrite or reuse an earlier run.' }
   git clone https://github.com/rmoreirao/orderdesk-dotnet48.git $appRoot
   if ($LASTEXITCODE -ne 0) { throw 'Application clone failed.' }
   Write-Output "Application folder: $appRoot"
   Write-Output "Plugin folder to install: $pluginRoot"
   ```

   If the application folder exists, change its name in the `$appRoot` assignment and rerun this block. Preserve previous work; do not delete it or reuse approvals from another attempt.

4. Save or copy the printed **plugin folder** path for Step 3, then open the application in a new VS Code window:

   ```powershell
   code -n $appRoot
   ```

   If `code` is unavailable, open VS Code and use **File > Open Folder** to select the printed application folder. Open only that folder, not the workshop or a combined workspace.

The path variables above belong to the original PowerShell session; they do not automatically exist in VS Code's new terminals. Keep the workshop checkout available for installation, but do not copy plugin files into the application.

**Expected result:** The application window shows `src\OrderDesk.Legacy`, and you have the absolute plugin-folder path ready.

**Continue when:** You are in the fresh application workspace, separate from the workshop checkout and any earlier migration.

## Step 2 - Run the original API

**Where:** The **application's VS Code window**, in a **PowerShell 7** terminal at its root. Use **Terminal > New Terminal** and select PowerShell 7 if needed.

1. Build the original application using its [own build instructions](https://github.com/rmoreirao/orderdesk-dotnet48/blob/main/README.md):

   ```powershell
   .\scripts\Build-Legacy.ps1
   ```

   Resolve any build or restore error before continuing. The helper locates Visual Studio MSBuild; the .NET 10 SDK alone cannot build this starter.

2. Start the API and leave this terminal running:

   ```powershell
   .\src\OrderDesk.Legacy\bin\Debug\OrderDesk.Legacy.exe --url http://localhost:5088/
   ```

3. Open a **second** PowerShell 7 terminal and request the product list:

   ```powershell
   Invoke-RestMethod -Uri 'http://localhost:5088/api/products'
   ```

   PowerShell should display product data from the JSON response, not a connection error.

4. Return to the **first** terminal and press **Ctrl+C** to stop the host you started. The agent will launch fresh hosts during assessment.

If startup fails because of an occupied port or OWIN access denial, use the [troubleshooting reference](modernization-plugins/README.md#troubleshooting). Stop only your own host; do not change system permissions or kill unrelated processes.

**Expected result:** The original API builds and returns products, then your manual host stops. This is a startup check, not the migration baseline.

**Continue when:** The application works locally and the manually started host is stopped.

## Step 3 - Install and select the plugin

**Where:** The **application's VS Code window**, in Copilot Chat.

1. Sign in with the GitHub account that has Copilot access and choose the **Copilot** harness.
2. Open the Command Palette with **Ctrl+Shift+P** and run **Chat: Install Plugin from Source**.
3. Paste the absolute **plugin folder** path printed in Step 1. It ends in `plugins\orderdesk-migrator` inside the workshop checkout. Select the folder, not `plugin.json`, a skill file, or the application repository.
4. Review the package and any trust/installation prompt before confirming. No marketplace registration is needed.
5. Run **Chat: Open Customizations**, open **Plugins**, and confirm **orderdesk-migrator 1.1.0** is installed and enabled for the intended context.
6. Inspect the included agent and five skills. In a **fresh application chat**, use **Add Context (+) > Agent...** or the current agent-name button to select **orderdesk-migrator**.

If the plugin or agent is missing, stop and use the [installation troubleshooting](modernization-plugins/README.md#troubleshooting). Respect organization policy and trust prompts; do not work around discovery by copying files into the application.

**Expected result:** The selected agent is **orderdesk-migrator**, with a description mentioning discovery and generated characterization.

**Continue when:** The plugin, agent, and five skills are available. Keep this application chat for the remaining stages so its reviews and approvals stay together.

## Step 4 - Record and review the API's behavior

**Where:** The same **application chat**, with **orderdesk-migrator** selected, then the application's editor.

A **contract** records what the original API actually does: its requests, responses, errors, and state changes. **Characterization tests** check those observations over HTTP. Together, they form the candidate **baseline** that Python will later be compared against.

1. Send this prompt:

   ```text
   Assess this .NET application for an independent Python/FastAPI migration.
   First inspect its source and running HTTP behavior. Use the plugin's generic
   scaffolding to generate a current-state contract and characterization tests
   from that evidence, then run them against .NET.
   Present the assessment, contract, cases, actual results, and limitations.
   Do not change production source or create the Python environment/implementation.
   Stop for my review of the assessment and candidate baseline.
   ```

2. Follow the agent's progress and review any tool approvals. Wait for it to present its assessment and stop; do not approve the next stage yet.
3. Press **Ctrl+P** in VS Code, paste a path below, and press **Enter** to open each generated file. All paths are relative to the application:

   | File | What to find |
   | --- | --- |
   | `.github\upgrades\dotnet-to-fastapi\assessment.md` | Source and HTTP observations, proposed changes, and limitations. |
   | `tests\baseline\contract.md` | The recorded API behavior and any explicitly documented comparison adjustments. |
   | `.github\upgrades\dotnet-to-fastapi\baseline-report.md` | The actual .NET **Before** run and the location of its TRX test-result file. |

   Follow the assessment's links to the generated case files and actual test results. No contract or tests are supplied by the starter; their absence before this step is expected.

4. Review a small set of examples from the agent's observations:

   | Example to inspect | Review question |
   | --- | --- |
   | A successful read, such as the product request from Step 2 | Do the contract and tests check the observed status, field names, values, and JSON types? |
   | An invalid request | Do the expected error status and response match what .NET actually returned? |
   | An operation that changes state, including repetition or failure | Do the tests check the observed effects, not just that a request completed? |
   | A known gap | Does the assessment explain what was not characterized rather than claiming complete coverage? |

   Ask for corrections or explanations before approval if an example is unsupported. Corrected cases need a new real .NET run and review. Do not provide tests or answers from another checkout.

**Expected result:** An assessment, observed contract, generated cases, and a genuine passing .NET run, with no Python implementation or environment yet.

**Continue when:** You have reviewed the examples and limitations, the agent has stopped, and the actual results show nonzero tests with all passed and none skipped or incomplete. Startup or compilation alone is not a passing baseline.

## Step 5 - Approve the baseline and review the plan

**Where:** The same **application chat**, then the application's editor.

**Freezing** or **sealing** records the approved passing baseline so later changes can be detected. Python must pass those checks; the checks must not be changed to make Python pass.

1. Only after completing the previous review, send:

   ```text
   I approve the current assessment and characterization contract/tests/results.
   Seal this passing baseline, then create the Python migration plan.
   Stop for my review; do not create executable tasks or target code yet.
   ```

2. Wait for the agent to stop with the plan. Open `.github\upgrades\dotnet-to-fastapi\plan.md` with **Ctrl+P**.
3. Check how the plan preserves what you reviewed:

   | In the plan | What to check |
   | --- | --- |
   | API behavior | Observed routes, field names, headers, statuses, and errors stay compatible. |
   | Values and state | Observed JSON types, numeric behavior, input boundaries, and state changes are preserved. |
   | Python implementation | Real Python modules implement the behavior without a CLR bridge or forwarding to C#. |
   | Verification | The frozen checks stay unchanged; the plan records how to launch the independent target. |

4. Request a revision if anything is missing. Review the revised plan before approving; do not move straight to implementation.

**Expected result:** The reviewed passing baseline is sealed and a migration plan is ready. No executable tasks or target code have been created.

**Continue when:** You understand the plan and its mapping from observed .NET behavior to Python. If sealing failed or inputs changed, resolve that and repeat the necessary run/review; never overwrite a freeze to continue.

## Step 6 - Approve the plan and review tasks

**Where:** The same **application chat**, then the application's editor.

1. When satisfied with the current plan, send:

   ```text
   I approve the current plan. Create dependency-ordered tasks with files and acceptance criteria.
   Do not execute them yet.
   ```

2. Wait for the agent to stop. Open `.github\upgrades\dotnet-to-fastapi\tasks.md` with **Ctrl+P**.
3. Find tasks for the Python environment and packages, application behavior, HTTP routes, runtime/schema checks, and comparison against the unchanged baseline.
4. Check that tasks identify prerequisites, files, and acceptance criteria, with places to record real commands and results. Editing frozen tests to get a pass must not be an implementation task.

**Expected result:** A task list derived from the approved plan, with execution still paused.

**Continue when:** You have reviewed the current tasks and are ready to authorize their execution.

## Step 7 - Execute the approved tasks

**Where:** The same **application chat**. Follow generated files in the application's Explorer.

1. Send the separate execution approval:

   ```text
   I approve the current tasks for execution. Implement the Python API.
   Keep the original production source and frozen baseline unchanged.
   Run the same characterized HTTP expectations against the independent target.
   ```

2. Follow task progress and review package-install and tool approvals. The agent now creates `src\orderdesk_python`, root `requirements.txt`, and a local `.venv`.
3. Inspect the changes and recorded results. The Python service must contain the business implementation, not call a CLR or forward requests to C#.
4. If a target check fails, have the agent fix the migration and rerun it. Do not approve changes to frozen expectations, refreshed hashes, or unsupported success claims.

**Expected result:** An independent Python implementation and updated task evidence, including actual target-check results.

**Continue when:** The approved work is complete, no failing or unfinished task is being presented as success, and the original source and frozen baseline are unchanged.

## Step 8 - Compare the results and finish

**Where:** The application's editor and, for a rerun, a **PowerShell 7** terminal at the application root.

1. Open `.github\upgrades\dotnet-to-fastapi\baseline-report.md` and `.github\upgrades\dotnet-to-fastapi\tasks.md` with **Ctrl+P**.
2. Follow their links to the actual **Before** (.NET) and **After** (Python) results. Use the real counts from your run, not the counts from a rehearsal.
3. Confirm the outcome:

   | Evidence | What success looks like |
   | --- | --- |
   | Before and After results | The same nonzero set of test identities passes, with none failed, skipped, or incomplete. |
   | Baseline integrity | The approved test expectations and covered files/hashes have not changed. |
   | Independent execution | The Python comparison succeeds with the C# host stopped. |
   | Runtime and cleanup | Runtime/OpenAPI checks match actual responses, and the agent has stopped its owned hosts. |

4. Find the complete After command in the task evidence. It should include the actual generated target launcher, arguments, working directory, and readiness path. If it is missing, ask the agent to record it before finishing; do not guess a Python launch command.
5. For a repeat comparison, run that exact command from the application root with the manual C# host stopped. The runner manages its own target host. See [baseline verification mechanics](modernization-plugins/README.md#baseline-verification-mechanics) for the runner options.

**Expected result:** The same approved checks pass against both implementations, with reproducible commands and explicit limitations.

**Continue when:** All evidence above is present. **You're finished:** keep your changes local. These checks cover the exercise, not exhaustive compatibility or production readiness.

For blockers, use the [troubleshooting reference](modernization-plugins/README.md#troubleshooting). For an optional look inside the working plugin, follow the [read-only tooling tour](modernization-plugins/README.md#explore-the-plugin).
