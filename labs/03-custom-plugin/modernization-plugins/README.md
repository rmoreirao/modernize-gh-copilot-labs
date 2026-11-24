# OrderDesk migrator: plugin reference

This is the reference for the complete **orderdesk-migrator 1.1.0** plugin. For setup, copyable prompts, and participant checkpoints, follow the [Lab 3 walkthrough](../README.md).

Use this page to [understand the components](#how-the-custom-plugin-works), [explore the tooling](#explore-the-plugin), [resolve a blocker](#troubleshooting), or read the [recorded verification boundary](#rehearsal-and-verification-boundary). Participants use the working plugin; they do not build it or edit a skill.

## How the custom plugin works

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

### Package layout and distribution

This workshop folder represents a central plugin repository:

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

The [manifest](plugins/orderdesk-migrator/plugin.json) identifies the package. Local installation uses the **package folder**, not the manifest file or this outer folder. The [marketplace catalog](.github/plugin/marketplace.json) demonstrates central distribution; it is not an execution step, and no repository publication is required.

In a real separate repository, catalog sources are relative to that repository root. Do not register the outer workshop GitHub repository as if this nested catalog were at its root.

The package uses Agent Plugins 1.0. `com.github.copilot` holds harness-specific customization; `skills` holds portable instructions. Within skills, `scripts` contains executable helpers and `templates` contains reusable scaffolding. Crucially, `baseline-tests\tests` checks **plugin tooling**, not application behavior: the application-specific contract and cases do not ship here.

### Agent and skills

| Component | Responsibility |
| --- | --- |
| [orderdesk-migrator agent](plugins/orderdesk-migrator/com.github.copilot/agents/orderdesk-migrator.agent.md) | Coordinate stages, workspace boundaries, approvals, and recovery. |
| [target-architecture](plugins/orderdesk-migrator/skills/target-architecture/SKILL.md) | Define destination rules, not facts about the source API. |
| [assess-dotnet-api](plugins/orderdesk-migrator/skills/assess-dotnet-api/SKILL.md) | Discover source and live HTTP behavior; assemble the assessment. |
| [baseline-tests](plugins/orderdesk-migrator/skills/baseline-tests/SKILL.md) | Bootstrap the harness, guide case authoring, run, seal, and recheck. |
| [plan-cross-language-migration](plugins/orderdesk-migrator/skills/plan-cross-language-migration/SKILL.md) | Produce the plan, then tasks after plan approval. |
| [dotnet-to-fastapi](plugins/orderdesk-migrator/skills/dotnet-to-fastapi/SKILL.md) | Implement approved tasks; verify the unchanged contract. |

## Workflow and approval gates

The original application does not know the destination. The agent discovers its source and HTTP behavior, then generates a candidate contract and characterization tests. A **baseline** is this recorded behavior and the HTTP checks used to compare implementations.

| Stage | Required pause |
| --- | --- |
| Discover source and HTTP behavior; generate assessment, contract, cases, and a passing .NET run | Learner reviews and approves the current assessment and candidate baseline. |
| Seal the approved passing baseline; create the migration plan | Learner reviews and approves the current plan. |
| Create dependency-ordered tasks | Learner reviews the current tasks and explicitly approves execution. |
| Implement Python; run the same frozen checks with C# stopped | Learner reviews actual Before/After results, integrity evidence, and limitations. |

Approvals apply to the current content. A revision invalidates its approval and dependent work. Before freezing, incorrect characterization can be corrected from source/HTTP evidence, rerun, and reviewed again. After freezing, fix target failures rather than changing expectations or overwriting the freeze.

The agent reads only the active application and installed plugin's generic resources. It must not obtain behavior or test cases from sibling folders, facilitator suites, previous rehearsals, or target answers.

### Generated application files

All paths below are relative to the **application checkout**, never the workshop or installed plugin cache.

| Location | Created for |
| --- | --- |
| `tests\baseline` | Observed contract, generated HTTP cases, and generic test infrastructure during assessment. |
| `scripts\Test-Baseline.ps1` | Running and sealing the characterization baseline. |
| `.github\upgrades\dotnet-to-fastapi` | Assessment, plan, tasks, baseline report, and actual test-result evidence. |
| `src\orderdesk_python`, `requirements.txt`, `.venv` | The independent target, only after task execution is approved. |

The original production source stays unchanged. The plugin includes no MCP server, hook, automatic Git operation, cloud deployment, or participant skill-edit exercise. Preserve unrelated files, extensions, and normal native approvals.

### Baseline verification mechanics

The generic runner uses `-Phase Before` and `-Phase After` with explicit host inputs: executable, JSON argument array, working directory, base URL, and readiness path. It has no built-in `-Target Python` mode. Use the complete commands recorded for the actual generated implementation, not guessed launch commands.

The .NET 10 HTTP project is verification tooling, not a retargeting of the .NET Framework application. Its fixture starts fresh hosts, checks readiness, refuses an occupied port, and cleans up only its own processes.

The runner records `baseline-report.md` and actual TRX test-result files in the chosen evidence directory. Require real nonzero discovery, all passed outcomes, and no skipped or incomplete results. A process, successful build, or report file alone is not success.

Sealing checks that the current inputs and genuine passing Before evidence still match. The frozen set covers expectations, fixture/project, SDK configuration, and runner. Target launch inputs and report/TRX outputs are separate. After migration, require the same test identities and covered file set/hashes, with C# stopped.

Approval markers and hashes are review guardrails and tamper detection, not security boundaries. Follow normal tool/trust approvals. Focused characterization does not establish exhaustive compatibility or production readiness.

## Explore the plugin

For an optional read-only tour:

1. Open the [agent definition](plugins/orderdesk-migrator/com.github.copilot/agents/orderdesk-migrator.agent.md) and find its required stages and pauses.
2. Follow [assess-dotnet-api](plugins/orderdesk-migrator/skills/assess-dotnet-api/SKILL.md) into [baseline-tests](plugins/orderdesk-migrator/skills/baseline-tests/SKILL.md). Notice that the application supplies the evidence; the plugin supplies procedures.
3. Compare the [initializer](plugins/orderdesk-migrator/skills/baseline-tests/scripts/Initialize-Baseline.ps1) with the [runner template](plugins/orderdesk-migrator/skills/baseline-tests/templates/Test-Baseline.ps1). They provide infrastructure, not a prewritten business contract.
4. Read the planning and implementation skills in the [component table](#agent-and-skills) to see how destination guidance and approved work fit together.

**References:** [Plugin authoring](https://code.visualstudio.com/docs/agents/reference/agent-plugin-reference), [FastAPI validation/errors](https://fastapi.tiangolo.com/tutorial/handling-errors/), [Pydantic Decimal serialization](https://docs.pydantic.dev/latest/api/standard_library_types/), and [simplejson decimal support](https://simplejson.readthedocs.io/en/latest/).
