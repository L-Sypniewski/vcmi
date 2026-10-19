# Edge Cases

Handle these gracefully. None should abort the plan or silently skip work.

| Case | Handling |
|---|---|
| **Ambiguous / underspecified goal** | Do NOT decompose. Ask the user clarifying questions first (Step 1). Re-ask with concrete options if the answer is still vague. |
| **Goal has no success criteria** | Ask the user to state the acceptance criteria before researching. A plan without a definition of done is not synthesizable. |
| **Worker returns no findings / empty** | Note the gap. Either research that thread inline in the orchestrator, or flag it as an `Open Question` in the plan. Do not silently drop the thread. |
| **Two workers disagree** | Surface the conflict in the plan's `Decisions & Rationale` section: record both views, pick one with a one-line reason, mark the other as the rejected alternative. Do not average or hide the disagreement. |
| **Research reveals the goal needs schema/infra changes not in scope** | Stop and re-confirm scope with the user before synthesizing. Record the scope expansion as an `Open Question` if the user defers. |
| **Plan file already exists for the slug** | Do NOT silently overwrite. Append a `-2` (then `-3`, …) suffix to the slug, or ask the user whether to supersede the existing file. |
| **User declines the execute gate (Step 7)** | Stop. The plan file is already written - the user can resume later via `/execute-plan <slug>`. Do not execute. |
| **A thread turns out to depend on another mid-research** | A worker cannot hand off to a sibling. It returns what it found; the orchestrator spawns the dependent thread next (sequential), passing the first thread's output as context. |
| **Verify fails during execution** | Hard-fail: stop, leave the todo + checkboxes reflecting reality, report the failure to the user. Do not auto-revert or retry blindly. |
| **Tool / MCP unavailable** | Fall back per the resource bundle's `fallback_chain` (from the `resource-scout`); if the need wasn't covered, scan your own tool list for a configured MCP, then web search. Note in the plan's `Open Questions` if a key source was unreachable and a claim rests on weaker evidence. |
| **Sensitive data (secrets, PII) encountered** | Reference by `file:line` only - never quote secrets into the plan file. |
| **Trivial goal (single small change, no risk)** | Skip fan-out; research inline and write a **lean** plan (see `templates/plan-file.md`). Do not pad small work with ceremony. |
| **Per-phase commit fails (hook rejects / nothing to commit)** | Record the failure. Leave the phase's changes staged/unstaged as they are. Tick the plan checkbox only if the phase's WORK is done (verify passed). Surface the commit failure to the user - do NOT retry blindly or skip the phase. |
