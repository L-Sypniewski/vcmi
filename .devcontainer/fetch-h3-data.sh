#!/usr/bin/env bash
# Fetches the official VCMI test H3 data (same artifact upstream CI uses -
# .github/workflows/github.yml "Prepare Heroes 3 data") into the persistent
# h3-data volume so the unit tests can resolve real game resources
# (DATA/LCDESC.TXT etc.). Idempotent: skips when data is already present.
set -euo pipefail

DEST="/mnt/h3-data/vcmi"
URL="https://github.com/vcmi-mods/vcmi-test-data/releases/download/v2.0/heroes3.7z"

if [ -d "$DEST/Data" ]; then
  echo "[h3-data] $DEST/Data already present - skipping download."
  exit 0
fi

echo "[h3-data] Downloading H3 test data (one-time; cached on the h3-data volume)..."
TMP_ARCHIVE="$(mktemp /tmp/heroes3.XXXXXX.7z)"
trap 'rm -f "$TMP_ARCHIVE"' EXIT
wget --progress=dot:giga "$URL" -O "$TMP_ARCHIVE"
mkdir -p "$DEST"
7za x -o"$DEST" "$TMP_ARCHIVE" > /dev/null
echo "[h3-data] Extracted to $DEST."
ls "$DEST" | head -5
