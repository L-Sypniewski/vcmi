#!/usr/bin/env bash
# Runs on the HOST via initializeCommand (before container starts). Creates a per-worktree named volume seeded with a clone of the current branch; idempotent.
set -euo pipefail

# Pin helper-container to host arch: a stale cross-arch cached image reuses the wrong local tag and fails with "exec format error".
case "$(uname -m)" in
  x86_64)        DCP_ARCH="linux/amd64" ;;
  aarch64|arm64) DCP_ARCH="linux/arm64" ;;
  *)             DCP_ARCH="linux/amd64" ;;
esac

# --- Generate .env from host shell profile ---
# VS Code launched from desktop doesn't inherit .zshrc env vars, so source the profile into a Docker --env-file runArgs picks up.
DEVCONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$DEVCONTAINER_DIR/.env"
ENV_TMP="$(mktemp)"

# gh's token lives in the OS keyring (libsecret); VS Code's initializeCommand subprocess often lacks DBUS_SESSION_BUS_ADDRESS, so point it at the user bus.
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -S "/run/user/$(id -u)/bus" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
fi

# Every {env:VAR} referenced by the project opencode config rides from the host
# profile when set, so project MCPs authenticate identically without a hardcoded
# per-var allowlist. GH tokens are emitted explicitly below and excluded here to
# avoid duplicate lines. Host-global MCP definitions are deliberately NOT
# forwarded - the container sees only project-configured MCP servers.
MCP_ENV_REFS="$(grep -ohE '\{env:[A-Za-z_][A-Za-z0-9_]*\}' \
  "$DEVCONTAINER_DIR/../.opencode/opencode.json" 2>/dev/null \
  | sed -E 's/^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/\1/' | sort -u \
  | grep -vxE 'GH_TOKEN|GITHUB_TOKEN' || true)"

{
  if command -v zsh >/dev/null 2>&1 && [[ -f "$HOME/.zshrc" ]]; then
    # shellcheck disable=SC2086 # word-split intended: names match [A-Za-z_][A-Za-z0-9_]*
    zsh -c 'source ~/.zshrc 2>/dev/null; for v in "$@"; do val="${(P)v}"; [[ -n "$val" ]] && printf "%s=%s\n" "$v" "$val"; done' _ $MCP_ENV_REFS 2>/dev/null || true
  elif [[ -f "$HOME/.bashrc" ]]; then
    # shellcheck disable=SC2086 # word-split intended: names match [A-Za-z_][A-Za-z0-9_]*
    bash -c 'source ~/.bashrc 2>/dev/null; for v in "$@"; do eval "val=\${$v:-}"; [[ -n "$val" ]] && printf "%s=%s\n" "$v" "$val"; done' _ $MCP_ENV_REFS 2>/dev/null || true
  fi
  # Token from host keyring (inaccessible in container); GH_TOKEN=gh CLI, GITHUB_TOKEN=opencode gh-* MCP servers.
  GH_TOKEN_VAL="$(gh auth token 2>/dev/null || echo '')"
  echo "GH_TOKEN=$GH_TOKEN_VAL"
  echo "GITHUB_TOKEN=$GH_TOKEN_VAL"
} > "$ENV_TMP"

# Overwrite in place (same inode): devcontainer.json bind-mounts this file into the container, and a re-attached (not restarted) container keeps its mount on the original inode. Deleting+recreating would orphan the mount until a real stop/start, silently sourcing stale values.
# The umask-default (~0644) mode is load-bearing: container shells source this file as uid 1000
# through the /etc/devcontainer/host.env bind with no in-container re-own, so tightening locks the container out on root-run hosts; accepted on a single-admin host.
if ! cat "$ENV_TMP" > "$ENV_FILE" 2>/dev/null; then
  # Fallback: a prior container run left the file mode-600 root/in-container-UID owned, blocking the overwrite - recreating means fresh values only land on the next real start.
  rm -f "$ENV_FILE"
  mv "$ENV_TMP" "$ENV_FILE"
fi
rm -f "$ENV_TMP"
echo "[devcontainer] Env vars written to .env"

# --- Copy opencode model-provider auth.json ---
# opencode stores the LLM provider credential in auth.json under XDG_DATA_HOME; devcontainer.json bind-mounts it so opencode can authenticate.
AUTH_PATH="$(zsh -c 'source ~/.zshrc 2>/dev/null; echo "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json"' 2>/dev/null || echo "$HOME/.local/share/opencode/auth.json")"
AUTH_FILE="$DEVCONTAINER_DIR/opencode-auth.json"
if [[ -f "$AUTH_PATH" ]]; then
  AUTH_CONTENT="$(cat "$AUTH_PATH")"
  AUTH_SOURCE_MSG="[devcontainer] opencode auth.json copied from $AUTH_PATH"
else
  AUTH_CONTENT='{}'
  AUTH_SOURCE_MSG="[devcontainer] WARN: opencode auth.json not found at $AUTH_PATH (model provider auth will be missing)"
fi
# Overwrite in place (same inode), same rationale as the .env write above - a delete+recreate would orphan an already-running container's mount.
if ! printf '%s' "$AUTH_CONTENT" > "$AUTH_FILE" 2>/dev/null; then
  # Fallback: prior container run left file mode-600 root/in-container-UID owned, blocking the overwrite - same recovery as the .env case.
  rm -f "$AUTH_FILE"
  printf '%s' "$AUTH_CONTENT" > "$AUTH_FILE"
fi
chmod 600 "$AUTH_FILE"
echo "$AUTH_SOURCE_MSG"

# --- Copy opencode MCP OAuth tokens (mcp-auth.json) ---
# opencode keeps MCP-server OAuth tokens in mcp-auth.json next to auth.json;
# forwarding it lets container MCPs reuse host-minted OAuth as-is (no project
# MCPs configured today - forwarded for when one lands).
MCP_AUTH_PATH="$(dirname "$AUTH_PATH")/mcp-auth.json"
MCP_AUTH_FILE="$DEVCONTAINER_DIR/opencode-mcp-auth.json"
if [[ -f "$MCP_AUTH_PATH" ]]; then
  MCP_AUTH_CONTENT="$(cat "$MCP_AUTH_PATH")"
  MCP_AUTH_MSG="[devcontainer] opencode mcp-auth.json copied from $MCP_AUTH_PATH"
else
  MCP_AUTH_CONTENT='{}'
  MCP_AUTH_MSG="[devcontainer] opencode mcp-auth.json not found at $MCP_AUTH_PATH (no OAuth MCP tokens to forward)"
fi
# Overwrite in place (same inode), same rationale as the .env write above.
if ! printf '%s' "$MCP_AUTH_CONTENT" > "$MCP_AUTH_FILE" 2>/dev/null; then
  rm -f "$MCP_AUTH_FILE"
  printf '%s' "$MCP_AUTH_CONTENT" > "$MCP_AUTH_FILE"
fi
chmod 600 "$MCP_AUTH_FILE"
echo "$MCP_AUTH_MSG"

WORKSPACE_DIR="${LOCAL_WORKSPACE_FOLDER:-$(pwd)}"
VOLUME_NAME="vcmi-$(basename "$WORKSPACE_DIR")"

# Check volume for CONTENT, not existence - Docker may auto-create empty volumes.
if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
  FILE_COUNT=$(docker run --rm --platform "$DCP_ARCH" -v "$VOLUME_NAME:/data" alpine sh -c 'ls -A /data 2>/dev/null | wc -l' 2>/dev/null || echo "0")
  if [[ "$FILE_COUNT" -gt 0 ]]; then
    echo "[devcontainer] Volume '$VOLUME_NAME' has content - skipping clone."
    exit 0
  fi
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "develop")
# Clone from the fork (it carries the ship pipeline branches); override for a pristine upstream clone.
VCMI_REPO="${VCMI_REPO:-L-Sypniewski/vcmi}"
echo "[devcontainer] Seeding volume '$VOLUME_NAME' with '$VCMI_REPO' branch '$BRANCH'..."

# Create volume (idempotent - safe if it already exists empty)
docker volume create "$VOLUME_NAME" >/dev/null

# Clone on the HOST where gh's credential helper handles auth, then copy into the volume.
TEMP_CLONE=$(mktemp -d)
trap 'rm -rf "$TEMP_CLONE"' EXIT

echo "[devcontainer] Cloning '$VCMI_REPO' branch '$BRANCH'..."
gh repo clone "$VCMI_REPO" "$TEMP_CLONE" -- --branch "$BRANCH"

# Copy via helper container; chown to UID 1000 (vscode user). Submodules are
# fetched inside the container by postCreateCommand (public https URLs - no
# host-credential forwarding needed).
echo "[devcontainer] Copying into volume..."
docker run --rm --platform "$DCP_ARCH" \
  -v "$VOLUME_NAME:/workspace" \
  -v "$TEMP_CLONE:/src:ro" \
  alpine sh -c 'cp -a /src/. /workspace/ && chown -R 1000:1000 /workspace'

echo "[devcontainer] Volume '$VOLUME_NAME' ready (repo: $VCMI_REPO, branch: $BRANCH)."
