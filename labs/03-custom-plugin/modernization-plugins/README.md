# Central plugin repository

This folder represents the central repository for the complete **orderdesk-migrator 1.1.0** plugin. It starts from an ordinary C# Web API 2 application, discovers its behavior, generates reviewed characterization, and ports it to Python FastAPI.

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

The agent coordinates stages and approvals; five skills provide destination guidance, source/HTTP discovery, generic baseline bootstrap, planning, and translation. The `baseline-tests` skill carries reusable initializer/templates, not completed application tests or a prewritten compatibility contract.

The original application does not know the destination. Characterization infrastructure, contract/cases, and reports are created in the application during assessment. A passing candidate is reviewed and frozen before planning; target code/environment and target ignore rules are created only after execution approval.

Current-state facts must come from the active application, not from a fixed sample specification, sibling facilitator assets, or earlier answers. Generated reports and source belong to the **application**, never the installed plugin cache. Preserve unrelated extensions and normal native approvals.

See the [Lab 3 walkthrough](../README.md). No skill-edit exercise, MCP server, hook, automatic Git operation, or cloud resource is required.
