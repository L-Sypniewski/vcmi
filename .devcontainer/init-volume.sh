#!/usr/bin/env bash
# Runs on the HOST via devcontainer initializeCommand (before container starts).
# Creates a named Docker volume per worktree and seeds it with a clone of the
# current branch. Idempotent - skips if the volume already has content.
set -euo pipefail

# Pin helper-container to host arch: a stale cross-arch cached image (e.g.
# arm64 alpine on an amd64 host) reuses whatever is tagged locally and fails
# with "exec format error" since the host can't exec the foreign binary.
case "$(uname -m)" in
  x86_64)        DCP_ARCH="linux/amd64" ;;
  aarch64|arm64) DCP_ARCH="linux/arm64" ;;
  *)             DCP_ARCH="linux/amd64" ;;
esac

# --- Generate .env from host shell profile ---
# VS Code launched from desktop doesn't inherit .zshrc env vars.
# Source the shell profile here and write a Docker --env-file that runArgs picks up.
DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$DEVCONTAINER_DIR/.env"
ENV_TMP="$(mktemp)"
CLAUDE_TOKEN_FILE="$HOME/.config/devcontainer/claude-token"

# gh's token lives in the OS keyring (libsecret); VS Code's initializeCommand
# subprocess often lacks DBUS_SESSION_BUS_ADDRESS, so point it at the user bus.
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "/run/user/$(id -u)/bus" ]]; then
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
  export DBUS_SESSION_BUS_ADDRESS
fi

# Every {env:VAR} referenced by the project opencode.jsonc rides from the host
# profile when set, so project MCPs authenticate identically without a hardcoded
# per-var allowlist. GH/CLAUDE tokens are emitted explicitly below and excluded
# here to avoid duplicate lines. Host-global MCP definitions are deliberately
# NOT forwarded - the container sees only project-configured MCP servers.
MCP_ENV_REFS="$(grep -ohE '\{env:[A-Za-z_][A-Za-z0-9_]*\}' \
  "$DEVCONTAINER_DIR/../opencode.jsonc" 2>/dev/null \
  | sed -E 's/^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/\1/' | sort -u \
  | grep -vxE 'GH_TOKEN|GITHUB_TOKEN|CLAUDE_CODE_OAUTH_TOKEN' || true)"

# Names of host credentials that failed to forward; drives the warning summary
# near the end of this script and the in-container shell banner.
MISSING_CREDENTIALS=""

{
  if command -v zsh >/dev/null 2>&1 && [[ -f "$HOME/.zshrc" ]]; then
    # shellcheck disable=SC2086 # word-split intended: names match [A-Za-z_][A-Za-z0-9_]*
    zsh -c 'source ~/.zshrc 2>/dev/null; for v in "$@"; do val="${(P)v}"; [[ -n "$val" ]] && printf "%s=%s\n" "$v" "$val"; done' _ $MCP_ENV_REFS 2>/dev/null || true
  elif [[ -f "$HOME/.bashrc" ]]; then
    # shellcheck disable=SC2086 # word-split intended: names match [A-Za-z_][A-Za-z0-9_]*
    bash -c 'source ~/.bashrc 2>/dev/null; for v in "$@"; do eval "val=\${$v:-}"; [[ -n "$val" ]] && printf "%s=%s\n" "$v" "$val"; done' _ $MCP_ENV_REFS 2>/dev/null || true
  fi
  # gh CLI: extract token from host keyring (inaccessible inside container).
  # GH_TOKEN authenticates gh CLI; GITHUB_TOKEN authenticates the opencode gh-* MCP servers.
  GH_TOKEN_VAL="$(gh auth token 2>/dev/null || echo '')"
  echo "GH_TOKEN=$GH_TOKEN_VAL"
  echo "GITHUB_TOKEN=$GH_TOKEN_VAL"
  # Scoped GitHub Packages auth for opencode's plugin installs (the
  # container's post-start writes it into the user-level ~/.npmrc).
  echo "NODE_AUTH_TOKEN=$GH_TOKEN_VAL"
  # opencode v2's zai-coding-plan catalog provider reads the ZAI_API_KEY env
  # name at client creation inside its service process; the profile spells it
  # Z_AI_API_KEY (forwarded for the {env:} MCP refs above), so alias it here
  # to satisfy both spellings. Probed from the profile shell, not this
  # script's env.
  ZAI_VAL="$(zsh -c 'source ~/.zshrc 2>/dev/null; echo "${Z_AI_API_KEY:-}"' 2>/dev/null || true)"
  if [[ -n "$ZAI_VAL" ]]; then
    echo "ZAI_API_KEY=$ZAI_VAL"
  fi
  # One-year claude setup-token, forwarded like GH_TOKEN above; a missing
  # or blank file means the container runs without claude auth.
  CLAUDE_TOKEN_VAL=""
  if [[ -s "$CLAUDE_TOKEN_FILE" ]]; then
    CLAUDE_TOKEN_VAL="$(head -n1 "$CLAUDE_TOKEN_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
  fi
  if [[ -n "$CLAUDE_TOKEN_VAL" ]]; then
    echo "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_TOKEN_VAL"
  else
    echo "[devcontainer] WARN: claude token missing or blank at $CLAUDE_TOKEN_FILE (Claude Code will be unauthenticated in the container)" >&2
    MISSING_CREDENTIALS="${MISSING_CREDENTIALS:+$MISSING_CREDENTIALS,}claude"
  fi
} > "$ENV_TMP"

# Unauthenticated host gh stages an EMPTY token silently (no WARN inside the
# brace group above); the brace group is not a subshell, so GH_TOKEN_VAL
# survives for this check. Track the miss here.
if [[ -z "$GH_TOKEN_VAL" ]]; then
  MISSING_CREDENTIALS="${MISSING_CREDENTIALS:+$MISSING_CREDENTIALS,}gh"
fi

# A present-but-underprivileged gh token would 403 the agent pipeline
# mid-run; unverifiable/offline checks stay WARN, like the tolerance above.
if [[ -n "$GH_TOKEN_VAL" ]]; then
  GH_REQUIRED_SCOPES="repo project read:org read:packages"
  # The probe runs under GNU timeout so a hung call cannot block container
  # start; hosts without the binary (stock macOS) skip it rather than go unbounded.
  if ! command -v timeout >/dev/null 2>&1; then
    echo "[devcontainer] WARN: cannot verify gh token scopes (GNU timeout not on PATH - stock macOS lacks it; install coreutils so 'timeout' resolves) - required: ${GH_REQUIRED_SCOPES// /, }" >&2
  else
    GH_SCOPES_STATUS=0
    GH_SCOPES_ERR_FILE="$(mktemp)"
    GH_SCOPES_OUTPUT="$(GH_TOKEN="$GH_TOKEN_VAL" timeout 15 gh api -i user 2>"$GH_SCOPES_ERR_FILE")" || GH_SCOPES_STATUS=$?
    GH_SCOPES_ERR="$(cat "$GH_SCOPES_ERR_FILE" 2>/dev/null || true)"
    rm -f "$GH_SCOPES_ERR_FILE"
    # Line-anchored: Access-Control-Expose-Headers names the header earlier.
    GH_SCOPES_HEADER="$(printf '%s\n' "$GH_SCOPES_OUTPUT" | grep -iE '^x-oauth-scopes:' | head -n1 | cut -d: -f2- | tr -d '\r' || true)"
    if [[ "$GH_SCOPES_STATUS" -eq 0 && -n "$GH_SCOPES_HEADER" ]]; then
      GH_GRANTED=" ${GH_SCOPES_HEADER//,/ } "
      GH_MISSING=""
      read -r -a GH_REQUIRED_LIST <<<"$GH_REQUIRED_SCOPES"
      for scope in "${GH_REQUIRED_LIST[@]}"; do
        # The X-Oauth-Scopes header lists only explicitly granted scope strings,
        # so requirements widen for documented implications (project <- its
        # read:/write: variants; write:org => read:org; write:packages =>
        # read:packages) instead of blanket scope aliasing.
        case "$scope" in
          project)
            if [[ "$GH_GRANTED" != *" project "* && "$GH_GRANTED" != *" read:project "* && "$GH_GRANTED" != *" write:project "* ]]; then
              GH_MISSING="${GH_MISSING:+$GH_MISSING,}$scope"
            fi
            ;;
          read:org)
            # write:org implies read:org (GitHub scope model); the X-Oauth-Scopes
            # header lists only granted strings, so an implied read must widen.
            if [[ "$GH_GRANTED" != *" read:org "* && "$GH_GRANTED" != *" write:org "* ]]; then
              GH_MISSING="${GH_MISSING:+$GH_MISSING,}$scope"
            fi
          ;;
          read:packages)
            # write:packages implies read:packages (same implication rule).
            if [[ "$GH_GRANTED" != *" read:packages "* && "$GH_GRANTED" != *" write:packages "* ]]; then
              GH_MISSING="${GH_MISSING:+$GH_MISSING,}$scope"
            fi
          ;;
          *)
            if [[ "$GH_GRANTED" != *" $scope "* ]]; then
              GH_MISSING="${GH_MISSING:+$GH_MISSING,}$scope"
            fi
            ;;
        esac
      done
      if [[ -n "$GH_MISSING" ]]; then
        echo "[devcontainer] ERROR: gh token missing scopes: $GH_MISSING - required for the container's agent pipeline (repos/issues/PRs, Projects board wiring, org project discovery, GitHub Packages installs). Fix: gh auth refresh -h github.com -s $GH_MISSING" >&2
        exit 1
      fi
    elif [[ "$GH_SCOPES_STATUS" -eq 0 ]]; then
      echo "[devcontainer] WARN: cannot verify gh token scopes (no OAuth scopes reported) - required: ${GH_REQUIRED_SCOPES// /, }" >&2
    # stdout carries the status line on current gh; stderr ("gh: ... (HTTP <n>)")
    # is the stable carrier across gh versions, so both surfaces are matched.
    elif printf '%s\n' "$GH_SCOPES_OUTPUT" | grep -Eq '^HTTP.* 401 ' \
      || printf '%s\n' "$GH_SCOPES_ERR" | grep -Eq '\(HTTP 401\)|Bad credentials'; then
      echo "[devcontainer] ERROR: gh token rejected by GitHub (401) - re-authenticate (gh auth login) or refresh the token" >&2
      exit 1
    elif printf '%s\n' "$GH_SCOPES_OUTPUT" | grep -Eq '^HTTP.* 403 ' \
      || printf '%s\n' "$GH_SCOPES_ERR" | grep -Eq '\(HTTP 403\)'; then
      # 403 also covers primary rate-limit exhaustion, so it never blocks the start.
      echo "[devcontainer] WARN: gh token scope check got 403 - either the token is restricted/insufficient (re-authenticate or gh auth refresh) or the API rate limit is exhausted (wait for the reset window; X-RateLimit-Remaining 0) - continuing" >&2
    else
      echo "[devcontainer] WARN: cannot verify gh token scopes (gh api unreachable - offline?) - required: ${GH_REQUIRED_SCOPES// /, }" >&2
    fi
  fi
fi

# Write CONTENT into the existing file (same inode) rather than deleting and
# recreating it: devcontainer.json bind-mounts this path into the container as a
# single file, so an already-running container (VS Code just re-attached, not
# restarted) keeps its mount on whatever inode existed at container-start time.
# Recreating the file here would silently orphan that mount until a real
# stop/start, and the container would keep sourcing the stale values.

# Mode 600 (enforced by the chmod below): this file carries long-lived tokens, so it stays
# owner-only host-side. Per-start container forwarding does NOT rely on bind readability:
# postStartCommand sudo-copies the bind to a vscode-owned 600 file that shells source
# (see devcontainer.json); docker's runArgs --env-file is read host-side by the CLI as
# the file's owner, so it is unaffected.
( umask 077
  if ! cat "$ENV_TMP" 2>/dev/null > "$ENV_FILE"; then
    # Fallback: a previous container run left the file root/in-container-UID owned
    # at mode 600, blocking the write above. Recreating means the fresh values only
    # reach the container on its next real start, not the upcoming re-attach.
    rm -f "$ENV_FILE"
    mv "$ENV_TMP" "$ENV_FILE"
  fi
)
chmod 600 "$ENV_FILE" || echo "[devcontainer] WARN: cannot set mode on env staging file" >&2
rm -f "$ENV_TMP"
echo "[devcontainer] Env vars written to .env"

# --- Copy opencode model-provider auth.json ---
# opencode stores the LLM provider credential (zai-coding-plan) in auth.json under
# XDG_DATA_HOME, which is non-standard on this host. devcontainer.json bind-mounts
# this file into the container so opencode can authenticate the model provider.
AUTH_PATH="$(zsh -c 'source ~/.zshrc 2>/dev/null; echo "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"' 2>/dev/null || echo "$HOME/.local/share/opencode/auth.json")"
AUTH_FILE="$DEVCONTAINER_DIR/opencode-auth.json"
if [[ -f "$AUTH_PATH" ]]; then
  AUTH_CONTENT="$(cat "$AUTH_PATH")"
  AUTH_SOURCE_MSG="[devcontainer] opencode auth.json copied from $AUTH_PATH"
else
  AUTH_CONTENT='{}'
  AUTH_SOURCE_MSG="[devcontainer] WARN: opencode auth.json not found at $AUTH_PATH (model provider auth will be missing)"
  MISSING_CREDENTIALS="${MISSING_CREDENTIALS:+$MISSING_CREDENTIALS,}opencode-auth"
fi
# Write CONTENT into the existing file (same inode), same rationale as the .env
# write above - devcontainer.json bind-mounts this as a single file, so a
# delete+recreate here would orphan an already-running container's mount.
# Mode 644 (umask 022): under rootless Docker the container user maps to a subordinate host uid,
# so only the other-read bit makes host-staged files readable in-container; the env staging file keeps 600 (shells source the sudo-copied file instead).
( umask 022
  if ! printf '%s' "$AUTH_CONTENT" 2>/dev/null > "$AUTH_FILE"; then
    # Fallback: a previous container run left the file root/in-container-UID owned
    # at mode 600, blocking the write above - same recovery as the .env case.
    rm -f "$AUTH_FILE"
    printf '%s' "$AUTH_CONTENT" > "$AUTH_FILE"
    echo "[devcontainer] WARN: refreshed $AUTH_FILE via recreate - a re-attached container keeps the stale bind until a full restart" >&2
  fi
)
chmod 644 "$AUTH_FILE" || echo "[devcontainer] WARN: cannot set mode on auth staging file" >&2
echo "$AUTH_SOURCE_MSG"

# --- Copy opencode MCP OAuth tokens (mcp-auth.json) ---
# opencode keeps MCP-server OAuth tokens (supabase, ...) in mcp-auth.json next to
# auth.json; forwarding it lets container MCPs reuse host-minted OAuth as-is.
MCP_AUTH_PATH="$(dirname "$AUTH_PATH")/mcp-auth.json"
MCP_AUTH_FILE="$DEVCONTAINER_DIR/opencode-mcp-auth.json"
if [[ -f "$MCP_AUTH_PATH" ]]; then
  MCP_AUTH_CONTENT="$(cat "$MCP_AUTH_PATH")"
  MCP_AUTH_MSG="[devcontainer] opencode mcp-auth.json copied from $MCP_AUTH_PATH"
else
  MCP_AUTH_CONTENT='{}'
  MCP_AUTH_MSG="[devcontainer] WARN: opencode mcp-auth.json not found at $MCP_AUTH_PATH (OAuth MCP servers will need re-auth in the container)"
  MISSING_CREDENTIALS="${MISSING_CREDENTIALS:+$MISSING_CREDENTIALS,}opencode-mcp"
fi
# Overwrite in place (same inode), same rationale as the auth write above.
( umask 022
  if ! printf '%s' "$MCP_AUTH_CONTENT" 2>/dev/null > "$MCP_AUTH_FILE"; then
    rm -f "$MCP_AUTH_FILE"
    printf '%s' "$MCP_AUTH_CONTENT" > "$MCP_AUTH_FILE"
    echo "[devcontainer] WARN: refreshed $MCP_AUTH_FILE via recreate - a re-attached container keeps the stale bind until a full restart" >&2
  fi
)
chmod 644 "$MCP_AUTH_FILE" || echo "[devcontainer] WARN: cannot set mode on mcp auth staging file" >&2
echo "$MCP_AUTH_MSG"

# --- Credential-forwarding warning summary ---
# The tally rides the env staging pipeline into the container, where
# shell-banner.sh renders it as a shell-start warning; placed before the
# volume-skip exit below so it also fires on every subsequent start.
printf 'DEVCONTAINER_MISSING_CREDENTIALS=%s\n' "$MISSING_CREDENTIALS" >> "$ENV_FILE" \
  || echo "[devcontainer] WARN: could not append credential tally to env staging file" >&2
if [[ -n "$MISSING_CREDENTIALS" ]]; then
  DEVCONTAINER_MISSING_CREDENTIALS="$MISSING_CREDENTIALS" bash "$DEVCONTAINER_DIR/shell-banner.sh" \
    || echo "[devcontainer] WARN: credential summary failed" >&2
fi

# --- Stage herdr opencode + claude integration (agent visibility) ---
# herdr's host integration (tui.jsonc + session/plugin artifacts in
# ~/.config/opencode) makes container opencode agents visible in herdr's
# sidebar. Bind sources must ALWAYS exist (docker create fails on a missing
# one): hosts without herdr get empty placeholders - tui.jsonc = {} loads
# no plugin. A present-but-broken integration is fatal instead of degraded:
# silently missing agent visibility mid-session is harder to diagnose than
# an actionable failed start. The claude hook is the optional exception:
# claude is not part of the required toolchain, so a missing hook WARNs
# instead of failing the start.
HERDR_OC_DIR="$HOME/.config/opencode"
HERDR_STAGE_DIR="$DEVCONTAINER_DIR/herdr-stage"
HERDR_BRIDGE_DIR="$HOME/.herdr/bridge"
mkdir -p "$HERDR_STAGE_DIR/herdr-opencode" "$HERDR_STAGE_DIR/plugins" "$HERDR_STAGE_DIR/claude"

if [[ -f "$HERDR_OC_DIR/tui.jsonc" ]]; then
  HERDR_INSTALLED=1
else
  HERDR_INSTALLED=""
fi

# Overwrite in place (same inode), same rationale as the auth write above -
# devcontainer.json bind-mounts these as single files, so a delete+recreate
# here would orphan an already-running container's mount.
# Mode 644, like the auth staging above: these artifacts are not secrets and
# must stay readable by opencode inside the container (only the env staging file keeps 600).
herdr_stage_write() {
  # 2>/dev/null precedes > "$1" deliberately: bash applies redirections
  # left-to-right, so only this order masks the failing open.
  if printf '%s' "$2" 2>/dev/null > "$1"; then
    chmod 644 "$1" || echo "[devcontainer] WARN: cannot set mode on herdr staging file $1" >&2
    return 0
  fi
  # Fallback: a prior container run left the file mode-locked, blocking the
  # in-place write. Recreating changes the inode, so a merely re-attached
  # container keeps the stale bind until a full restart.
  if rm -f "$1" 2>/dev/null && printf '%s' "$2" 2>/dev/null > "$1"; then
    chmod 644 "$1" || echo "[devcontainer] WARN: cannot set mode on herdr staging file $1" >&2
    echo "[devcontainer] WARN: refreshed $1 via recreate - a re-attached container keeps the stale bind until a full restart" >&2
    return 0
  fi
  echo "[devcontainer] WARN: could not refresh $1 (stays stale until a start where the write succeeds)" >&2
}

# Missing and empty share a fix (reinstall the integration); unreadability
# is a host permissions problem, so it gets its own message.
HERDR_BROKEN_INSTALL=()
HERDR_UNREADABLE=()
while read -r rel; do
  src="$HERDR_OC_DIR/$rel"
  if [[ -n "$HERDR_INSTALLED" ]]; then
    if [[ ! -f "$src" ]]; then
      HERDR_BROKEN_INSTALL+=("$src")
    elif [[ ! -r "$src" ]]; then
      HERDR_UNREADABLE+=("$src")
    elif [[ ! -s "$src" ]]; then
      HERDR_BROKEN_INSTALL+=("$src")
    fi
    content="$(cat "$src" 2>/dev/null || true)"
  elif [[ "$rel" == "tui.jsonc" ]]; then
    # {} tui.jsonc loads no plugin, so nothing tries to connect.
    content='{}'
  else
    content=""
  fi
  herdr_stage_write "$HERDR_STAGE_DIR/$rel" "$content"
done <<'EOF'
tui.jsonc
herdr-tui-session.js
herdr-opencode/tui.js
plugins/herdr-agent-state.js
EOF

for src in "${HERDR_BROKEN_INSTALL[@]}"; do
  echo "[devcontainer] ERROR: herdr artifact missing or empty: $src - run 'herdr integration install opencode' on the host, then restart the container" >&2
done
for src in "${HERDR_UNREADABLE[@]}"; do
  echo "[devcontainer] ERROR: herdr artifact unreadable: $src - fix host file readability, then restart the container" >&2
done
if [[ "${#HERDR_BROKEN_INSTALL[@]}" -gt 0 || "${#HERDR_UNREADABLE[@]}" -gt 0 ]]; then
  exit 1
fi

# claude is optional (unlike the opencode artifacts above): a missing hook
# degrades to no claude agent visibility, never a failed start.
HERDR_CLAUDE_HOOK="$HOME/.claude/hooks/herdr-agent-state.sh"
HERDR_CLAUDE_CONTENT=""
if [[ -n "$HERDR_INSTALLED" && -s "$HERDR_CLAUDE_HOOK" ]]; then
  HERDR_CLAUDE_CONTENT="$(cat "$HERDR_CLAUDE_HOOK" 2>/dev/null || true)"
fi
if [[ -n "$HERDR_INSTALLED" && -z "$HERDR_CLAUDE_CONTENT" ]]; then
  echo "[devcontainer] WARN: herdr claude hook missing or empty at $HERDR_CLAUDE_HOOK - run 'herdr integration install claude' on the host for claude agent visibility (continuing without it)" >&2
fi
herdr_stage_write "$HERDR_STAGE_DIR/claude/herdr-agent-state.sh" "$HERDR_CLAUDE_CONTENT"

# Optional like the claude hook above (WARN + absent when missing), staged before
# the ref check so every "./..." plugin reference in the staged tui.jsonc resolves:
# an integration update adding a plugin stages automatically; a reference with no
# host file behind it still fails the ref check below (drift guard unchanged).
# `..` refs are left to that check (staging must not read outside the config dir).
while read -r ref; do
  [[ -z "$ref" || "$ref" == *..* ]] && continue
  ref="${ref#./}"
  src="$HERDR_OC_DIR/$ref"
  if [[ -s "$src" ]]; then
    mkdir -p "$HERDR_STAGE_DIR/$(dirname "$ref")"
    herdr_stage_write "$HERDR_STAGE_DIR/$ref" "$(cat "$src")"
  else
    rm -f "$HERDR_STAGE_DIR/$ref"
    echo "[devcontainer] WARN: tui.jsonc references '$ref', missing or empty at $src - not staged (run the toolkit's opencode-global/sync.sh on the host)" >&2
  fi
done < <(sed -n '/"plugin"[[:space:]]*:/,/\]/p' "$HERDR_STAGE_DIR/tui.jsonc" 2>/dev/null \
  | grep -oE '"\./[^"]+"' | tr -d '"' || true)

if [[ -n "$HERDR_INSTALLED" ]]; then
  # A ./ plugin reference with no counterpart in the stage dir means the host
  # integration expects an artifact this staging does not know (version
  # drift); loading it in-container would fail at runtime, so fail the start
  # with the drift fix instead.
  HERDR_UNRESOLVED=""
  while read -r ref; do
    [[ -z "$ref" ]] && continue
    # A .. component escapes the stage dir by definition.
    if [[ "$ref" == *..* || ! -f "$HERDR_STAGE_DIR/${ref#./}" ]]; then
      HERDR_UNRESOLVED="${HERDR_UNRESOLVED:+$HERDR_UNRESOLVED }$ref"
    fi
  done < <(sed -n '/"plugin"[[:space:]]*:/,/\]/p' "$HERDR_STAGE_DIR/tui.jsonc" 2>/dev/null \
    | grep -oE '"\./[^"]+"' | tr -d '"' || true)
  if [[ -n "$HERDR_UNRESOLVED" ]]; then
    echo "[devcontainer] ERROR: staged tui.jsonc references plugin file(s) missing from the stage dir: $HERDR_UNRESOLVED - herdr integration version drift; update herdr on the host and restart the container" >&2
    exit 1
  fi
fi

# Mount source for the socket bridge: the bind needs the dir to exist, and the
# host's herdr-bridge service populates the socket itself (systemd user unit on
# Linux, dev.herdr.bridge LaunchAgent or skill-spawned socat on macOS).
mkdir -p "$HERDR_BRIDGE_DIR"
if [[ -n "$HERDR_INSTALLED" && ! -e "$HERDR_BRIDGE_DIR/herdr.sock" ]]; then
  echo "[devcontainer] ERROR: herdr is active but $HERDR_BRIDGE_DIR/herdr.sock does not exist - Linux: systemctl --user start herdr-bridge; macOS: launchctl kickstart -k gui/\$(id -u)/dev.herdr.bridge (unit and LaunchAgent ship in the herdr-workflow skill; any herdr-workflow launch self-heals the bridge) - then restart the container" >&2
  exit 1
fi

if [[ -n "$HERDR_INSTALLED" ]]; then
  echo "[devcontainer] herdr opencode artifacts staged from $HERDR_OC_DIR"
else
  echo "[devcontainer] herdr not installed (no $HERDR_OC_DIR/tui.jsonc) - staged empty placeholders"
fi
echo "[devcontainer] herdr bridge socket dir ready (the host bridge service populates the socket)"

# --- Stage opencode-global v2 config (cli.json + pr-link package + gh-owner-guard) ---
# Host-gated like herdr: the toolkit's opencode-global sync.sh produces these;
# without it a {} cli.json loads no plugin and no pr-link stages, so the
# container's opencode behavior is unchanged.
OC_GLOBAL_STAGE="$DEVCONTAINER_DIR/opencode-stage"
OC_PRLINK_SRC="$HERDR_OC_DIR/plugins/pr-link"
OC_PRLINK_STAGE="$HERDR_STAGE_DIR/plugins/pr-link"
OC_GLOBAL_MISSING=()
mkdir -p "$OC_GLOBAL_STAGE"
chmod 755 "$OC_GLOBAL_STAGE"
if [[ -s "$HERDR_OC_DIR/cli.json" ]]; then
  if [[ ! -r "$HERDR_OC_DIR/cli.json" ]]; then
    echo "[devcontainer] ERROR: cli.json source unreadable: $HERDR_OC_DIR/cli.json - fix host file readability, then restart the container" >&2
    exit 1
  fi
  # Read failure must bind to an assignment: argument-position $(cat) never trips set -e.
  OC_CLI_CONTENT="$(cat "$HERDR_OC_DIR/cli.json")" || { echo "[devcontainer] ERROR: cli.json source unreadable: $HERDR_OC_DIR/cli.json - fix host file readability, then restart the container" >&2; exit 1; }
  herdr_stage_write "$OC_GLOBAL_STAGE/cli.json" "$OC_CLI_CONTENT"
else
  herdr_stage_write "$OC_GLOBAL_STAGE/cli.json" '{}'
  OC_GLOBAL_MISSING+=(cli.json)
fi
# pr-link rides the plugins bind, not a cli.json entry: v2 auto-loads it via
# the package exports' ./tui entry (package.json gates the package), so the
# whole source dir stages and no hardcoded filename list drifts against the
# toolkit's plugin layout.
if [[ -s "$OC_PRLINK_SRC/package.json" ]]; then
  mkdir -p "$OC_PRLINK_STAGE"
  chmod 755 "$OC_PRLINK_STAGE"
  # The stage is a dir bind (per-file inodes are not mount-tracked), so wiping
  # first keeps it an exact mirror of the source dir.
  find "$OC_PRLINK_STAGE" -mindepth 1 -delete 2>/dev/null || true
  while IFS= read -r -d '' OC_PRLINK_FILE_SRC; do
    OC_PRLINK_FILE_REL="${OC_PRLINK_FILE_SRC#"$OC_PRLINK_SRC"/}"
    OC_PRLINK_FILE_DIR="$(dirname "$OC_PRLINK_FILE_REL")"
    if [[ "$OC_PRLINK_FILE_DIR" != "." ]]; then
      mkdir -p "$OC_PRLINK_STAGE/$OC_PRLINK_FILE_DIR"
      chmod 755 "$OC_PRLINK_STAGE/$OC_PRLINK_FILE_DIR"
    fi
    if [[ ! -r "$OC_PRLINK_FILE_SRC" ]]; then
      echo "[devcontainer] ERROR: pr-link file unreadable: $OC_PRLINK_FILE_SRC - fix host file readability, then restart the container" >&2
      exit 1
    fi
    OC_PRLINK_CONTENT="$(cat "$OC_PRLINK_FILE_SRC")" || { echo "[devcontainer] ERROR: pr-link file unreadable: $OC_PRLINK_FILE_SRC - fix host file readability, then restart the container" >&2; exit 1; }
    herdr_stage_write "$OC_PRLINK_STAGE/$OC_PRLINK_FILE_REL" "$OC_PRLINK_CONTENT"
  done < <(find "$OC_PRLINK_SRC" -type f -print0)
else
  rm -rf "$OC_PRLINK_STAGE"
  OC_GLOBAL_MISSING+=(plugins/pr-link/package.json)
fi
# One content source stages two names: opencode autoloads the .js from the plugins
# bind; the claude PreToolUse hook runs the .mjs (the .js parses as ESM only on node >= 22.7; the .mjs on any node).
OC_GUARD_SRC="$HERDR_OC_DIR/plugins/gh-owner-guard.js"
if [[ -f "$OC_GUARD_SRC" ]]; then
  if [[ ! -r "$OC_GUARD_SRC" ]]; then
    echo "[devcontainer] ERROR: gh-owner-guard source unreadable: $OC_GUARD_SRC - fix host file readability, then restart the container" >&2
    exit 1
  fi
  OC_GUARD_CONTENT="$(cat "$OC_GUARD_SRC")" || { echo "[devcontainer] ERROR: gh-owner-guard source unreadable: $OC_GUARD_SRC - fix host file readability, then restart the container" >&2; exit 1; }
  [[ -n "${OC_GUARD_CONTENT//[[:space:]]/}" ]] || { echo "[devcontainer] ERROR: gh-owner-guard source is empty: $OC_GUARD_SRC - reinstall via the toolkit's opencode-global/sync.sh" >&2; exit 1; }
  OC_GUARD_STAGE_JS="$HERDR_STAGE_DIR/plugins/gh-owner-guard.js"
  OC_GUARD_STAGE_MJS="$HERDR_STAGE_DIR/plugins/gh-owner-guard.mjs"
  herdr_stage_write "$OC_GUARD_STAGE_JS" "$OC_GUARD_CONTENT"
  herdr_stage_write "$OC_GUARD_STAGE_MJS" "$OC_GUARD_CONTENT"
  # herdr_stage_write WARNs and returns 0 on failure: one failed write splits
  # the pair, two fail over a prior run's equal-but-stale pair.
  if [[ ! -s "$OC_GUARD_STAGE_JS" || ! -s "$OC_GUARD_STAGE_MJS" ]] || ! cmp -s "$OC_GUARD_STAGE_JS" "$OC_GUARD_STAGE_MJS" || [[ "$(cat "$OC_GUARD_STAGE_JS")" != "$OC_GUARD_CONTENT" ]]; then
    echo "[devcontainer] ERROR: staged gh-owner-guard pair missing, divergent, or stale: $OC_GUARD_STAGE_JS vs $OC_GUARD_STAGE_MJS - a staging write failed (see WARN above); fix it and restart the container" >&2
    exit 1
  fi
else
  rm -f "$HERDR_STAGE_DIR/plugins/gh-owner-guard.js" "$HERDR_STAGE_DIR/plugins/gh-owner-guard.mjs"
  OC_GLOBAL_MISSING+=(plugins/gh-owner-guard.js)
fi
if [[ "${#OC_GLOBAL_MISSING[@]}" -gt 0 ]]; then
  echo "[devcontainer] WARN: opencode-global sync incomplete on the host (missing: ${OC_GLOBAL_MISSING[*]}) - run the toolkit's opencode-global/sync.sh; those pieces stay off in the container" >&2
else
  echo "[devcontainer] opencode-global config staged (cli.json + pr-link + gh-owner-guard)"
fi

# --- Stage claude container settings (host-gated permission mode) ---
# Merged into the script-owned container settings.json at postStart; a direct
# settings.json bind would block wire-claude-herdr.sh's writes (see that script).
CLAUDE_SETTINGS_SRC="$HOME/.config/devcontainer/claude-container-settings.json"
CLAUDE_STAGE="$DEVCONTAINER_DIR/claude-stage"
mkdir -p "$CLAUDE_STAGE"
chmod 755 "$CLAUDE_STAGE"
if [[ -s "$CLAUDE_SETTINGS_SRC" ]]; then
  herdr_stage_write "$CLAUDE_STAGE/settings.json" "$(cat "$CLAUDE_SETTINGS_SRC")"
  echo "[devcontainer] claude container settings staged"
else
  herdr_stage_write "$CLAUDE_STAGE/settings.json" '{}'
  echo "[devcontainer] WARN: claude container settings missing or empty at $CLAUDE_SETTINGS_SRC - {} staged (claude keeps default permission behavior)" >&2
fi

# Bind source for a consumer-set CLAUDE_CONFIG_DIR (README: "Claude sessions
# in the container"); the guard keeps a flipped-ownership bind non-fatal.
mkdir -p "$DEVCONTAINER_DIR/claude-home"
chmod 1777 "$DEVCONTAINER_DIR/claude-home" || echo "[devcontainer] WARN: cannot set mode on claude-home bind source" >&2

# --- Stage moshi hooks (host-global ~/.moshi/bridge, bound at /moshi); warn-only without moshi ---
bash "$DEVCONTAINER_DIR/stage-moshi.sh" || echo "[devcontainer] WARN: moshi staging failed - moshi hooks off in the container" >&2

WORKSPACE_DIR="${LOCAL_WORKSPACE_FOLDER:-$(pwd)}"
# Repo slug and volume prefix come from the origin remote; the prefix must match
# the workspaceMount volume source in devcontainer.json (lowercased repo name).
REPO_SLUG="$(git -C "$WORKSPACE_DIR" config --get remote.origin.url 2>/dev/null | sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##' || true)"
if [[ -z "$REPO_SLUG" || "$REPO_SLUG" != */* ]]; then
  echo "[devcontainer] ERROR: cannot derive owner/repo from the origin remote" >&2
  exit 1
fi
VOLUME_PREFIX="$(basename "$REPO_SLUG" | tr '[:upper:]' '[:lower:]')"
VOLUME_NAME="$VOLUME_PREFIX-$(basename "$WORKSPACE_DIR")"

# Check if volume has CONTENT (not just exists - Docker may auto-create empty volumes)
if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
  FILE_COUNT=$(docker run --rm --platform "$DCP_ARCH" -v "$VOLUME_NAME:/data" alpine sh -c 'ls -A /data 2>/dev/null | wc -l' 2>/dev/null || echo "0")
  if [[ "$FILE_COUNT" -gt 0 ]]; then
    echo "[devcontainer] Volume '$VOLUME_NAME' has content - skipping clone."
    exit 0
  fi
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")
echo "[devcontainer] Seeding volume '$VOLUME_NAME' with branch '$BRANCH'..."

# Create volume (idempotent - safe if it already exists empty)
docker volume create "$VOLUME_NAME" >/dev/null

# Clone on the HOST where git/gh credentials work, then copy into the volume.
# Using gh repo clone so auth is handled by gh's credential helper.
TEMP_CLONE=$(mktemp -d)
trap 'rm -rf "$TEMP_CLONE"' EXIT

echo "[devcontainer] Cloning branch '$BRANCH'..."
gh repo clone "$REPO_SLUG" "$TEMP_CLONE" -- --branch "$BRANCH"

# Seed host-only act config (gitignored, so never present in the clone) into new volumes.
for ACT_FILE in "$WORKSPACE_DIR/.act/.secrets" "$WORKSPACE_DIR/.act/.vars"; do
  if [[ -f "$ACT_FILE" ]]; then
    install -m 600 "$ACT_FILE" "$TEMP_CLONE/.act/$(basename "$ACT_FILE")"
    echo "[devcontainer] Seeded $(basename "$ACT_FILE") into the volume."
  fi
done

# Copy into the volume via a helper container, fix ownership to UID 1000 (vscode user)
echo "[devcontainer] Copying into volume..."
docker run --rm --platform "$DCP_ARCH" \
  -v "$VOLUME_NAME:/workspace" \
  -v "$TEMP_CLONE:/src:ro" \
  alpine sh -c 'cp -a /src/. /workspace/ && chown -R 1000:1000 /workspace'

echo "[devcontainer] Volume '$VOLUME_NAME' ready (branch: $BRANCH)."
