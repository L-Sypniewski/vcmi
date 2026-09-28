# Finding Schema

Workers return ONE block per finding using this YAML structure. The top agent
merges all blocks. Keep blocks self-contained - no raw file dumps, no logs.

```yaml
- id: F-<CATEGORY>-<N> # e.g. F-SECURITY-1, F-TESTS-2; F-<CAT>-0 = "no findings"
  category: <detected category>
  severity: Must | Should | Could | Won't # or the repo's taxonomy if conventions define one
  location: "path/to/file.ext:LINESTART-LINEEND"
  title: "<one-line summary>"
  finding: |
    <what is wrong, 2-4 sentences. Be specific. Reference the diff.>
  impact: "<why it matters: correctness | security | performance | maintainability>"
  bug_fix: true # OPTIONAL. Set ONLY when the finding is a runtime/behavior DEFECT fix
                # (impact is correctness / security / data-loss - the "incorrect logic"
                # blocker class). Drives the regression-test-on-fix rule: a `bug_fix: true`
                # finding MUST land with a regression test, TDD-preferred (red-first) - see
                # code-review Step 7 + software-engineer Mode B. Omit for cosmetic,
                # maintainability, doc-drift, or missing-coverage findings that don't fix
                # broken runtime behavior themselves.
  suggested_fix: |
    <a sketch - the direction of the fix, not a full rewrite. Minimal.>
  confidence: High | Medium | Low
  basis: # required when the finding rests on an external claim
    # (see .opencode/agent-resources/shared/rules/citations.md). Omit for self-evident
    # code defects where the code itself is the evidence.
    - source: "<doc title | skill name | convention file | spec>"
      link: "<URL | path:line>"
      quote: "<verbatim excerpt supporting the claim>"
  consensus: # filled by the top agent after the consensus step;
    # omit when workers return blocks.
    status: "2-of-3 uphold | 2-of-3 modify (top-reconciled) | 3-way split (top-resolved) | single-voter (quorum-degraded) | skipped (budget/unavailable)"
    dissent: "<minority reasoning, if any>"
```

## "No findings" block

If a category is clean, return exactly one block marked `status: clean` (NOT a
severity). Clean blocks are NOT counted in the severity tallies.

```yaml
- id: F-<CATEGORY>-0
  category: <category>
  status: clean # reserved for clean categories; do not set a severity here
  title: "No findings"
  finding: "Reviewed <N> files in <category>. No issues meeting <taxonomy> thresholds."
  confidence: High
```

A clean category is a valid outcome - do not invent findings to fill a quota.
`Won't` (severity) is reserved for genuine out-of-scope notes on a REAL finding,
not for clean categories.

## Severity (MoSCoW, default)

| Level      | Meaning                                                                     |
| ---------- | --------------------------------------------------------------------------- |
| **Must**   | Blocks merge. Correctness defect, security vulnerability, data-loss risk.   |
| **Should** | Should fix before/after merge. Significant quality/maintainability concern. |
| **Could**  | Nice-to-have improvement. Minor clarity, style, minor perf.                 |
| **Won't**  | Noted but explicitly out of scope for this change.                          |

If the repo's conventions define a different taxonomy (check AGENTS.md /
CONTRIBUTING.md / prior reviews), USE THAT instead and note the adaptation in the
report appendix.

### Blocker categories - Must or Should, NEVER Could

Some classes of finding are NEVER the lowest tier, regardless of taxonomy. File
any finding in these classes at `Must` or `Should` (never `Could`), unless a
convention defines a stricter rule:

| Class                                                                                                                                                                                                                                                                                                                                                                                                                                  | Default    | Why                                                                                                                                                                                                                 |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **incorrect logic / wrong behavior** - behavior contradicts intent (e.g. an inverted or missing condition, a wrong result)                                                                                                                                                                                                                                                                                                             | **Must**   | Correctness defect.                                                                                                                                                                                                 |
| **dead or stale code** - unreachable code, commented-out code, unused identifiers                                                                                                                                                                                                                                                                                                                                                      | **Should** | Maintainability / rot.                                                                                                                                                                                              |
| **documentation drift / mismatch** - comments, docs, or prompts that contradict the current code                                                                                                                                                                                                                                                                                                                                       | **Should** | Misleads future readers; latent correctness risk.                                                                                                                                                                   |
| **documentation gap** - documentation missing for changed/added behavior                                                                                                                                                                                                                                                                                                                                                               | **Should** | Change is not reproducible/auditable without it.                                                                                                                                                                    |
| **missing test coverage** - changed/added behavior with no test, or coverage removed/weakened                                                                                                                                                                                                                                                                                                                                          | **Should** | Regression risk; the change is unguarded.                                                                                                                                                                           |
| **unjustified complexity** - a materially simpler design meets the same RESOLVED requirement (e.g. a wrapper script built where an inline call works; a guard for a behavior the source shows is already constrained)                                                                                                                                                                                                                  | **Should** | Maintainability - extra surface to test, review, and rot. **Only file when the reviewer cites a working simpler alternative** (source/repo evidence it meets the requirement), never as a vague "this feels heavy." |
| **verbose or over-specific comments** - violates the repo's comment hard-rules (`docs/developers/Coding_Guidelines.md` / `software-engineer.md`/`worker.md`'s comment rules): a comment restating what the code obviously does, run-commands/finding-IDs embedded in source, or concrete instances/enum members named in a comment for generic/extensible code (goes stale as instances are added) | **Should** | Maintainability - the repo's own agents are instructed to avoid this at write time; a slip through review means it reaches a human reviewer instead.                                                                |

`Could` is reserved for genuinely cosmetic / taste-level items only (naming,
formatting, micro-optimizations with no correctness or maintainability impact).
A finding that is wrong, stale, missing, untested, or contradictory is never
`Could`.

This principle applies under ANY severity taxonomy the repo conventions define:
if a convention replaces MoSCoW, a finding of these classes is still filed at the
convention's equivalent of Must/Should - never its lowest tier.

## `bug_fix: true` -> regression test required

A finding tagged `bug_fix: true` (set for the "incorrect logic / wrong behavior" blocker
class - impact correctness / security / data-loss) MUST land with a regression test when it
is fixed, TDD-preferred: write the test first so it FAILS on the unpatched code (proving it
reproduces the defect), then apply the fix so it PASSES. This closes the recurring "the bug
shipped because no test covered the broken path" gap. `code-review` Step 7 carries the tag
into the fix handoff; `software-engineer` Mode B enforces red -> fix -> green. Findings that
are NOT defect fixes (cosmetic, maintainability, doc-drift, pure missing-coverage) omit the
tag and need no regression test.
