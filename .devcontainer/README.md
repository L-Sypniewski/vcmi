# Dev Container

A per-worktree build/test sandbox with a **hard memory cap** (8 GB cgroup), so a
runaway compile/test run gets OOM-killed inside the container and the host VS
Code + browser stay alive. Open the **worktree folder** in VS Code, not the main
checkout.

## Prerequisites

- **Docker on the host** - on macOS this repo's setup uses colima
  (`colima start` before opening the container).
- **gh CLI authenticated on host** - `gh auth status` must succeed on the host.
  The container auto-forwards the host gh token (via `gh auth token`) as
  `GH_TOKEN`/`GITHUB_TOKEN`, so gh CLI works without manual login inside the
  container. `git push`/`fetch`/`pull` over HTTPS also work non-interactively:
  `set-git-identity.sh` runs `gh auth setup-git` on every container start (an
  already-running container needs a one-time manual `gh auth setup-git` -
  `postStartCommand` fires only on start).
- **opencode authenticated on host** - `opencode auth login` must have been run
  on the host. The container auto-forwards the host's `auth.json` (model
  provider credential) via a bind mount; MCP OAuth tokens (`mcp-auth.json`)
  ride along the same way (no project MCPs configured today - forwarded for
  when one lands).
- **(optional) Claude Code token on host** - see "Claude Code setup" below; a
  missing token only WARNs at container start (claude stays unauthenticated,
  everything else works).

## Claude Code setup (one-time)

Claude Code authenticates from a token minted once on the host; from then on
it is auto-forwarded as `CLAUDE_CODE_OAUTH_TOKEN` into every container start
via the env staging pipeline. It reuses the SAME token file as the Alpio
devcontainer - if you already minted one there, you are done.

In a **host terminal** (not inside the container), once:

```bash
# 1. Mint the token (browser OAuth; prints a ~1-year token). The command
#    saves nothing - copy the bare token string (first line, no prefixes).
claude setup-token

# 2. Store it - the file must contain ONLY the token, on a single line:
mkdir -p ~/.config/alpio-devcontainer
echo "<token>" > ~/.config/alpio-devcontainer/claude-token
chmod 600 ~/.config/alpio-devcontainer/claude-token

# 3. Secret-safe sanity check (never prints the token):
test -s ~/.config/alpio-devcontainer/claude-token && echo "token file ok"
```

The env staging file is re-read on every container start, so a fresh token
reaches even a re-attached container; only the FIRST provisioning of the
claude-code feature needs a **Rebuild Container** (features bake into the
image). The token supports model requests only. Regenerate roughly yearly.

Verify in the **container terminal**:

```bash
printenv CLAUDE_CODE_OAUTH_TOKEN >/dev/null && echo "token forwarded"  # never prints the value
claude --version
```

## Quick start

```bash
# 1. In VS Code: File → Open Folder → <this worktree>  (NOT the main checkout)
# 2. Command Palette → "Dev Containers: Reopen in Container"
#    (first start clones the branch into a named volume + apt-installs the
#     full C++ toolchain + fetches H3 test data - expect ~5-10 min; later
#     starts are fast)
# 3. From the container terminal:
cmake --preset linux-gcc-test -DENABLE_MMAI=OFF   # configure (run once; postCreate warm-configures it)
CMAKE_BUILD_PARALLEL_LEVEL=2 cmake --build --preset linux-gcc-test   # build; see memory note below
cd out/build/linux-gcc-test/bin
timeout 1800 ./vcmitest                          # full unit suite (ONE process; exit 124 = hang)
timeout 300 ./vcmitest --gtest_filter='Suite*'   # filtered
```

(`timeout` is GNU coreutils - in the base image on Linux; on the macOS host
it comes from `brew install coreutils`. On the macOS host build one suite -
`Nullkiller2_Behaviors_GatherArmyBehavior.upgradesPikemenCarriedByGarrisonHero`
- deadlocks; exclude it there via
`--gtest_filter=-Nullkiller2_Behaviors_GatherArmyBehavior.*`. Linux runs it
fine in upstream CI.)

**Build parallelism:** the 8 GB cap OOM-kills `cc1plus` at ninja's default
`-j4` on the heaviest translation units - build with
`CMAKE_BUILD_PARALLEL_LEVEL=2` (as above) inside this container.

The container uses a **named Docker volume** (not a bind mount) seeded with a
clone of the current branch from the fork (`L-Sypniewski/vcmi` - override with
`VCMI_REPO=vcmi/vcmi` when seeding a pristine upstream volume). Each worktree
gets its own volume (`vcmi-<folder-name>`), so containers are fully isolated
from each other and from the host (the exception is the host-global ccache
volume - shared by every worktree container of this repo; see "Persistent
cache volumes"). First launch creates the volume and clones the repo; subsequent
launchs find the existing volume and skip the clone.

Host-side file edits do **not** propagate to the container (the volume is
isolated). All editing happens through VS Code's remote connection, which
writes to the container's filesystem. The volume persists across container
restarts, so you don't re-clone on each start.

## What's inside

- **C++ toolchain via apt** - gcc + clang + cmake + ninja + ccache and the full
  vcmi dependency set from `docs/developers/Building_Linux.md` (Ubuntu 24.04):
  SDL2 stack, Qt6 (base/tools/svg), Boost, ffmpeg (libavformat/libswscale),
  TBB, LuaJIT, minizip, squish, fmt, xz, sqlite3. `postCreateCommand` also
  fetches the git submodules (`test/googletest` for vcmitest,
  `vcmi-dependencies`, innoextract, discord-presence) and warm-configures the
  `linux-gcc-test` preset as an end-to-end toolchain validation.
- **gh CLI** (devcontainer feature) + **opencode** (curl-installed,
  self-updating) + **claude** (official devcontainer feature) - all three
  authenticated via the host-forwarded credentials.
- **GLM-5.3 as the default model** - the repo's `.opencode/opencode.json`
  pins `zai-coding-plan/glm-5.3` (reasoning effort `max`) with glm-5.3-flash
  vision-capable, and preselects the `max` variant for the ship/build/plan
  agents; `@ship <goal>` is the default agent (the pipeline entry point).
  The config travels with the branch - `git pull` inside a persisted
  workspace volume to pick up changes to it.
- **ripgrep** - for agent code search.
- **NOT included (deliberately)**: onnxruntime (Ubuntu 24.04 apt lacks it - the
  experimental MMAI combat AI stays off; see
  `docs/developers/Building_Linux.md` if you need it), Docker-in-Docker (no
  Testcontainers-style tests here), mise (no runtime pins - the toolchain comes
  from apt like upstream CI).
- **opencode `--auto` mode** - `opencode` runs with auto-approve (all
  permission prompts skipped except explicit `deny` rules like force-push).
  Safe because the container is isolated - filesystem damage is contained to
  the named volume, and the 8 GB memory cap prevents host impact.
- **ship pipeline** - `.opencode/` travels with the branch, so `@ship <goal>`
  works inside the container (its build+test sweep uses the `linux-gcc-test`
  preset there - the agents say "the platform's `*-test` preset").

## Persistent cache volumes

| Store  | Path                        | Scope                                 | Reset                            |
| ------ | --------------------------- | ------------------------------------- | -------------------------------- |
| ccache | `/mnt/ccache` (`ccache-volume`) | host-global, all containers of this repo | `docker volume rm ccache-volume` |
| H3 test data | `/mnt/h3-data/vcmi` (`h3-data-volume`), symlinked to `~/.local/share/vcmi` | host-global, all containers of this repo | `docker volume rm h3-data-volume` |

The unit tests resolve REAL Heroes 3 resources (`DATA/LCDESC.TXT` etc.) - the
same artifact upstream CI uses (`vcmi-mods/vcmi-test-data` heroes3.7z, see
`.github/workflows/github.yml` "Prepare Heroes 3 data") is fetched once onto the
persistent `h3-data` volume; rebuilds reuse it.

ccache hits survive container rebuilds (`CCACHE_COMPILERCHECK=content` keeps
the cache valid across toolchain upgrades). The ccache hit rate is what makes
rebuilds cheap - a cold full build is ~15-30 min, a warm one a few minutes.

## Memory and CPU caps

The container has a **hard 8 GB** cgroup cap (`runArgs: ["--memory=8gb"]` in
`devcontainer.json`). The `hostRequirements` block is a VS Code warning-only
gate, not the runtime cap. If the container OOM-kills during heavy parallel
links (Qt client + tests at once), that's the isolation working as designed -
bump to 12 GB if it becomes disruptive.

CPU, by contrast, is capped only proportionally: `runArgs:
["--cpu-shares=512"]` is a soft work-conserving weight, not a reservation.
When CPU is plentiful the container uses all cores; only under contention does
the weight arbitrate. After a rebuild, run `cat /sys/fs/cgroup/cpu.weight`
inside the container to see the translated value - expect 59 on modern runc
(>= 1.2), 20 on legacy (<= 1.1); same proportional semantics either way.

## Notes

- **Reset everything** - `docker volume rm vcmi-<folder-name>` (workspace) and
  optionally `docker volume rm ccache-volume` (compile cache), then rebuild.
- **Branch switching inside the container** - the volume is a normal git clone:
  `git fetch origin develop && git checkout -b <branch> origin/develop` works
  in the container terminal. Pushes go to the fork via the forwarded gh
  credential.
- **Windows/Linux hosts** - the devcontainer itself is host-agnostic (the
  helper container is arch-pinned automatically); only the colima note above
  is macOS-specific.
