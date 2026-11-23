# Central plugin repository

This folder represents the central repository for a complete **orderdesk-migrator** plugin package. Its scenario is a **C# Web API 2 to Python FastAPI** port, not a .NET version upgrade.

```text
modernization-plugins\
  .github\plugin\marketplace.json
  plugins\orderdesk-migrator\
    plugin.json
    com.github.copilot\agents\orderdesk-migrator.agent.md
    skills\
      target-architecture\SKILL.md
      assess-dotnet-api\SKILL.md
      baseline-tests\SKILL.md
      plan-cross-language-migration\SKILL.md
      dotnet-to-fastapi\SKILL.md
```

The package uses Agent Plugins 1.0: portable skills live at the root, and Copilot-specific agents live under `com.github.copilot`. Small assessment/plan/task templates live inside their skills.

For this local exercise, install the [plugin folder](plugins/orderdesk-migrator/README.md) using VS Code's **Chat: Install Plugin from Source**. The marketplace catalog demonstrates central distribution; you do not need to publish a repository.

In a real separate repository, the catalog's plugin source is relative to that repository root. Do not register the outer workshop GitHub repository as if this nested catalog were at its root.

The agent coordinates stages and approvals; skills provide target rules, evidence gathering, baseline handling, planning, and translation. Generated application reports and Python source belong to the **application** repository, never the installed plugin cache.

See the [Lab 3 walkthrough](../README.md). No skill-edit exercise, MCP server, hook, automatic Git operation, or cloud resource is required.
