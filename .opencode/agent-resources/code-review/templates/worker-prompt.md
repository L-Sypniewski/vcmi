# Worker Prompt Template (per-category reviewer)

The top agent fills the `{PLACEHOLDERS}` and spawns ONE Task call per category.
Fan out categories in parallel where they touch disjoint files (one assistant
message, multiple Task calls). Merge overlapping categories into one worker.

## Delegation template (fill every placeholder)

```text
Objective: Review the {CATEGORY} slice of the diff. Surface correctness, security,
  performance, maintainability, and convention-violation findings WITHIN YOUR
  CATEGORY ONLY.

Context:
  - Review slice (your category's files) - diff hunks for Path A/B, FULL file
    content for Path C (static scope):
    {PASTED_REVIEW_SLICE}
  - Category: {CATEGORY}
  - Resource bundle (produced by the `resource-scout`; USE it - do not
    re-discover): convention files to read in priority order, doc sources per
    need, fallback chain, one-line research plan:
    {RESOURCE_BUNDLE}
  - Severity taxonomy: MoSCoW (Must / Should / Could / Won't) unless a convention
    above defines otherwise. Apply the `Blocker categories` rule in `finding-schema.md`:
    incorrect logic, dead/stale code, documentation drift/mismatch, documentation
    gaps, and missing test coverage are filed `Must`/`Should` (never `Could`);
    `Could` is cosmetic/taste-level only.

USE the resource bundle above for context discovery - read the named convention
  files, webfetch the named doc pages. Do NOT re-discover; the scout already
  selected. If a need arises the bundle didn't cover, fall back to websearch →
  webfetch. For the citation discipline (source + link + quote) every external
  claim must follow, READ
  `.opencode/agent-resources/shared/rules/citations.md`. Do the doc fetches and
  convention reads yourself - the top agent does not pre-digest them for you.

Tools you may use: read, grep, glob, websearch, webfetch. Load relevant skills
  via the skill tool if the bundle names any. For understanding existing code
  beyond the pasted review slice (e.g. tracing a call path the diff touches),
  grep/glob/read the repo - orient from `docs/developers/Code_Structure.md` and
  `lib/constants/` for entity IDs. You MAY spawn sub-subagents via Task IF your
  category is broad (e.g. "language/cpp" splitting into battle / serialization /
  ui) - do so only when warranted, not reflexively.

Output Format: return one finding block PER FINDING using the finding schema
  (.opencode/agent-resources/code-review/templates/finding-schema.md). Include
  source+link+quote in `basis` for any claim resting on an external source
  (.opencode/agent-resources/shared/rules/citations.md). No raw file dumps, no logs.
  If your category is clean, return one "no findings" block.

Boundaries: review ONLY {CATEGORY}. If you notice an issue clearly outside your
  category, note it as a one-liner "cross-category flag" at the end - do not
  elaborate; the top agent will route it.

Report back with:
  1. The finding blocks.
  2. A one-line self-assessment of coverage (what you checked).
  3. Any sub-subagents you spawned (for the appendix).
```

## Fan-out discipline

- Parallel fan-out = ONE assistant message with multiple Task calls (independent
  categories). Sequential only when a category depends on another's result.
- Workers return lightweight structured findings - never raw output, never full
  file contents. This keeps the top agent's context clean.
- If a worker would only review a single trivial file, do not spawn it - review
  inline in the top agent instead.
- If two categories overlap on the same file, merge them into one worker to avoid
  duplicate review of the same lines.
- The top agent spawns each worker with `subagent_type: general` (the reviewing
  worker type; `explore` is read-only navigation and is not used for review).
