# Research-First

Auto-loaded via opencode `instructions`. Applies to every session.

One principle, three layers: **discover before doing.**

## Layer 1 - Resource discovery (every task)

Before diving into a task, scan for resources that could shorten the path or improve the
result. Don't assume you know the route; check the available tooling first.

- **Available skills** - review the `<available_skills>` list at session start. Invoke the
  ones genuinely matching the task domain via the `skill` tool. Don't fire every skill
  blindly - pick the relevant few.
- **Documentation MCP servers** - whatever is configured. Use them for current API/behavior;
  training data lags behind releases.
- **Project conventions** - AGENTS.md (root + module-level), relevant module specs, recent
  session logs covering similar ground.
- **Existing codebase patterns** - neighboring files, sibling modules, helper utilities.
  Match established conventions rather than inventing.

## Layer 2 - Claim verification (external-tool assertions)

Before asserting that an external tool, library, CLI, framework, or cloud service
**"fixes"**, **"enables"**, **"unblocks"**, **"simplifies"**, or **"will benefit"** something,
verify against one of (descending strength):

1. The feature's **PR / commit description** - canonical scope statement.
2. The tool's **source code** - when behavior is non-obvious or version-gated.
3. **Official docs via documentation MCP servers** configured in the environment.
4. **Release-note one-liners** - weakest; treat as marketing copy, not a behavior contract.

For each benefit claim, **cite the verification source** inline. Claims that cannot be
verified must be marked **`_unverified_`** - never asserted as fact.

**This layer also covers behavioral unknowns that drive an implementation choice** - cwd,
argument form, env vars, ordering, exit codes. Before adding complexity (a wrapper, adapter,
guard, fallback, or indirection) to handle such a behavior, **resolve it first**: cite the
source code or PR (source > docs is the hierarchy above; **apply it when the docs are
*silent*, not only when they're wrong** - doc-silence usually means you stopped one layer
short, not that the behavior is undefined). If you genuinely cannot resolve it, mark the
assumption **`_unverified_`** and surface it to the caller; **do not silently build
defensive robustness around an unresolved assumption.** Complexity built on a silent
assumption is the exact failure mode this layer exists to prevent.

## Layer 3 - Internal codebase claims

A structural/identity claim about THIS repo ("file/endpoint/module/component/route is/does
X") is grounded only in a file actually **read** (or grepped/globbed) **in the current
session** - cite `file:line`. Otherwise it is a **hypothesis** labeled `_unverified_`,
verified (by reading the file) before being asserted as fact OR acted on downstream (a plan
task, a fix, a user answer).

- **The session is the unit of trust.** Reading the file in a prior session does NOT count;
  re-read it.
- **Framework/library default-template conventions are NOT evidence about this codebase** -
  they are at most an `_unverified_` hypothesis. Forbid asserting a default convention as a
  fact about the project's actual implementation. Motivating failure, abstractly: a
  login-path structural claim inferred from a framework's default template, asserted
  without opening the actual handler or confirming the expected file type exists.
- **Independent re-pull.** When an internal claim is contested or relied upon downstream,
  open the file fresh rather than trusting a prior assertion - verify against the source,
  not the summary. (Mirrors `citations.md`'s "Independent re-pull" section.)

## Anti-patterns to refuse

- Starting a task without checking for relevant skills, MCPs, or conventions when the
  domain clearly has them.
- Paraphrasing a changelog summary as a behavior guarantee.
- "This will let us…" / "This unblocks…" without naming the PR, commit, or doc that says so.
- Treating a tool's reputation as evidence about a specific version's behavior.
- Assuming a fix for surface A also covers surface B because they sound related.
- Asserting "X is a Y in this repo" from a framework/library convention without reading
  the file in the current session.
- Treating a default-template mapping as this project's actual wiring.
- Citing a prior session's file read as grounding for a current-session structural claim.
- Answering a structural question from memory when a single `read`/`grep` would confirm it.
- Treating doc-silence about a tool's runtime behavior (cwd, arg form, ordering) as "must
  be undefined/variable" and building defensive complexity, instead of reading the tool's
  source to resolve it.
- Adding a wrapper/adapter/guard/fallback to handle an unverified assumption, when one
  source-file read would have removed the need for it entirely.

## Fallback when verification is blocked

State the claim as a **hypothesis**, label it `_unverified_`, and gate downstream action on
a verification step. Hypotheses are fine; asserting hypotheses as facts is the failure
mode. Internal structural claims follow the same fallback: state as a hypothesis, label
`_unverified_`, and verify by reading the file before asserting or acting on it. Same for
resource discovery: if a skill or MCP is genuinely unavailable, say so and proceed - but
check first.
