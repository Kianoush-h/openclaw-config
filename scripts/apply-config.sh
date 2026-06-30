#!/usr/bin/env bash
# apply-config.sh — validate this repo's openclaw.json, diff against the live one,
# back up, apply, and (optionally) restart the gateway.
# Usage: scripts/apply-config.sh [--restart]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_DIR/config/openclaw.json"
DST="$HOME/.openclaw/openclaw.json"

command -v openclaw >/dev/null || { echo "openclaw CLI not found"; exit 1; }

echo "Validating $SRC ..."
# Validate the JSON is well-formed first.
node -e "JSON.parse(require('fs').readFileSync('$SRC','utf8'))" || { echo "Invalid JSON"; exit 1; }

if grep -q 'REPLACE_WITH_' "$SRC"; then
  echo "WARNING: $SRC still contains REPLACE_WITH_* placeholders:"
  grep -n 'REPLACE_WITH_' "$SRC" || true
  read -r -p "Apply anyway? [y/N] " a; [ "$a" = "y" ] || exit 1
fi

if [ -f "$DST" ]; then
  echo "Diff (live <-> repo):"
  diff -u "$DST" "$SRC" || true
  bak="$DST.bak.$(date +%s)"
  cp "$DST" "$bak"; echo "Backed up live config to $bak"
fi

read -r -p "Write repo config to $DST? [y/N] " a; [ "$a" = "y" ] || exit 1
cp "$SRC" "$DST"

echo "Running doctor (schema/state validation) ..."
openclaw config validate || true
openclaw doctor || true

if [ "${1:-}" = "--restart" ]; then
  read -r -p "Restart gateway now? [y/N] " a
  [ "$a" = "y" ] && systemctl --user restart openclaw-gateway.service && openclaw status
fi
