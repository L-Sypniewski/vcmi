# Worker Prompt Template (research worker)

The plan orchestrator fills the `{PLACEHOLDERS}` and spawns ONE Task call per
investigation thread. Fan out threads in parallel only where they are truly
independent (different files/concerns, no shared includes); default to sequential
when one thread's output feeds another.

## Delegation template (fill every placeholder)

```text
Objective: Investigate <THREAD> to inform the plan for <GOAL>. Surface findings
  WITHIN YOUR THREAD ONLY: what exists today, what would need to change, risks,
  edge cases, and any decision-relevant evidence.

Context:
  - Goal: <GOAL>
  - Your thread: <THREAD>
  - Known state: <file:line references the orchestrator already has>
  - Resource bundle (produced by the `resource-scout`; USE it - do not
    re-discover): convention files to read in priority order, doc sources per
    need, fallback chain, one-line research plan:
    {RESOURCE_BUNDLE}

USE the resource bundle above for context discovery - read the named convention
  files, webfetch the named doc pages. Do NOT re-discover; the scout already
  selected. If a need arises the bundle didn't cover, fall back to websearch →
  webfetch. For the citation discipline (source + link + quote) every external
  claim must follow, READ
  `.opencode/agent-resources/shared/rules/citations.md`. Do the doc fetches and
  convention reads yourself - the orchestrator does not pre-digest them for you.

Tools you may use: read, grep, glob, websearch, webfetch. Load relevant skills
  via the skill tool if the bundle names any. You MAY spawn sub-subagents via
  Task IF your thread is broad - do so only when warranted, not reflexively.

Output Format: return COMPACT, CITED research-note blocks - one per finding. Each
  block: claim · location (`file:line`) · basis (source + link + quote, per
  `.opencode/agent-resources/shared/rules/citations.md`) · relevance (one line:
  how it should shape the plan). Plus any decision you recommend, with rejected
  alternatives and the one-line reason each was rejected. No raw file dumps, no
  logs, no full file contents. If your thread is clean (nothing to flag), say so
  in one line.

Boundaries: investigate ONLY <THREAD>. If you notice something clearly outside
  your thread that the plan must account for, note it as a one-liner
  "cross-thread flag" at the end - do not elaborate; the orchestrator will route it.

Report back with:
  1. The research-note blocks (cited).
  2. Any recommended decisions + rejected alternatives.
  3. A one-line self-assessment of coverage (what you checked).
  4. Any sub-subagents you spawned.
```

## Fan-out discipline

- Parallel fan-out = ONE assistant message with multiple Task calls (independent
  threads). Sequential only when a thread depends on another's result. When unsure,
  default to sequential.
- Workers return lightweight cited research-notes - never raw output, never full
  file contents. This keeps the orchestrator's context clean while PRESERVING the
  cited authority the plan needs to be self-contained.
- If a thread is trivial (a single quick lookup), do not spawn a worker - resolve
  it inline in the orchestrator.
- Spawn each worker with `subagent_type: general`.
