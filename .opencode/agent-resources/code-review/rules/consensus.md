# Consensus Protocol

Use consensus to sanity-check high-stakes findings before they reach the report.
Do NOT run consensus on every finding - only on findings where being wrong is
costly. This keeps the review tractable.

## When to trigger consensus

After collecting worker findings, identify findings meeting ANY of:

- severity `Must` (highest priority - a wrong "Must" blocks a PR unjustly), OR
- `confidence: High` AND the claim is complex/contestable (relies on a subtle
  interpretation of a doc, a security judgment, a performance trade-off).

For each such finding, spawn 3 independent voters IN PARALLEL (one assistant
message, three Task calls).

## Voter independence

- Each voter receives ONLY: the finding under review, its diff slice, applicable
  conventions. Voters do NOT see each other's reasoning.
- Each voter independently re-pulls the cited source and extracts its OWN quote
  (see `.opencode/agent-resources/shared/rules/citations.md`). Do not trust the finding's excerpt at face value.
- Voter output: `UPHOLD` | `OVERTURN` | `MODIFY` + reasoning + revised
  severity/confidence + corrected fix (if MODIFY).

## Resolution

- **Majority (2-of-3) wins.** Apply the majority verdict to the finding.
- **Conflicting MODIFY votes:** if 2 voters return MODIFY with DIFFERENT revised
  severities/fixes, the top agent reconciles them and records "2-of-3 modify;
  top-agent-reconciled to <verdict/severity> because <reason>". Prefer the more
  conservative (higher-severity) reconciliation when in doubt.
- **Voter failure (1+ of 3 errors/empty):** majority of the RETURNED votes decides.
  - 2 of 2 returned agree → that verdict (note "2 voters returned; 1 failed").
  - only 1 voter returned → set `consensus.status: single-voter`, keep the finding
    but lower its confidence one level, and note the degraded quorum in the
    appendix. This is the ONLY situation that produces `single-voter`.
  - 0 voters returned → skip consensus; flag the finding "consensus unavailable
    (all voters failed) - single-pass, confidence unchanged" in the appendix.
- **Capture the minority.** Append a "Dissenting view" block to the finding with
  the minority's reasoning. Do not discard dissent - the user may reconsider.
- **3-way split (no majority):** the top agent makes the final call. Record the
  split explicitly in the dissenting block ("3-way split; top-agent-resolved to
  <verdict> because <reason>"). Do NOT block on the user.

## What consensus does NOT do

- It does not surface new findings - voters judge ONLY the finding given.
- It does not run on `Should`/`Could`/`Won't` findings unless they are
  High-confidence AND contestable. Most low-severity findings skip consensus.
- It does not replace worker review - it is a targeted check on costly claims.

## Cost note

Voters use the same model as the top agent (per project decision). Each consensus
round is 3× a single review of one finding. Reserve it for findings where the
cost of a wrong call exceeds the cost of the votes.
