# OrderDesk migrator

A packaged **1.1.0** workflow that starts from an ordinary C# / .NET Framework Web API 2 application and discovers its behavior before a Python/FastAPI port. No migration contract or harness must already exist in the application.

Install this folder in VS Code using **Chat: Install Plugin from Source**. Use the **Copilot** harness, enable the plugin, and start a fresh chat in the OrderDesk application folder. Select **orderdesk-migrator** in the agent picker.

The agent uses five skills:

| Skill | Purpose |
| --- | --- |
| target-architecture | Destination standards and cross-language pitfalls, not assumed source facts |
| assess-dotnet-api | Source/HTTP discovery and a reviewable assessment/characterization bundle |
| baseline-tests | Generic bootstrap, agent-authored cases, actual .NET results, reviewed freeze and recheck |
| plan-cross-language-migration | Map C# behavior to Python and produce reviewable work |
| dotnet-to-fastapi | Translate the API and verify the unchanged contract |

Assessment includes authoring a target-neutral behavioral contract and meaningful cases from the actual application. Generic resources under `skills\baseline-tests` contain no completed business tests. The agent must not obtain answers from sibling folders or previous runs.

The workflow stops for assessment/baseline, plan, and task/execution approvals. A passing candidate baseline is sealed after review, before planning. Hashes detect later changes; neither markers nor instructions are security boundaries.

The plugin includes no MCP servers, hooks, telemetry, cloud deployment, or automatic Git operations. Generated source and reports belong to the application workspace, not the installed plugin directory.

In the workshop checkout, see `labs\03-custom-plugin\README.md` for setup, prompts, and completion criteria. Participants use the working plugin; they do not edit its skills.
