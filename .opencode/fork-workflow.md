# Fork Workflow (auto-loaded)

This checkout is the **L-Sypniewski/vcmi** fork of vcmi/vcmi. Read
[`.opencode/fork-playbook.md`](.opencode/fork-playbook.md) for the full
playbook (build lanes, commands, cleanup map). Core rules:

1. **Never write to upstream.** No pushes to `vcmi/vcmi`, no PRs, issues, or
   comments there — fork-internal PRs only (feature branch → fork `develop`).
   `origin` = the fork; `upstream` = fetch-only.
2. **`origin/develop` is a fast-forward mirror of upstream `develop`.** Sync =
   `git fetch upstream && git push origin upstream/develop:develop`.
3. **The main checkout stays on `lukasz-experiment`** (agent/infra branch).
   Feature work happens in sibling worktrees: `../vcmi-<branch-slug>`.
4. **Push the branch to the fork BEFORE devcontainer bring-up** — the container
   seeds its workspace volume by cloning the branch from the fork.
5. **Two build lanes, both host-pollution-free:**
   - **Devcontainer** (build + test, no GUI): `devcontainer exec
     --workspace-folder <worktree>` — never bare `docker exec` (runs as root,
     breaks H3 data resolution). Test = `bin/vcmitest`.
   - **Host-native** (play lane): venv `~/.local/vcmi-buildenv`, Conan deps in
     `~/.conan2`, build in `<worktree>/out/build/macos-dev`. **Always launch
     game binaries with `HOME=~/vcmi-scratch`** — VCMI hardcodes user data to
     `$HOME/Library/Application Support/vcmi`.
6. **Done = green sweep** (full build + full unit suite in the container)
   before declaring work finished or updating a fork PR.
7. **Never commit** `.devcontainer/`, `.env`, or credential files — the
   devcontainer definition is borrowed untracked from `lukasz-experiment`.
8. **Consult the cleanup map** in the playbook before creating new host or
   Docker artifacts; reuse existing volumes, venv, and caches.
