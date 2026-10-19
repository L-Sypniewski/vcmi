# Plan-File Format (tiered)

The plan file is the durable artifact. It is the ONLY thing an executor agent
receives when resuming via `/execute-plan <slug>` or a cross-session handoff - so
it must be self-contained: every task carries its own `file:line`, rationale, the
decision that made it necessary, and (for non-obvious claims) cited authority. See
the Self-containment contract in `plan-orchestrator.md`.

Phases are ordered; each phase's tasks are `- [ ]` checkboxes (the durable tracking
mechanism - the executor ticks them `- [ ]` → `- [x]` as work lands).

## Tiering: full vs. lean

Classify the plan at synthesis time, BEFORE writing the file. Record the tier in
the `> Source:` header.

- **lean** - ALL of: single phase AND zero `⚠️`-flagged HIGH-risk tasks AND zero
  external-authority claims (no doc/spec/skill cited). Use the lean skeleton.
  Mandatory even in lean: `file:line` per task, one-line rationale per task, and
  the `Goals` / `Non-goals` / `Context` sections.
- **full** - anything else. Use the full skeleton; `Decisions & Rationale` and
  `Research Findings (cited)` are REQUIRED.

When in doubt, default to **full**. Lean is a concession for genuinely small work,
not a way to skip recording decisions.

## Full skeleton

```markdown
# <Plan Title>

> Source: plan-orchestrator <YYYY-MM-DD>. Approach: <parallel/sequential/hybrid summary>. Tier: full.

## Goals

1. ...

## Non-goals (explicit)

- ...

## Context

<2-6 sentences: what exists today (cite `file:line`), what changes, why now.>

## Linked issues (omit entirely if none)

Fixes #NNN[, #MMMM]

## Decisions & Rationale

- **<decision>** - alternatives: <alt A (rejected: <one-line why>)>, <alt B (rejected: <…>)>.
  Tradeoff accepted: <…>. Basis: <source+link, or "code-internal: `file:line`">.
- ...

## Research Findings (cited)

- **<claim that shaped the plan>** - source: <doc/spec>; link: <URL | `path:line`>;
  quote: "<verbatim excerpt>"; relevance: <one line on how it shaped the plan>.
- ...

## Assumptions & Constraints

- <assumption made during synthesis> - confirm before implementing
- <hard constraint, e.g. "must keep older saves loadable (serialization compat)">

## <Phase N> - <name> (note "parallel, disjoint files" when applicable)

- [ ] **N.1** <task> - `path/file.ext:line` - rationale
- [ ] **N.2** <task> ⚠️ <one-line risk, HIGH only> - `path/file.ext:line` - rationale
      **Verify**: `cmake --build --preset macos-ninja-test`, then (from `out/build/macos-ninja-test/bin/`) `timeout 300 ./vcmitest --gtest_filter='NewSuite*'` scoped to this phase's own new/changed tests. Full unfiltered suite only with a stated reason - see Rules.
      **Commit**: <optional one-line commit message for this phase; omit if no commit is desired>

## Key Risks & Mitigations (omit entirely if none worth flagging)

- <risk> → <mitigation>

## Open Questions (omit if none)

- <decision needing the user before phase X can start>
```

## Lean skeleton

```markdown
# <Plan Title>

> Source: plan-orchestrator <YYYY-MM-DD>. Approach: <summary>. Tier: lean.

## Goals

1. ...

## Non-goals (explicit)

- ...

## Context

<1-3 sentences.>

## Linked issues (omit entirely if none)

Fixes #NNN[, #MMMM]

## <Phase 1> - <name>

- [ ] **1.1** <task> - `path/file.ext:line` - rationale
      **Verify**: <build + targeted filter - see Rules>
      **Commit**: <optional one-line commit message for this phase; omit if no commit is desired>
```

## Rules for the file

- Cite `file:line` references from worker findings on every task.
- Include a `**Verify**` step per phase. **Test preset** = `macos-ninja-test`
  on the macOS host, `linux-gcc-test -DENABLE_MMAI=OFF` inside the devcontainer
  (build there with `CMAKE_BUILD_PARALLEL_LEVEL=2`); below the preset name
  stands for whichever applies. Default: a compile check
  (`cmake --build --preset macos-ninja-test` - warnings-as-errors is ON via
  `ENABLE_STRICT_COMPILATION`) plus a `--gtest_filter`-scoped run of just this
  phase's own new/changed test suites (from `out/build/macos-ninja-test/bin/`:
  `timeout 300 ./vcmitest --gtest_filter='A*|B*'` - the resource loader
  resolves `CONFIG/FILESYSTEM` relative to cwd, and `timeout` exit 124 = hang
  = failure) - NOT the unfiltered full suite. `@ship` step 2b runs
  the full diff-scoped regression sweep right after implementation, so a full
  `vcmitest` per phase on top of that is duplicated build+init cost. Only
  specify the full unfiltered suite when a phase has a concrete reason to need
  the whole regression check before the next phase starts (e.g. a
  serialization-format phase) - state that reason inline next to the Verify line
  so it isn't silently copy-pasted into unrelated phases.
- Optional `**Commit**:` step per phase: in standalone execute, the orchestrator
  commits after each green Verify using the phase's `**Commit**:` message (if
  present); if absent, it commits the phase's changes with a generated message.
  Omit the line entirely for phases where a commit isn't desired.
- Note parallelizable phases explicitly (e.g. "parallel, disjoint files").
- Flag only HIGH-risk tasks with a `⚠️ <risk>` inline annotation - do not annotate
  every task.
- Optional sections (Assumptions & Constraints, Key Risks & Mitigations, Open
  Questions) may be omitted when a simple goal doesn't warrant them - do not pad
  the file with empty sections.
- In a **full** plan, `Decisions & Rationale` and `Research Findings (cited)` are
  NOT optional - they are the self-containment payload that lets a fresh executor
  proceed without the research conversation.
- Optional `## Linked issues` section: a single line using the GitHub auto-close
  keyword `Fixes` - `Fixes #123` for one issue, `Fixes #123, fixes #456` for
  several (**each issue needs its own closing keyword**). `ship` reads this line
  and includes it in the PR body so the linked issue(s) auto-close on merge.
  Omit the section ENTIRELY when there is no linked issue - never emit a
  placeholder.
