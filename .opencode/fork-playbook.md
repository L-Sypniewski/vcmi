# VCMI Fork Playbook

Operational playbook for the **L-Sypniewski/vcmi** fork (`origin`), which
tracks **vcmi/vcmi** (`upstream`, fetch-only). Everything here was verified on
this machine (Apple Silicon macOS, Xcode CLT, colima). Companion to
[`.opencode/fork-workflow.md`](.opencode/fork-workflow.md) (auto-loaded rules).

## 1. Layout and policy

| Remote | Repo | Use |
| --- | --- | --- |
| `origin` | `L-Sypniewski/vcmi` | all pushes; fork-internal PRs (`feature → develop`) |
| `upstream` | `vcmi/vcmi` | fetch-only mirror source |

- `origin/develop` = upstream `develop` **plus merged fork features**, kept
  current via merge-based sync (it stopped being a pure fast-forward mirror
  when PR #1 merged, 2026-10-19):
  ```sh
  git fetch upstream
  git checkout develop            # local branch tracking origin/develop
  git merge upstream/develop      # resolve conflicts if any
  git push origin develop
  ```
  If the sync resolved conflicts in code, run the green sweep (§3) before
  pushing. Changes reach `develop` via PR merges or these sync merges — no
  direct commits. Branch from `upstream/develop` for a pristine upstream base.
- Feature branches (`ship/*` or `lukasz-*`) live on the fork and PR into fork
  `develop`. **No PRs/issues/comments on upstream** (repo policy + owner
  preference; upstream `AGENTS.md` GitHub Contribution Policy). History: the
  battle-telnet-mirror work was once PRed upstream (#7924) and closed — the
  fork-only policy is deliberate; do not resubmit upstream. The open fork PR
  is `L-Sypniewski/vcmi#1` (`ship/battle-telnet-mirror` → fork `develop`).
- Main checkout `/Users/lukasz/Documents/developer/vcmi` stays on `develop`
  (carries the agent infra via PR #2: `.opencode/`, `.devcontainer/`).
  Feature work goes in sibling worktrees `../vcmi-<branch-slug>` — this matches
  the devcontainer's per-worktree volume design.

## 2. Standard feature flow

1. Sync `develop`: fetch upstream and merge per §1; if the merge resolved
   conflicts in code, sweep green (§3) before pushing.
2. Branch from `origin/develop`; create worktree:
   `git worktree add ../vcmi-<slug> <branch>`.
3. Merge current develop into the branch when it drifts; push the branch to
   the fork (required before container bring-up).
4. Sweep in the devcontainer until green (§3).
5. Host-native build only when the change is meant to be played (§4).
6. Fork PR updates automatically when its head branch is pushed.

## 3. Devcontainer lane — build + test (no GUI)

**Bring-up** (first run ~2 h, later ~1 min):

```sh
colima start --cpu 4 --memory 8        # container hard requirement; profile default is 2/2
cd ../vcmi-<slug>
# Branches cut from current develop carry .devcontainer/ natively (PR #2).
# Only branches predating that merge (or cut from upstream) need to borrow it
# untracked from the main checkout (on develop):
for f in README.md devcontainer.json devcontainer-lock.json fetch-h3-data.sh \
         init-volume.sh set-git-identity.sh; do
  git -C ~/Documents/developer/vcmi show origin/develop:.devcontainer/$f \
    > .devcontainer/$f
done
devcontainer up --workspace-folder .
```

Mechanics (from `.devcontainer/devcontainer.json` on `develop`):

- Workspace is a **named volume** `vcmi-<worktree-folder-basename>`, seeded
  **once** by cloning the checked-out branch from the fork — push first, and
  in-container edits are invisible to the host until committed+pushed.
- Persistent volumes: `ccache-volume` (`CCACHE_DIR=/mnt/ccache`),
  `h3-data-volume` (H3 test data → symlinked to `~/.local/share/vcmi`).
- postCreate soft-fails the H3 fetch and git-identity scripts (they're
  untracked on the host and absent from the seeded clone) — after first
  bring-up run, inside the container: `bash .devcontainer/fetch-h3-data.sh`
  and `bash .devcontainer/set-git-identity.sh` (or set identity manually).

**Enter and use** (never bare `docker exec` — it runs as root and tests fail
with `DATA/LCDESC not found` because the H3 symlink is per-user):

```sh
# interactive — either of:
devcontainer exec --workspace-folder <worktree-abs-path> bash
docker exec -it -u vscode -w /workspace <container> bash
# container names are random (e.g. "infallible_hamilton") — find with docker ps;
# the image is vsc-vcmi-<slug>-...-features
# VS Code also works: open the WORKTREE folder (not the main checkout) →
# "Reopen in Container"; after colima stop/start, devcontainer up reattaches (~1 min)

devcontainer exec --workspace-folder <worktree-abs-path> bash -lc \
  'cmake --build --preset linux-gcc-test'                        # build
devcontainer exec --workspace-folder <worktree-abs-path> bash -lc \
  'cd out/build/linux-gcc-test/bin && ./vcmitest'                # full suite
devcontainer exec --workspace-folder <worktree-abs-path> bash -lc \
  'cd out/build/linux-gcc-test/bin && ./vcmitest --gtest_filter="BattleMirror*"'
                                                                # targeted suites
```

**Edit loop**: the container workspace is its own clone — VS Code remote
edits land directly in it; host-side edits must relay through the fork
(host `git push` → in-container `git pull`). In-container commits and pushes
work (origin = fork, gh token forwarded via the env-file, identity set by
`set-git-identity.sh`).

**GUI does not run in the container** — no display, and X11 forwarding would
need XQuartz installed on the host (defeats the no-host-pollution rule). Use
the host-native lane (§4) whenever a change must be *played*, the container
for build + tests.

Baselines and known issues (as of the `5881a6f93` merge, 2026-10-19):

- Configure: `cmake --preset linux-gcc-test -DENABLE_MMAI=OFF` (Ubuntu 24.04
  has no onnxruntime; MMAI off is the container baseline).
- Suite baseline: **1221 passed / 0 failed / 2 disabled** via
  `out/build/linux-gcc-test/bin/vcmitest` (direct binary, not ctest).
- `vcmilobby` fails `-Werror=type-limits` on aarch64 gcc13 — **upstream-own**
  (`lobby/LobbyServer.cpp:51`, plain `char` is unsigned on arm64); do not fix
  in feature branches.
- OOM under the 8 GB cap on heavy TUs → rebuild with `-- -j2`.

## 4. Host-native lane — build to play

**User-space only**: no brew, no sudo, nothing outside `$HOME` + the worktree.
Footprint: `~/.local/vcmi-buildenv` (venv), `~/.conan2` (deps), build dir in
the worktree, `~/vcmi-scratch` (play data).

One-time setup (CLT ≥16 already present; venv provides cmake/ninja/conan):

```sh
python3 -m venv ~/.local/vcmi-buildenv
~/.local/vcmi-buildenv/bin/pip install conan cmake ninja
export PATH=$HOME/.local/vcmi-buildenv/bin:$PATH
cd ../vcmi-<slug> && git submodule update --init --recursive
conan profile detect
# IMPORTANT: use the CI-pinned PRERELEASE deps (stable 1.7.5 lacks luajit).
# CI/install_conan_dependencies.sh names the exact release:
gh release download -R vcmi/vcmi-dependencies --prerelease \
  -p 'dependencies-mac-arm.txz' -D /tmp && conan cache restore /tmp/dependencies-mac-arm.txz
conan install . --output-folder=conan-macos --build=never \
  --profile=dependencies/conan_profiles/macos-arm \
  --profile=dependencies/conan_profiles/base/apple-system \
  -s "&:build_type=RelWithDebInfo"
cmake -S . -B out/build/macos-dev -G Ninja \
  --toolchain conan-macos/conan_toolchain.cmake -D CMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build out/build/macos-dev -- -j$(sysctl -n hw.ncpu)   # first ~15-30 min
# Host build keeps MMAI ENABLED (onnxruntime resolves from the Conan prebuilts;
# only the container needs -DENABLE_MMAI=OFF). Smoke check without GUI:
HOME=/tmp/vcmi-smoke out/build/macos-dev/bin/vcmiserver --help && rm -rf /tmp/vcmi-smoke
```

**Play, isolated from the official installation** (VCMI hardcodes user data to
`$HOME/Library/Application Support/vcmi` — `lib/VCMIDirs.cpp` `VCMIDirsOSX`;
never launch a dev build without the `HOME` override). `bin/` is
self-contained: the build stages `config/` and `Mods/` next to the binaries,
and VCMI's development mode (`lib/VCMIDirs.cpp` `developmentMode()`) resolves
game data relative to the CWD when both are present:

```sh
cd ../vcmi-<slug>/out/build/macos-dev/bin
ln -sfn "/Applications/VCMI.app/Contents/Resources/Data" Data   # real H3 data, read-only
mkdir -p ~/vcmi-scratch
HOME=~/vcmi-scratch ./vcmiclient        # or vcmilauncher / vcmieditor
```

Feature settings (e.g. battle telnet mirror) go in the scratch tree:
`~/vcmi-scratch/Library/Application Support/vcmi/…/settings.json`. Mirror:
`"server" : { "battleMirror" : { "enabled" : true } }`, then `nc 127.0.0.1 3033`.

Iterating: edit in the worktree → `cmake --build out/build/macos-dev` →
relaunch. Incremental rebuilds are minutes.

## 5. Host cleanup map

Everything the fork workflow adds lives in **five self-contained locations**
(plus one reversible side-effect in the main checkout). Full cleanup when done
experimenting reclaims ~10–15 GB:

| # | Location | Contents | Approx. size |
| --- | --- | --- | --- |
| 1 | Docker (inside colima VM) | dev container, `vcmi-vcmi-<slug>` workspace volume, `ccache-volume`, `h3-data-volume` (1.2 GB), `-features` images | ~5+ GB |
| 2 | Worktree `../vcmi-<slug>` | source clone, `out/build/*`, `conan-macos/`, untracked `.devcontainer/` copies | several GB |
| 3 | `~/.local/vcmi-buildenv/` | Python venv (conan, cmake, ninja) | ~0.5 GB |
| 4 | `~/.conan2/` | Conan dependency binaries cache | ~0.5–2 GB |
| 5 | `~/vcmi-scratch/` | isolated user data (settings, saves, mods) for playing | grows with use |

```sh
# 1. container side
docker rm -f <container>                       # e.g. infallible_hamilton
docker volume rm vcmi-vcmi-<slug> ccache-volume h3-data-volume
docker image rm vsc-vcmi-<slug>-*-features dev_container_feature_content_temp
colima stop
colima start --cpu 2 --memory 2               # restore original VM size (or leave at 4/8)

# 2. worktree — removes the build output and the borrowed .devcontainer copies
git -C ~/Documents/developer/vcmi worktree remove --force ../vcmi-<slug>

# 3–5. host user-space bits
rm -rf ~/.local/vcmi-buildenv ~/.conan2 ~/vcmi-scratch

# side-effect in the main checkout: after merge work, the `dependencies`
# submodule pin sits at the other branch's commit (`git status` shows
# "M dependencies") — restore with:
git -C ~/Documents/developer/vcmi submodule update dependencies

# optional: drop the local branch — the work itself stays on the fork remote
git -C ~/Documents/developer/vcmi branch -D <branch>
```

Cautions:

- `colima delete -f` is the bigger hammer — it wipes the whole VM including
  base images. Acceptable only if the VM is dedicated to this workflow (it
  was: nothing but `hello-world`/`alpine` ever ran in it); the per-item
  removal above is the precise path.
- **Don't clean up mid-experiment**: the Conan cache, the ccache volume, and
  the H3 data are exactly what turn hour-long cold builds and bring-ups into
  minutes.
- The result is a host indistinguishable from before — apart from git history
  on the fork, which is the point.

Never touched by this workflow (verify with `df`/`brew list` before/after if
in doubt): `/opt/homebrew`, `/usr/local`, `/Applications` (the official
`VCMI.app` and its data at `~/Library/Application Support/vcmi`), Xcode CLT,
system Python, and the colima installation itself (stop/resize only — it
pre-dates this workflow).

## 6. Agent etiquette

- Delegate verbose loops (sweeps, long builds) to subagents; workers must use
  long-timeout **foreground** waits, not background+end-of-turn.
- Orphaned host processes (a subagent session ending while its build runs)
  survive — verify with `ps`, park a `while kill -0 <pid>` watcher, and
  validate results after.
- Never commit `.env`, `opencode-auth*.json`, or build output. Check
  `git status --porcelain` before every commit in volume clones.
- Submodule pins move during merges between branches — a dirty `dependencies`
  in the main checkout after switching branches is expected;
  `git submodule update dependencies` restores it.
- **The fork docs live on `develop`** (the main checkout): edit
  `.opencode/fork-workflow.md` + `.opencode/fork-playbook.md` (and the
  `AGENTS.md` fork section) there, commit, push — after `git fetch origin`,
  make sure the branch matches `origin/develop` first (stale local branch or
  stale remote-tracking refs after a remote merge base the commit on
  outdated history and the push gets rejected). Only ever commit these doc
  paths, never build output, `.env`, or credential files.
