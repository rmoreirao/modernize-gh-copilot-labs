# Modernize

A packaged workshop workflow for a **C# / .NET Framework 4.8 Web API 2 to Python / FastAPI** port. This is not a .NET version upgrade.

Install this folder in VS Code using **Chat: Install Plugin from Source**. Use the **Copilot** harness, enable the plugin, and start a fresh chat in the OrderDesk application folder. Select **modernize** in the agent picker.

The agent uses five skills:

| Skill | Purpose |
| --- | --- |
| target-architecture | Python target and compatibility rules |
| assess-dotnet-api | Evidence-backed inventory of the legacy application |
| baseline-tests | Execute and freeze the independent HTTP oracle |
| plan-cross-language-migration | Map C# behavior to Python and produce reviewable work |
| dotnet-to-fastapi | Translate the API and verify the unchanged contract |

It stops for separate assessment, plan, and task approvals. It never approves its own work. Baseline source hashes detect changes; neither hashes nor agent instructions are a security boundary.

The plugin includes no MCP servers, hooks, telemetry, cloud deployment, or automatic Git operations. Generated source and reports belong to the application workspace, not the installed plugin directory.

In the workshop checkout, see `labs\03-custom-plugin\README.md` for setup, prompts, and completion criteria. Participants use the working plugin; they do not edit its skills.
