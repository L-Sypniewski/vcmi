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

- `origin/develop` = fast-forward mirror of `upstream/develop`. Never commit
  to it directly; sync via `git push origin upstream/develop:develop`.
- Feature branches (`ship/*` or `lukasz-*`) live on the fork and PR into fork
  `develop`. **No PRs/issues/comments on upstream** (repo policy + owner
  preference; upstream `AGENTS.md` GitHub Contribution Policy).
- Main checkout `/Users/lukasz/Documents/developer/vcmi` stays on
  `lukasz-experiment` (this agent/infra branch: `.opencode/`, `.devcontainer/`).
  Feature work goes in sibling worktrees `../vcmi-<branch-slug>` — this matches
  the devcontainer's per-worktree volume design.

## 2. Standard feature flow

1. Sync the mirror: `git fetch upstream && git push origin upstream/develop:develop`.
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
# borrow the definition from lukasz-experiment (UNTRACKED — never commit):
for f in README.md devcontainer.json devcontainer-lock.json fetch-h3-data.sh \
         init-volume.sh set-git-identity.sh; do
  git -C ~/Documents/developer/vcmi show lukasz-experiment:.devcontainer/$f \
    > .devcontainer/$f
done
devcontainer up --workspace-folder .
```

Mechanics (from `.devcontainer/devcontainer.json` on `lukasz-experiment`):

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
devcontainer exec --workspace-folder <worktree-abs-path> bash    # interactive
devcontainer exec --workspace-folder <worktree-abs-path> bash -lc \
  'cmake --build --preset linux-gcc-test'                        # build
devcontainer exec --workspace-folder <worktree-abs-path> bash -lc \
  'cd out/build/linux-gcc-test/bin && ./vcmitest'                # full suite
```

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
```

**Play, isolated from the official installation** (VCMI hardcodes user data to
`$HOME/Library/Application Support/vcmi` — `lib/VCMIDirs.cpp` `VCMIDirsOSX`;
never launch a dev build without the `HOME` override):

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

Everything the fork workflow adds lives in five places (plus one git pin):

```sh
# container side (~5+ GB in the colima VM)
docker rm -f <container>
docker volume rm vcmi-vcmi-<slug> ccache-volume h3-data-volume
docker image rm vsc-vcmi-<slug>-*-features dev_container_feature_content_temp
colima stop && colima start --cpu 2 --memory 2   # restore VM size (or leave)

# worktree (source + out/ + conan-macos/)
git -C ~/Documents/developer/vcmi worktree remove --force ../vcmi-<slug>

# host user-space (~2–4 GB)
rm -rf ~/.local/vcmi-buildenv ~/.conan2 ~/vcmi-scratch

# restore main-checkout submodule pin after merge work there
git -C ~/Documents/developer/vcmi submodule update dependencies

# optional: local branch
git -C ~/Documents/developer/vcmi branch -D <branch>
```

Never touched: `/opt/homebrew`, `/usr/local`, `/Applications` (official
`VCMI.app` and its `~/Library/Application Support/vcmi` data), Xcode CLT,
Python, colima binary itself. colima was pre-existing — stop/resize only; do
not `colima delete` if the VM is used for anything else.

## 6. Agent etiquette

- Delegate verbose loops (sweeps, long builds) to subagents; workers must use
  long-timeout **foreground** waits, not background+end-of-turn.
- Orphaned host processes (a subagent session ending while its build runs)
  survive — verify with `ps`, park a `while kill -0 <pid>` watcher, and
  validate results after.
- Never commit `.devcontainer/`, `.env`, `opencode-auth*.json`, or build
  output. Check `git status --porcelain` before every commit in volume clones.
- Submodule pins move during merges between branches — a dirty `dependencies`
  in the main checkout after switching branches is expected;
  `git submodule update dependencies` restores it.
