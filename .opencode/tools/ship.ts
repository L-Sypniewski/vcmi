import { tool } from "@opencode-ai/plugin";
import { evaluateGate } from "./loop";

export const create_pr = tool({
  description:
    "Create a DRAFT PR via gh, but ONLY after the loop gate passes (replan_count<=3 and last_verify=pass). " +
    "If the gate fails, returns a BLOCKED reason and does NOT run gh.",
  args: {
    slug: tool.schema.string(),
    title: tool.schema.string(),
    body: tool.schema.string(),
    head: tool.schema.string(),
    base: tool.schema.string(),
  },
  async execute(args, context) {
    const g = evaluateGate(context.worktree, args.slug);
    if (!g.may_ship) {
      const lv = g.last_verify ? g.last_verify.result : "none";
      return {
        title: "ship_create_pr - BLOCKED",
        output: `BLOCKED: gate failed (replan_count=${g.replan_count}, last_verify=${lv})`,
        metadata: {
          shipped: false,
          replan_count: g.replan_count,
          last_verify: g.last_verify,
        },
      };
    }
    try {
      // Bun.$ treats interpolated values as literal argv (auto-escaped), not shell-substituted.
      const out = await Bun.$`gh pr create --draft --title ${args.title} --body ${args.body} --head ${args.head} --base ${args.base}`
        .cwd(context.worktree)
        .nothrow()
        .text();
      const url = out.trim().split("\n").pop()!.trim();
      return {
        title: "ship_create_pr",
        output: `created draft PR: ${url}`,
        metadata: { shipped: true, url, slug: args.slug },
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return {
        title: "ship_create_pr - gh error",
        output: `gh pr create failed: ${msg}`,
        metadata: { shipped: false, error: msg },
      };
    }
  },
});

export const create_followup_issue = tool({
  description:
    "Create a GitHub follow-up issue via gh issue create (Won't items + substantial unfixable leftovers ONLY - Could findings and review observations are fixed in-branch in step 4b, never issued).",
  args: {
    slug: tool.schema.string(),
    title: tool.schema.string(),
    body: tool.schema.string(),
  },
  async execute(args, context) {
    try {
      const out = await Bun.$`gh issue create --title ${args.title} --body ${args.body}`
        .cwd(context.worktree)
        .nothrow()
        .text();
      const url = out.trim().split("\n").pop()!.trim();
      return {
        title: "ship_create_followup_issue",
        output: `created issue: ${url}`,
        metadata: { url, slug: args.slug },
      };
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return {
        title: "ship_create_followup_issue - gh error",
        output: `gh issue create failed: ${msg}`,
        metadata: { error: msg },
      };
    }
  },
});
