# Edge Cases

Handle these gracefully. None should crash the review or silently skip work.

| Case | Handling |
|---|---|
| **Empty diff** | Write a short report: "No changes to review for <confirmed scope>." Exit. Do not spawn workers. |
| **No PR found / invalid PR number** | Re-ask the user for the correct scope. Do not guess or fall back to a different PR. |
| **`gh auth` missing (PR-comments path)** | Write the report anyway. Emit a clear error: "GitHub replies skipped: auth unavailable (<reason>). Report written to <path>. Replies can be posted manually." Do NOT silently skip. |
| **Huge diff** (≈2000+ lines or ≈40+ files) | **Sample**: summarize each file's diff-stat; pick representative files per category for deep review; note partial coverage explicitly in the appendix and flag that coverage is incomplete. Do not silently truncate. |
| **No skills found** | Proceed with general best-practices via web/docs MCPs. Note "no project skills located" in the appendix. |
| **No conventions found** | Default to MoSCoW severity. Note "no project conventions located; using MoSCoW default" in the appendix. |
| **Consensus 3-way deadlock** | Top agent resolves; record the split in the dissenting block (see `.opencode/agent-resources/code-review/rules/consensus.md`). |
| **A worker fails / errors** | Note the failure and continue with sibling workers. Surface the failure in the appendix ("worker for <category> failed: <reason>; category reviewed inline/partially"). |
| **A consensus voter fails / errors** | Majority of the RETURNED voters decides; see the voter-failure rules in `.opencode/agent-resources/code-review/rules/consensus.md`. Never silently drop the finding. |
| **Path C scope is a single file** | Still categorize it (it may span categories by content) and review inline if trivial; no diff exists to slice. |
| **Sensitive data (secrets, PII) in diff** | The `security-sensitive` category is always extracted. Reference sensitive content by `file:line` only - never quote secrets into findings or the report. |
| **Category with a single trivial file** | Do not spawn a dedicated worker - review inline in the top agent or fold into the nearest category. |
| **Cross-category overlap on the same file** | Merge the overlapping categories into one worker to avoid duplicate review of the same lines. |
| **Tool / MCP unavailable** | Fall back per the resource bundle's `fallback_chain` (from the `resource-scout`); if the need wasn't covered, scan your own tool list for a configured MCP, then web search. Note in the appendix if a key source was unreachable. |
| **User declines auto-fix (Step 7)** | Stop. The report is left as-is, unstaged. Do not spawn software-engineer. The user can apply fixes manually from the report. |
| **software-engineer fails on a fix** | software-engineer marks that fix `failed`/`skipped` and continues with siblings - it does not abort the batch. Surface every `failed`/`skipped` fix in the report's "Auto-applied fixes" section and to the user. Do not retry within the same run. |
| **Verify fails after fixes** | Leave the applied fixes in place; record the failure (command + short file:line reference) in the "Auto-applied fixes" section. Do NOT auto-revert - the user decides whether to keep, adjust, or discard the changes. |

## Sampling rule (huge diff)

When sampling:

1. Compute diff-stat per file (lines added/removed).
2. Group files by detected category.
3. Within each category, pick files by: largest change, security-relevance, and
   representativeness of the change type.
4. Deep-review the sampled files; summarize the rest with a one-line note each.
5. State the sampling explicitly: "Sampled N of M files for deep review (diff
   exceeded threshold). Coverage: partial. Full review requires narrower scope."
