import { tool } from "@opencode-ai/plugin";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const MAX_ITERATIONS = 3;

export type VerifyResult = { result: "pass" | "fail"; command: string } | null;
type LoopState = {
  replan_count: number;
  last_verify: VerifyResult;
  // Commit SHA at which a diff-scoped test sweep last PASSED (step 2b / a
  // loop-iteration re-sweep / 4b's confirm-sweep) - independent from
  // last_verify so a bare phase-Verify-only record (step 2, before the sweep
  // runs) never clobbers it. Downstream sweep-scope derivation diffs from
  // this commit instead of <base> once it is set, so an iteration whose fix
  // only touched one tree doesn't re-pay the other tree's already-green
  // suite. Null until the first sweep passes.
  last_sweep_commit_sha: string | null;
  history: Array<Record<string, unknown>>;
};

function statePath(worktree: string, slug: string): string {
  return join(worktree, ".plans", `${slug}.loop.json`);
}

function readState(worktree: string, slug: string): LoopState {
  const p = statePath(worktree, slug);
  if (!existsSync(p)) {
    return {
      replan_count: 0,
      last_verify: null,
      last_sweep_commit_sha: null,
      history: [],
    };
  }
  try {
    const raw = JSON.parse(readFileSync(p, "utf8"));
    return {
      replan_count: Number(raw.replan_count ?? 0),
      last_verify: raw.last_verify ?? null,
      last_sweep_commit_sha:
        typeof raw.last_sweep_commit_sha === "string"
          ? raw.last_sweep_commit_sha
          : null,
      history: Array.isArray(raw.history) ? raw.history : [],
    };
  } catch {
    return {
      replan_count: 0,
      last_verify: null,
      last_sweep_commit_sha: null,
      history: [],
    };
  }
}

function writeState(worktree: string, slug: string, state: LoopState): void {
  const p = statePath(worktree, slug);
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, JSON.stringify(state, null, 2), "utf8");
}

// Single source of truth for the ship gate. Both `gate_check` (this file) and
// `create_pr` (ship.ts) call this so the condition cannot drift between copies.
export function evaluateGate(
  worktree: string,
  slug: string,
): {
  may_ship: boolean;
  replan_count: number;
  last_verify: VerifyResult;
} {
  const state = readState(worktree, slug);
  const may_ship =
    state.replan_count <= MAX_ITERATIONS &&
    state.last_verify?.result === "pass";
  return {
    may_ship,
    replan_count: state.replan_count,
    last_verify: state.last_verify,
  };
}

// Read-only: the commit SHA at which a diff-scoped test sweep last passed, or
// null if no sweep has passed yet this run. Callers diff sweep scope from
// this commit instead of <base> once it is set (see LoopState doc comment).
export function lastSweepCommitSha(
  worktree: string,
  slug: string,
): string | null {
  return readState(worktree, slug).last_sweep_commit_sha;
}

export const record_replan = tool({
  description:
    "Record one replan iteration for the plan-slug's review->replan loop. " +
    "Code-enforced cap at 3: refuses to increment past 3 and returns may_replan:false.",
  args: {
    slug: tool.schema
      .string()
      .describe("Plan slug (the .plans/<slug>.md identifier)."),
  },
  async execute(args, context) {
    const state = readState(context.worktree, args.slug);
    if (state.replan_count >= MAX_ITERATIONS) {
      return {
        title: "loop_record_replan - cap reached",
        output: `iteration=${state.replan_count} max=${MAX_ITERATIONS} may_replan=false (cap enforced; not incremented)`,
        metadata: {
          iteration: state.replan_count,
          max: MAX_ITERATIONS,
          may_replan: false,
        },
      };
    }
    state.replan_count += 1;
    state.history.push({
      type: "replan",
      at: new Date().toISOString(),
      iteration: state.replan_count,
    });
    writeState(context.worktree, args.slug, state);
    const may_replan = state.replan_count < MAX_ITERATIONS;
    return {
      title: "loop_record_replan",
      output: `iteration=${state.replan_count} max=${MAX_ITERATIONS} may_replan=${may_replan}`,
      metadata: {
        iteration: state.replan_count,
        max: MAX_ITERATIONS,
        may_replan,
      },
    };
  },
});

export const record_verify = tool({
  description:
    "Record the result of the latest verify step (pass|fail) for the plan-slug, with the command that was run. " +
    "Pass sweep_commit_sha ONLY when this record represents an actual diff-scoped test-sweep completion " +
    "(not a bare phase-Verify record) - on a 'pass' it advances the sweep checkpoint used to scope future " +
    "sweeps' diffs; omitting it leaves any previously recorded checkpoint untouched (never cleared).",
  args: {
    slug: tool.schema.string(),
    result: tool.schema.enum(["pass", "fail"]),
    command: tool.schema.string(),
    sweep_commit_sha: tool.schema.string().optional(),
  },
  async execute(args, context) {
    const state = readState(context.worktree, args.slug);
    state.last_verify = { result: args.result, command: args.command };
    if (args.sweep_commit_sha && args.result === "pass") {
      state.last_sweep_commit_sha = args.sweep_commit_sha;
    }
    state.history.push({
      type: "verify",
      at: new Date().toISOString(),
      result: args.result,
      command: args.command,
      ...(args.sweep_commit_sha
        ? { sweep_commit_sha: args.sweep_commit_sha }
        : {}),
    });
    writeState(context.worktree, args.slug, state);
    return {
      title: "loop_record_verify",
      output: `recorded last_verify=${args.result} for slug=${args.slug}${
        state.last_sweep_commit_sha
          ? ` last_sweep_commit_sha=${state.last_sweep_commit_sha}`
          : ""
      }`,
      metadata: {
        slug: args.slug,
        last_verify: state.last_verify,
        last_sweep_commit_sha: state.last_sweep_commit_sha,
      },
    };
  },
});

export const gate_check = tool({
  description:
    "Read-only ship gate: may_ship requires replan_count<=3 AND last_verify.result==='pass'. Does not mutate state. " +
    "Also returns last_sweep_commit_sha - the commit a diff-scoped test sweep last passed at (null if none yet) - " +
    "so callers can scope the next sweep's diff from that commit instead of <base>.",
  args: {
    slug: tool.schema.string(),
  },
  async execute(args, context) {
    const { may_ship, replan_count, last_verify } = evaluateGate(
      context.worktree,
      args.slug,
    );
    const last_sweep_commit_sha = lastSweepCommitSha(
      context.worktree,
      args.slug,
    );
    return {
      title: "loop_gate_check",
      output: `may_ship=${may_ship} replan_count=${replan_count} last_verify=${
        last_verify ? last_verify.result : "none"
      } last_sweep_commit_sha=${last_sweep_commit_sha ?? "none"}`,
      metadata: {
        may_ship,
        replan_count,
        last_verify,
        last_sweep_commit_sha,
      },
    };
  },
});
