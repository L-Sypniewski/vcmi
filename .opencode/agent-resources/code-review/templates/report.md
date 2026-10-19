# Report Template

File: `docs/reviews/<YYYY-MM-DD>-<slug>.md` (slug from branch or PR title).

```markdown
# Code Review - <PR_TITLE_OR_BRANCH>

> **Path:** <General diff | PR-comments | Static> · **Scope:** <PR #N / branch..base / staged / unstaged / file(s)|folder(s)>
> **Generated:** <ISO date> · **Reviewer:** code-review agent (model: <model>)

## Summary

- **Verdict:** <APPROVE / REQUEST CHANGES / BLOCK>
- **Files reviewed:** <N> · **Review set:** +<A> / −<D> (Path A/B) | <N> files / <L> lines (Path C)
- **Findings:** <count per severity>
- **Categories detected:** <list>
- **Consensus votes run:** <N> findings (2-of-3)

## What this code does well
<!-- lead with positives. calibration honesty: a zero-Must report is valid. -->

## Findings by category

### <Category 1>
<!-- findings severity-ordered: Must → Should → Could → Won't -->

#### F-<CAT>-<N> - <title>  ·  `<severity>` · `<confidence>`
**Location:** `path:line`
**Finding:** …
**Impact:** …
**Suggested fix:** …
**Basis:**
- source: … · link: … · quote: "…"
<details><summary>Dissenting view (consensus)</summary>…</details>

### <Category 2>
…

## Severity-ranked action items
1. **[Must]** F-… - …
2. **[Must]** F-… - …
3. **[Should]** F-… - …

## Dissenting views
<!-- all consensus minority opinions collected here for visibility -->

## References
<!-- every source cited across findings, deduplicated -->
- docs: <library/topic> - <link>
- skill: <name> (<path>)
- convention: <file> §<section>
- web: <article> - <link>

## What was reviewed (appendix)
- **Review-set stats:** <per-file diff-stat (Path A/B) | per-file line counts (Path C)>
- **Categories detected:** <table: category → files>
- **Context sources consulted:** <MCP calls, skills loaded, conventions read>
- **Workers spawned:** <N per-category, <M> consensus voters; any sub-subagents>
- **Coverage notes:** <full review | sampled (reason) | partial (worker failures)>
- **Sampling (if huge diff):** <sampled N of M files; threshold reason>
- **Severity taxonomy:** <MoSCoW default | adapted from <convention>>
- **PR-comments path only - GitHub replies posted:** <N threaded / failed: <reason>>
```
