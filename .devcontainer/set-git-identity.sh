#!/usr/bin/env bash
set -euo pipefail

# Idempotent per-start git setup: wires gh as the HTTPS credential helper (agent shells have no TTY, so git's username prompt can never succeed - GH_TOKEN must be supplied by helper), then fills identity if missing.

# Agent shells run under a PTY where git's pager would block forever. Precedence is
# $GIT_PAGER > core.pager > $PAGER, so this pin covers only shells that unset the env (the plugin's env-config injection outranks it - pager-guard.ts).
git config --global core.pager cat

command -v gh >/dev/null 2>&1 || exit 0
gh auth status >/dev/null 2>&1 || exit 0

gh auth setup-git >/dev/null 2>&1 || true

# Identity: skip if already set (a prior run of this script, or the user's own `git config` in the container). Fills the gap where the container starts identity-less, so commits aren't authored by a fabricated fallback.
if [ -n "$(git config user.name)" ] && [ -n "$(git config user.email)" ]; then
  exit 0
fi

name="$(gh api user --jq '.name // .login')"
email="$(gh api user --jq '.email // ""')"
if [ -z "$email" ]; then
  email="$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
fi

git config --global user.name "$name"
git config --global user.email "$email"
