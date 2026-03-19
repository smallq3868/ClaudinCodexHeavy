#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/helpers/provider-quota-status.sh"

echo "test-provider-quota-status"

out="$(CCH_CLAUDE_HOURLY_USED=82 CCH_GEMINI_WEEKLY_USED=96 "$SCRIPT")"
echo "$out" | jq -e '.claude.high == true' >/dev/null
echo "$out" | jq -e '.gemini.exhausted == true' >/dev/null

out="$("$SCRIPT")"
echo "$out" | jq -e '.claude.unknown == true' >/dev/null
echo "$out" | jq -e '.gemini.unknown == true' >/dev/null

echo "ok"

