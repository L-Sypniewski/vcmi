# Citation Rules

Every claim that rests on an external authority - a best practice, a library
contract, a standard, a project convention - MUST cite its basis. A claim with no
verifiable basis is marked low-confidence with a note explaining it is
unsubstantiated.

Self-evident code defects (a null deref, an off-by-one, a syntax error, a logic bug
visible in the source) do NOT need an external citation - the code is the evidence.
Reference the `location` (`file:line`) and explain the defect directly.

This rule is shared by agents that produce cited output (e.g. `code-review`
finding `basis` fields, `plan-orchestrator` research-note blocks). The discipline is
identical across them: a claim without a verifiable basis is weak, regardless of
which agent produced it.

## Required basis fields

For each external claim, capture ALL THREE of:

- **source** - the name/identifier: doc title, skill name, convention filename,
  spec number.
- **link** - a resolvable pointer: URL, or `path:line` for local files/skills.
- **quote** - a verbatim excerpt from the source that supports the claim.

If any of the three is missing, the citation is incomplete; downgrade confidence
and note the gap. Do not paraphrase a source as if it were a quote.

## When citations apply

| Claim type | Cite from |
|---|---|
| "Best practice says X" | official docs, specs, reputable articles |
| "Library Y requires Z" | library docs (docs MCP / source), with link + quote |
| "This violates our convention" | AGENTS.md / CONTRIBUTING.md / linter config (`file:line`) |
| "This is a known anti-pattern" | skill content (skill name + the quoted section) |
| "Standard N mandates M" | the standard/spec (link + quote) |
| `"X is a Y in this repo"` (structural/identity claim) | the file itself, read/grep/glob this session (`file:line`); else label `_unverified_` |

A structural/identity claim (`"X is a Y in this repo"`) requires `file:line`
evidence from a file read/grep/glob in the current session - or it must be labeled
`_unverified_`. A framework/library default-template convention is NOT acceptable
evidence for a structural claim about this project; at most it is an
`_unverified_` hypothesis to be confirmed by reading the file.

## When multiple sources exist

Prefer multiple independent sources for high-stakes claims. If two reputable
sources agree, cite both. If they conflict, surface the conflict in the claim and
lower confidence. A single blog post is weaker than official docs plus a spec.

## Independent re-pull (when a claim is contested)

When a second agent re-checks a claim (e.g. a consensus voter, or an executor
re-verifying a plan's research note), it independently re-pulls the cited source
and extracts its OWN quote. If the re-pulled quote does not support the claim,
overturn or modify it. Do not trust the excerpt at face value - open the source
and read the surrounding context.
