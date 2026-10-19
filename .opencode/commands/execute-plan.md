---
description: Resume executing an existing plan file (execute-only mode)
agent: plan-orchestrator
---

Resume execution of the plan at `.plans/$1.md` in **execute-only mode**: skip clarify/research/synthesize (steps 1–6) and jump straight to Execution (step 8) - parse the plan file, mirror every unchecked `- [ ]` task into `todowrite`, and resume at the first unchecked checkbox. Treat `$1` as the plan slug (so `.plans/$1.md`).
