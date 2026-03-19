#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/orchestrate.sh"

echo "test-orchestrate"

bundle='{"higher_order_purpose":"ship the change safely","intents":[{"order":1,"intent":"implement the router","category":"implementation"},{"order":2,"intent":"verify the result","category":"verification"}],"truncated_to_max":false,"authority":"claude"}'

out="$(CCH_SKIP_PROVIDER_EXEC=1 CCH_INTENT_BUNDLE_JSON="$bundle" CCH_CLAUDE_HOURLY_USED=82 "$SCRIPT" auto "build quota router ALL")"
echo "$out" | grep -q "Mode: codex-heavy"
echo "$out" | grep -q "Prompt: implement the router"
echo "$out" | grep -q "Category:"
echo "$out" | grep -q "Category reason:"
echo "$out" | grep -q "Current usage:"
echo "$out" | grep -q "Claude: 82 / n/a"
echo "$out" | grep -q "Gemini: n/a / n/a"
echo "$out" | grep -q "Higher-order purpose: ship the change safely"
echo "$out" | grep -q "Intent authority: claude"
echo "$out" | grep -q "Intent count: 2"

out="$(CCH_SKIP_PROVIDER_EXEC=1 CCH_INTENT_BUNDLE_JSON="$bundle" CCH_CLAUDE_EXHAUSTED=true "$SCRIPT" auto "do the work ALL")"
echo "$out" | grep -q "Mode: codex-only"
echo "$out" | grep -q "Codex-only degraded mode is active"

out="$(CCH_SKIP_PROVIDER_EXEC=1 CCH_DISABLE_CLAUDE_INTENT_INFERENCE=1 "$SCRIPT" auto "plain request ALL")"
echo "$out" | grep -q "Mode: codex-heavy"
echo "$out" | grep -q "conservative Codex-first fallback"
echo "$out" | grep -q "Fallback reason:"
echo "$out" | grep -q "Intent count: 1"

out="$(CCH_SKIP_PROVIDER_EXEC=1 CCH_DISABLE_CLAUDE_INTENT_INFERENCE=1 "$SCRIPT" auto "plain request")"
echo "$out" | grep -q "Prompt: plain request"
echo "$out" | grep -q "Intent count: 1"

bundle='{"higher_order_purpose":"document the release","intents":[{"order":1,"intent":"write release notes","category":"documentation"}],"truncated_to_max":false,"authority":"claude"}'
out="$(CCH_SKIP_PROVIDER_EXEC=1 CCH_INTENT_BUNDLE_JSON="$bundle" "$SCRIPT" auto "write release notes ALL")"
echo "$out" | grep -q "Category: documentation"

bundle='{"higher_order_purpose":"ship safely","intents":[{"order":1,"intent":"review this implementation","category":"verification"},{"order":2,"intent":"document the release","category":"documentation"},{"order":3,"intent":"plan the follow-up","category":"planning"}],"truncated_to_max":false,"authority":"claude"}'
out="$(CCH_SKIP_PROVIDER_EXEC=1 CCH_INTENT_BUNDLE_JSON="$bundle" "$SCRIPT" auto "review this implementation ALL")"
echo "$out" | grep -q "Category: verification"
echo "$out" | grep -q "Category: documentation"
echo "$out" | grep -q "Category: planning"

echo "ok"
