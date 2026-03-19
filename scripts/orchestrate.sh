#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODEX_MODEL="${CCH_CODEX_MODEL:-gpt-5.4}"
GEMINI_MODEL="${CCH_GEMINI_MODEL:-gemini-3.1-pro-preview}"
SKIP_PROVIDER_EXEC="${CCH_SKIP_PROVIDER_EXEC:-0}"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

strip_all_suffix() {
    local prompt
    prompt="$(trim "$1")"
    if [[ "$prompt" =~ ^(.*)[[:space:]]ALL[[:space:]]*$ ]]; then
        trim "${BASH_REMATCH[1]}"
        return 0
    fi
    printf '%s\n' "$prompt"
}

has_all_suffix() {
    local prompt
    prompt="$(trim "$1")"
    [[ "$prompt" =~ [[:space:]]ALL[[:space:]]*$ || "$prompt" == "ALL" ]]
}

run_codex() {
    local prompt="$1"
    if [[ "$SKIP_PROVIDER_EXEC" == "1" ]]; then
        printf '[skipped] codex exec --model %s --sandbox workspace-write --ask-for-approval never %q\n' "$CODEX_MODEL" "$prompt"
        return 0
    fi
    if ! command -v codex >/dev/null 2>&1; then
        printf '[unavailable] codex CLI not found\n'
        return 0
    fi
    codex exec --model "$CODEX_MODEL" --sandbox workspace-write --ask-for-approval never "$prompt" 2>&1 || true
}

run_gemini() {
    local prompt="$1"
    if [[ "$SKIP_PROVIDER_EXEC" == "1" ]]; then
        printf '[skipped] gemini -o text --approval-mode yolo -m %s <prompt>\n' "$GEMINI_MODEL"
        return 0
    fi
    if ! command -v gemini >/dev/null 2>&1; then
        printf '[unavailable] gemini CLI not found\n'
        return 0
    fi
    printf '%s' "$prompt" | env NODE_NO_WARNINGS=1 gemini -o text --approval-mode yolo -m "$GEMINI_MODEL" 2>&1 || true
}

select_mode() {
    local quota_json="$1"
    local claude_exhausted gemini_exhausted claude_high gemini_high claude_unknown gemini_unknown
    claude_exhausted="$(jq -r '.claude.exhausted' <<<"$quota_json")"
    gemini_exhausted="$(jq -r '.gemini.exhausted' <<<"$quota_json")"
    claude_high="$(jq -r '.claude.high' <<<"$quota_json")"
    gemini_high="$(jq -r '.gemini.high' <<<"$quota_json")"
    claude_unknown="$(jq -r '.claude.unknown' <<<"$quota_json")"
    gemini_unknown="$(jq -r '.gemini.unknown' <<<"$quota_json")"

    if [[ "$claude_exhausted" == "true" ]]; then
        printf 'codex-only\n'
    elif [[ "$gemini_exhausted" == "true" ]]; then
        printf 'codex-heavy\n'
    elif [[ "$claude_unknown" == "true" || "$gemini_unknown" == "true" ]]; then
        printf 'codex-heavy\n'
    elif [[ "$claude_high" == "true" || "$gemini_high" == "true" ]]; then
        printf 'codex-heavy\n'
    else
        printf 'normal\n'
    fi
}

mode_reason() {
    local mode="$1"
    local quota_json="$2"
    case "$mode" in
        codex-only)
            printf 'Claude is effectively exhausted, so execution degrades to Codex-only.\n'
            ;;
        codex-heavy)
            if [[ "$(jq -r '.gemini.exhausted' <<<"$quota_json")" == "true" ]]; then
                printf 'Gemini is exhausted, so GPT/Codex takes over that work.\n'
            elif [[ "$(jq -r '.claude.unknown' <<<"$quota_json")" == "true" || "$(jq -r '.gemini.unknown' <<<"$quota_json")" == "true" ]]; then
                printf 'Quota state is unknown, so conservative Codex-first fallback is used.\n'
            else
                printf 'At least one provider is in a high-usage state, so Codex-first routing is used.\n'
            fi
            ;;
        *)
            printf 'Quota state is healthy, so normal orchestration remains enabled.\n'
            ;;
    esac
}

render_summary() {
    local mode="$1"
    local cleaned_prompt="$2"
    local quota_json="$3"
    printf 'Mode: %s\n' "$mode"
    printf 'Prompt: %s\n' "$cleaned_prompt"
    printf 'Reason: %s' "$(mode_reason "$mode" "$quota_json")"
    printf 'Quota: %s\n' "$quota_json"
}

run_auto() {
    local raw_prompt="$1"
    if ! has_all_suffix "$raw_prompt"; then
        printf 'Error: trailing ALL suffix not found.\n' >&2
        return 1
    fi
    local cleaned_prompt quota_json mode codex_output gemini_output
    cleaned_prompt="$(strip_all_suffix "$raw_prompt")"
    quota_json="$("$ROOT_DIR/scripts/helpers/provider-quota-status.sh")"
    mode="$(select_mode "$quota_json")"

    render_summary "$mode" "$cleaned_prompt" "$quota_json"
    printf '\n=== Codex ===\n'
    codex_output="$(run_codex "$cleaned_prompt")"
    printf '%s\n' "$codex_output"

    if [[ "$mode" == "normal" ]]; then
        printf '\n=== Gemini ===\n'
        gemini_output="$(run_gemini "$cleaned_prompt")"
        printf '%s\n' "$gemini_output"
        printf '\n=== Orchestration Note ===\n'
        printf 'Use Codex and Gemini outputs together for the final response.\n'
    elif [[ "$mode" == "codex-heavy" ]]; then
        if [[ "$(jq -r '.gemini.exhausted' <<<"$quota_json")" != "true" ]]; then
            printf '\n=== Gemini (best-effort) ===\n'
            gemini_output="$(run_gemini "$cleaned_prompt")"
            printf '%s\n' "$gemini_output"
        fi
        printf '\n=== Orchestration Note ===\n'
        printf 'Bias the final response toward Codex(gpt-5.4) and use Gemini only if it returned safely.\n'
    else
        printf '\n=== Orchestration Note ===\n'
        printf 'Codex-only degraded mode is active.\n'
    fi
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") auto "<prompt ... ALL>"
EOF
}

main() {
    local command="${1:-}"
    case "$command" in
        auto)
            shift
            [[ $# -lt 1 ]] && { usage; exit 1; }
            run_auto "$*"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"

