#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CONFIG="${HOME}/.claude/plugins/data/cch-claudin-codex-heavy/config.json"
CONFIG_PATH="${CCH_CONFIG:-$DEFAULT_CONFIG}"
CODEX_MODEL="${CCH_CODEX_MODEL:-gpt-5.4}"
GEMINI_MODEL="${CCH_GEMINI_MODEL:-gemini-3.1-pro-preview}"
SKIP_PROVIDER_EXEC="${CCH_SKIP_PROVIDER_EXEC:-0}"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

read_json_value() {
    local file="$1"
    local query="$2"
    if [[ -f "$file" ]] && command -v jq >/dev/null 2>&1; then
        jq -r "$query // empty" "$file" 2>/dev/null || true
    fi
}

expand_tilde() {
    local value="$1"
    if [[ "$value" == "~/"* ]]; then
        printf '%s\n' "${HOME}/${value#~/}"
    else
        printf '%s\n' "$value"
    fi
}

config_path() {
    expand_tilde "$CONFIG_PATH"
}

config_or_default() {
    local query="$1"
    local fallback="$2"
    local value
    value="$(read_json_value "$(config_path)" "$query")"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

claude_intent_model() {
    if [[ -n "${CCH_CLAUDE_INTENT_MODEL:-}" ]]; then
        printf '%s\n' "$CCH_CLAUDE_INTENT_MODEL"
    else
        config_or_default '.models.claude_intent' 'sonnet'
    fi
}

json_escape() {
    if command -v jq >/dev/null 2>&1; then
        jq -Rn --arg value "$1" '$value'
    else
        printf '"%s"' "$1"
    fi
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

default_category_policy() {
    local category="$1"
    case "$category" in
        implementation)
            cat <<EOF
{"leader":"claude","executor":"codex:gpt-5.4","fallback":"codex:gpt-5.4","quota_bias":"codex-first"}
EOF
            ;;
        research)
            cat <<EOF
{"leader":"gemini","executor":"gemini:default","fallback":"codex:gpt-5.4","quota_bias":"gemini-first"}
EOF
            ;;
        verification)
            cat <<EOF
{"leader":"claude","executor":"codex:gpt-5.4","fallback":"codex:gpt-5.4","quota_bias":"codex-first"}
EOF
            ;;
        security)
            cat <<EOF
{"leader":"claude","executor":"codex:gpt-5.4","fallback":"gemini:default","quota_bias":"codex-first"}
EOF
            ;;
        debate)
            cat <<EOF
{"leader":"claude","executor":"codex+gemini","fallback":"codex:gpt-5.4","quota_bias":"balanced"}
EOF
            ;;
        documentation)
            cat <<EOF
{"leader":"claude","executor":"claude","fallback":"codex:gpt-5.4","quota_bias":"claude-first"}
EOF
            ;;
        planning)
            cat <<EOF
{"leader":"claude","executor":"claude","fallback":"codex:gpt-5.4","quota_bias":"claude-first"}
EOF
            ;;
        *)
            default_category_policy implementation
            ;;
    esac
}

category_policy() {
    local category="$1"
    local cfg
    cfg="$(config_path)"
    if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
        local policy
        policy="$(jq -c --arg category "$category" '.categories[$category] // empty' "$cfg" 2>/dev/null || true)"
        if [[ -n "$policy" ]]; then
            printf '%s\n' "$policy"
            return 0
        fi
    fi
    default_category_policy "$category"
}

keyword_match() {
    local haystack="$1"
    shift
    local needle
    for needle in "$@"; do
        if [[ "$haystack" == *"$needle"* ]]; then
            return 0
        fi
    done
    return 1
}

resolve_category() {
    local raw_prompt="$1"
    local command_surface="${2:-}"
    local explicit_command="${3:-false}"
    local prompt_lc category
    prompt_lc="$(printf '%s' "$raw_prompt" | tr '[:upper:]' '[:lower:]')"

    if [[ "$explicit_command" == "true" ]]; then
        case "$command_surface" in
            implementation|research|verification|security|debate|documentation|planning)
                printf '%s\n' "$command_surface"
                return 0
                ;;
        esac
    fi

    if keyword_match "$prompt_lc" "plan" "roadmap" "spec" "requirements"; then
        category="planning"
    elif keyword_match "$prompt_lc" "readme" "docs" "documentation" "write docs" "release notes" "notes" "changelog"; then
        category="documentation"
    elif keyword_match "$prompt_lc" "debate" "argue" "compare options" "tradeoff"; then
        category="debate"
    elif keyword_match "$prompt_lc" "security" "vulnerability" "audit" "auth" "permission"; then
        category="security"
    elif keyword_match "$prompt_lc" "verify" "validation" "review" "test" "check"; then
        category="verification"
    elif keyword_match "$prompt_lc" "research" "investigate" "explore" "survey"; then
        category="research"
    else
        category="implementation"
    fi

    printf '%s\n' "$category"
}

intent_default_category() {
    config_or_default '.intent_inference.unknown_intent_default_category' 'implementation'
}

max_intents() {
    config_or_default '.intent_inference.max_intents' '3'
}

normalize_category() {
    local category="$1"
    case "$category" in
        implementation|research|verification|security|debate|documentation|planning)
            printf '%s\n' "$category"
            ;;
        *)
            intent_default_category
            ;;
    esac
}

mock_intent_bundle() {
    local prompt="$1"
    local category="$2"
    local max_count
    max_count="$(max_intents)"
    cat <<EOF
{
  "higher_order_purpose": $(json_escape "$prompt"),
  "intents": [
    {
      "order": 1,
      "intent": $(json_escape "$prompt"),
      "category": $(json_escape "$category")
    }
  ],
  "truncated_to_max": false,
  "authority": "claude"
}
EOF
}

infer_intent_bundle_with_claude() {
    local prompt="$1"
    local fallback_category="$2"
    local max_count schema output
    max_count="$(max_intents)"
    schema='{"type":"object","properties":{"higher_order_purpose":{"type":"string"},"intents":{"type":"array","maxItems":3,"items":{"type":"object","properties":{"order":{"type":"integer"},"intent":{"type":"string"},"category":{"type":"string","enum":["implementation","research","verification","security","debate","documentation","planning"]}},"required":["order","intent","category"],"additionalProperties":false}},"truncated_to_max":{"type":"boolean"},"authority":{"type":"string"}},"required":["higher_order_purpose","intents","truncated_to_max","authority"],"additionalProperties":false}'

    if [[ -n "${CCH_INTENT_BUNDLE_JSON:-}" ]]; then
        printf '%s\n' "$CCH_INTENT_BUNDLE_JSON"
        return 0
    fi

    if [[ "${CCH_DISABLE_CLAUDE_INTENT_INFERENCE:-0}" == "1" ]]; then
        mock_intent_bundle "$prompt" "$fallback_category"
        return 0
    fi

    if ! command -v claude >/dev/null 2>&1; then
        mock_intent_bundle "$prompt" "$fallback_category"
        return 0
    fi

    output="$(
        claude --print \
            --output-format json \
            --json-schema "$schema" \
            --model "$(claude_intent_model)" \
            "Infer one higher-order purpose for this request, then decompose it into at most ${max_count} ordered intents. Preserve the user's actual meaning. Do not go beyond one inferred higher-order purpose. Return only valid JSON. Request: ${prompt}" \
            2>/dev/null || true
    )"

    if [[ -n "$output" ]] && jq -e '.higher_order_purpose and (.intents | length >= 1)' >/dev/null 2>&1 <<<"$output"; then
        printf '%s\n' "$output"
    else
        mock_intent_bundle "$prompt" "$fallback_category"
    fi
}

intent_bundle_with_normalized_categories() {
    local bundle_json="$1"
    jq --arg default_category "$(intent_default_category)" '
      .authority = (.authority // "claude")
      | .intents = (
          .intents
          | sort_by(.order)
          | map(.category = (
              if (.category == "implementation" or .category == "research" or .category == "verification" or .category == "security" or .category == "debate" or .category == "documentation" or .category == "planning")
              then .category
              else $default_category
              end
            ))
        )
    ' <<<"$bundle_json"
}

resolve_executor_surface() {
    local category="$1"
    local policy_json="$2"
    local quota_json="$3"
    local mode="$4"
    local executor fallback quota_bias
    local claude_exhausted gemini_exhausted claude_high gemini_high any_unknown

    executor="$(jq -r '.executor' <<<"$policy_json")"
    fallback="$(jq -r '.fallback' <<<"$policy_json")"
    quota_bias="$(jq -r '.quota_bias' <<<"$policy_json")"
    claude_exhausted="$(jq -r '.claude.exhausted' <<<"$quota_json")"
    gemini_exhausted="$(jq -r '.gemini.exhausted' <<<"$quota_json")"
    claude_high="$(jq -r '.claude.high' <<<"$quota_json")"
    gemini_high="$(jq -r '.gemini.high' <<<"$quota_json")"
    any_unknown="$(jq -r '(.claude.unknown or .gemini.unknown)' <<<"$quota_json")"

    if [[ "$mode" == "codex-only" ]]; then
        printf 'codex:gpt-5.4\n'
        return 0
    fi

    case "$executor" in
        gemini:default)
            if [[ "$gemini_exhausted" == "true" || "$any_unknown" == "true" ]]; then
                printf '%s\n' "$fallback"
            else
                printf '%s\n' "$executor"
            fi
            ;;
        codex+gemini)
            if [[ "$gemini_exhausted" == "true" || "$any_unknown" == "true" ]]; then
                printf '%s\n' "$fallback"
            else
                printf '%s\n' "$executor"
            fi
            ;;
        claude)
            if [[ "$claude_exhausted" == "true" ]]; then
                printf '%s\n' "$fallback"
            elif [[ "$mode" == "codex-heavy" && "$quota_bias" == "codex-first" ]]; then
                printf '%s\n' "$fallback"
            else
                printf '%s\n' "$executor"
            fi
            ;;
        *)
            if [[ "$mode" == "codex-heavy" && "$quota_bias" == "codex-first" ]]; then
                printf '%s\n' "$fallback"
            elif [[ "$gemini_high" == "true" && "$executor" == "gemini:default" ]]; then
                printf '%s\n' "$fallback"
            elif [[ "$claude_high" == "true" && "$executor" == "claude" ]]; then
                printf '%s\n' "$fallback"
            else
                printf '%s\n' "$executor"
            fi
            ;;
    esac
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
    local category="$2"
    local executor_surface="$3"
    local cleaned_prompt="$4"
    local quota_json="$5"
    local policy_json="$6"
    local claude_source gemini_source truth_source claude_reason gemini_reason fallback_reason
    claude_source="$(jq -r '.claude.source' <<<"$quota_json")"
    gemini_source="$(jq -r '.gemini.source' <<<"$quota_json")"
    claude_reason="$(jq -r '.claude.fallback_reason // empty' <<<"$quota_json")"
    gemini_reason="$(jq -r '.gemini.fallback_reason // empty' <<<"$quota_json")"
    if [[ "$claude_source" == "$gemini_source" ]]; then
        truth_source="$claude_source"
    else
        truth_source="mixed:${claude_source},${gemini_source}"
    fi
    if [[ -n "$claude_reason" && "$claude_reason" == "$gemini_reason" ]]; then
        fallback_reason="$claude_reason"
    elif [[ -n "$claude_reason" && -n "$gemini_reason" ]]; then
        fallback_reason="mixed:${claude_reason},${gemini_reason}"
    elif [[ -n "$claude_reason" ]]; then
        fallback_reason="$claude_reason"
    elif [[ -n "$gemini_reason" ]]; then
        fallback_reason="$gemini_reason"
    else
        fallback_reason="none"
    fi
    printf 'Mode: %s\n' "$mode"
    printf 'Category: %s\n' "$category"
    printf 'Truth source: %s\n' "$truth_source"
    printf 'Fallback reason: %s\n' "$fallback_reason"
    printf 'Executor: %s\n' "$executor_surface"
    printf 'Prompt: %s\n' "$cleaned_prompt"
    printf 'Reason: %s' "$(mode_reason "$mode" "$quota_json")"
    printf 'Policy: %s\n' "$policy_json"
    printf 'Quota: %s\n' "$quota_json"
}

render_intent_summary() {
    local bundle_json="$1"
    printf 'Higher-order purpose: %s\n' "$(jq -r '.higher_order_purpose' <<<"$bundle_json")"
    printf 'Intent authority: %s\n' "$(jq -r '.authority' <<<"$bundle_json")"
    printf 'Intent count: %s\n' "$(jq -r '.intents | length' <<<"$bundle_json")"
    printf 'Intent bundle: %s\n' "$bundle_json"
}

run_executor_surface() {
    local executor_surface="$1"
    local prompt="$2"
    case "$executor_surface" in
        codex:gpt-5.4|codex)
            printf '\n=== Codex ===\n'
            run_codex "$prompt"
            ;;
        gemini:default|gemini)
            printf '\n=== Gemini ===\n'
            run_gemini "$prompt"
            ;;
        codex+gemini)
            printf '\n=== Codex ===\n'
            run_codex "$prompt"
            printf '\n=== Gemini ===\n'
            run_gemini "$prompt"
            ;;
        claude)
            printf '\n=== Claude ===\n'
            printf '[in-session] Claude is the designated executor for this category. Use the routing summary and continue in the current Claude session.\n'
            ;;
        *)
            printf '\n=== Fallback ===\n'
            printf '[unhandled executor] %s\n' "$executor_surface"
            ;;
    esac
}

run_intent() {
    local mode="$1"
    local quota_json="$2"
    local intent_json="$3"
    local category intent_text policy_json executor_surface

    category="$(jq -r '.category' <<<"$intent_json")"
    intent_text="$(jq -r '.intent' <<<"$intent_json")"
    policy_json="$(category_policy "$category")"
    executor_surface="$(resolve_executor_surface "$category" "$policy_json" "$quota_json" "$mode")"

    printf '\n--- Intent %s ---\n' "$(jq -r '.order' <<<"$intent_json")"
    render_summary "$mode" "$category" "$executor_surface" "$intent_text" "$quota_json" "$policy_json"
    run_executor_surface "$executor_surface" "$intent_text"
}

run_auto() {
    local raw_prompt="$1"
    local command_surface="auto"
    local explicit_command="true"
    local cleaned_prompt quota_json mode category policy_json executor_surface intent_bundle_json
    if ! has_all_suffix "$raw_prompt"; then
        printf 'Error: trailing ALL suffix not found.\n' >&2
        return 1
    fi

    cleaned_prompt="$(strip_all_suffix "$raw_prompt")"
    quota_json="$("$ROOT_DIR/scripts/helpers/provider-quota-status.sh")"
    mode="$(select_mode "$quota_json")"
    category="$(resolve_category "$cleaned_prompt" "$command_surface" "$explicit_command")"
    intent_bundle_json="$(infer_intent_bundle_with_claude "$cleaned_prompt" "$category")"
    intent_bundle_json="$(intent_bundle_with_normalized_categories "$intent_bundle_json")"

    printf 'Entry category: %s\n' "$category"
    render_intent_summary "$intent_bundle_json"

    while IFS= read -r intent_row; do
        [[ -n "$intent_row" ]] || continue
        run_intent "$mode" "$quota_json" "$intent_row"
    done < <(jq -c '.intents[]' <<<"$intent_bundle_json")

    printf '\n=== Orchestration Note ===\n'
    if [[ "$mode" == "codex-only" ]]; then
        printf 'Codex-only degraded mode is active, but the intent bundle still stays within one higher-order purpose.\n'
    else
        printf 'Claude should preserve the higher-order purpose and synthesize all intent results into one final response.\n'
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
