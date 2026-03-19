#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/orchestrate.sh"

echo "test-orchestrate"

out="$(CCH_SKIP_PROVIDER_EXEC=1 CCH_CLAUDE_HOURLY_USED=82 "$SCRIPT" auto "build quota router ALL")"
echo "$out" | grep -q "Mode: codex-heavy"
echo "$out" | grep -q "Prompt: build quota router"

out="$(CCH_SKIP_PROVIDER_EXEC=1 CCH_CLAUDE_EXHAUSTED=true "$SCRIPT" auto "do the work ALL")"
echo "$out" | grep -q "Mode: codex-only"
echo "$out" | grep -q "Codex-only degraded mode is active"

out="$(CCH_SKIP_PROVIDER_EXEC=1 "$SCRIPT" auto "plain request ALL")"
echo "$out" | grep -q "Mode: codex-heavy"
echo "$out" | grep -q "conservative Codex-first fallback"

echo "ok"
