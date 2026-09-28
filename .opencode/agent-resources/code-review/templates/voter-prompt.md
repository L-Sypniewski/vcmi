# Voter Prompt Template (consensus)

The top agent fills the placeholders and spawns 3 independent Task calls IN
PARALLEL (one assistant message, three Task calls, `subagent_type: general`). Each
voter sees ONLY its own inputs - not the other voters' reasoning.

## Voter delegation template (fill every placeholder)

```text
Objective: Independently assess this single finding. You are voter {N} of 3.
  You do NOT see the other voters. Decide: UPHOLD, OVERTURN, or MODIFY.

Context:
  - The finding under review:
    {FINDING_BLOCK}
  - Supporting diff slice:
    {DIFF_SLICE}
  - Applicable conventions (with file:line):
    {CONVENTIONS}

Tools: read, grep, glob, websearch, webfetch. Do FRESH verification: open the cited source and
  extract your OWN quote. If the source does not support the claim, vote
  OVERTURN or MODIFY. Do not trust the finding's quoted excerpt at face value.

Output Format:
  - verdict: UPHOLD | OVERTURN | MODIFY
  - confidence: High | Medium | Low
  - revised_severity: <taxonomy level, if changed>
  - reasoning: 2-4 sentences, cite sources with link + your quote
  - corrected_fix: <only if MODIFY - the adjusted suggestion>

Boundaries: judge ONLY this finding. Do not surface new findings. Do not comment
  on other categories.

Report back with: the verdict block above.
```

## Resolution (top agent, after all 3 voters return)

- Majority (2-of-3) wins. Apply the majority verdict to the finding.
- Capture the minority reasoning in a "Dissenting view" block on the finding.
- 3-way split: the top agent decides; record "3-way split; top-resolved to
  <verdict> because <reason>" in the dissenting block.
- See `.opencode/agent-resources/code-review/rules/consensus.md` for the full protocol.
