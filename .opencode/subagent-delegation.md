# Subagent Delegation Rules

Auto-loaded via opencode `instructions`. Apply to all delegation decisions.

## When to delegate (vs main context)

**Delegate when:**
- Task produces verbose output (test runs, logs, GitHub/MCP fetches) - keep main context clean
- Work is self-contained and returns a summary
- You need to enforce tool restrictions
- Multiple independent threads can run in parallel

**Stay in main context when:**
- Frequent back-and-forth needed
- Phases share significant context (plan → implement → test)
- Quick targeted change; latency matters

## Parallel vs sequential

Fan out only when work is **truly independent**:
- Different files, no shared imports → separate subagents
- Different concerns on same diff (security / perf / tests) → separate subagents
- Same file, or sequential steps (A→B→C) → single agent

**Coding caveat (Anthropic):** most coding tasks have fewer parallelizable threads than research. Default to sequential.

## opencode mechanics

- Delegate via **Task tool**. Subagents get their own context window.
- **Parallel fan-out** = emit ONE assistant message with multiple Task calls.
- **Sequential chain** = Task A → result → Task B with A's output.
- `permission.task` globs control which subagents an agent may spawn.
- `hidden: true` keeps worker subagents out of `@` menu but still callable.
- `mode: subagent` for workers; `model` inherits from parent if unset.
- `todowrite` is off for subagents by default; enable it via `permission.todowrite: allow` when a subagent needs to own progress tracking (e.g. an executor agent).
- Background subagents lose Task tool at depth 5; omit Task from tools to forbid children entirely.

## Task delegation template

Every Task call must include:
- **Objective**: what to accomplish
- **Context**: file:line, relevant state, exact request
- **Tools/Sources**: which tools/docs to use
- **Output Format**: structured format expected
- **Boundaries**: in/out of scope
- **Report back with**: artifact/reference + commit SHA or file path

> **Citation discipline**: workers that produce cited output (e.g. `code-review`
> finding `basis` fields, `plan-orchestrator` research-note blocks) follow the
> shared rule at `.opencode/agent-resources/shared/rules/citations.md`
> (source + link + quote for every external claim). The per-agent worker prompts
> (`code-review/templates/worker-prompt.md`, `plan-orchestrator/templates/worker-prompt.md`)
> implement this skeleton and add the citation requirement on top.

## Principles

1. Default to main context; delegate deliberately (subagents pay latency + token cost)
2. Fan out only when truly independent (no shared files, no step dependencies)
3. ALWAYS isolate high-volume output (tests, logs, GitHub/MCP) into subagents
4. Each delegation needs objective + output format + tools + boundaries
5. Plan fan-in (synthesis) BEFORE fan-out
6. Avoid "game of telephone" - subagents write artifacts, return lightweight references
7. Group related work (same file/nearby lines/concern) into one subagent; unrelated → separate

## Error handling

- Subagent fails: note and continue with siblings; surface in summary
- Tool failure: retry once, fall back (e.g., MCP → gh CLI), or report
- Decide per workflow: rollback / retry / escalate

## Anti-patterns

- Spawning many subagents for trivial work (overhead exceeds value)
- Fan-out without fan-in plan (wasted work, no synthesis)
- Parallel mutations on shared files (merge conflicts)
- Nesting too deep (omit Task from tools to forbid children)
- Routing cheap read-only work to expensive models (use Haiku-class for exploration)
- Vague delegation prompts → duplicated/gapped work
1