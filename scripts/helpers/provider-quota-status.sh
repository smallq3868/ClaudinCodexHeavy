#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_CONFIG="${HOME}/.claude/plugins/data/cch-claudin-codex-heavy/config.json"
CONFIG_PATH="${CCH_CONFIG:-$DEFAULT_CONFIG}"

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

config_or_default() {
    local env_value="$1"
    local file="$2"
    local query="$3"
    local fallback="$4"
    if [[ -n "$env_value" ]]; then
        printf '%s\n' "$env_value"
        return 0
    fi
    local value
    value="$(read_json_value "$file" "$query")"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

quota_state_file="$(config_or_default "${CCH_QUOTA_STATE_FILE:-}" "$CONFIG_PATH" '.quota_state_file' '~/.claude/plugins/data/cch-claudin-codex-heavy/quota-state.json')"
quota_state_file="$(expand_tilde "$quota_state_file")"

claude_hourly_warn="$(config_or_default "${CCH_CLAUDE_HOURLY_WARN:-}" "$CONFIG_PATH" '.thresholds.claude.hourly_warn' '60')"
claude_weekly_warn="$(config_or_default "${CCH_CLAUDE_WEEKLY_WARN:-}" "$CONFIG_PATH" '.thresholds.claude.weekly_warn' '80')"
claude_hourly_exhausted="$(config_or_default "${CCH_CLAUDE_HOURLY_EXHAUSTED:-}" "$CONFIG_PATH" '.thresholds.claude.hourly_exhausted' '95')"
claude_weekly_exhausted="$(config_or_default "${CCH_CLAUDE_WEEKLY_EXHAUSTED:-}" "$CONFIG_PATH" '.thresholds.claude.weekly_exhausted' '95')"
gemini_hourly_warn="$(config_or_default "${CCH_GEMINI_HOURLY_WARN:-}" "$CONFIG_PATH" '.thresholds.gemini.hourly_warn' '60')"
gemini_weekly_warn="$(config_or_default "${CCH_GEMINI_WEEKLY_WARN:-}" "$CONFIG_PATH" '.thresholds.gemini.weekly_warn' '80')"
gemini_hourly_exhausted="$(config_or_default "${CCH_GEMINI_HOURLY_EXHAUSTED:-}" "$CONFIG_PATH" '.thresholds.gemini.hourly_exhausted' '95')"
gemini_weekly_exhausted="$(config_or_default "${CCH_GEMINI_WEEKLY_EXHAUSTED:-}" "$CONFIG_PATH" '.thresholds.gemini.weekly_exhausted' '95')"

read_provider_metric() {
    local provider="$1"
    local metric="$2"
    local env_name="$3"
    local env_value="${!env_name:-}"
    if [[ -n "$env_value" ]]; then
        printf '%s\n' "$env_value"
        return 0
    fi
    read_json_value "$quota_state_file" ".${provider}.${metric}"
}

read_provider_bool() {
    local provider="$1"
    local metric="$2"
    local env_name="$3"
    local env_value="${!env_name:-}"
    if [[ -n "$env_value" ]]; then
        printf '%s\n' "$env_value"
        return 0
    fi
    read_json_value "$quota_state_file" ".${provider}.${metric}"
}

bool_value() {
    case "${1:-}" in
        true|TRUE|1|yes|YES) printf 'true\n' ;;
        *) printf 'false\n' ;;
    esac
}

provider_json() {
    local provider="$1"
    local hourly="$2"
    local weekly="$3"
    local exhausted_flag="$4"
    local warn_hourly="$5"
    local warn_weekly="$6"
    local exhausted_hourly="$7"
    local exhausted_weekly="$8"
    local source="$9"
    local unknown=false
    local high=false
    local exhausted=false

    if [[ -z "$hourly" && -z "$weekly" && "$exhausted_flag" != "true" ]]; then
        unknown=true
    fi

    if [[ "$exhausted_flag" == "true" ]]; then
        exhausted=true
    fi

    if [[ -n "$hourly" && "$hourly" =~ ^[0-9]+$ && "$hourly" -ge "$warn_hourly" ]]; then
        high=true
    fi
    if [[ -n "$weekly" && "$weekly" =~ ^[0-9]+$ && "$weekly" -ge "$warn_weekly" ]]; then
        high=true
    fi
    if [[ -n "$hourly" && "$hourly" =~ ^[0-9]+$ && "$hourly" -ge "$exhausted_hourly" ]]; then
        exhausted=true
    fi
    if [[ -n "$weekly" && "$weekly" =~ ^[0-9]+$ && "$weekly" -ge "$exhausted_weekly" ]]; then
        exhausted=true
    fi

    cat <<EOF
{
  "hourly_used": ${hourly:-null},
  "weekly_used": ${weekly:-null},
  "high": $high,
  "exhausted": $exhausted,
  "unknown": $unknown,
  "source": "$source"
}
EOF
}

claude_hourly="$(read_provider_metric claude hourly_used CCH_CLAUDE_HOURLY_USED)"
claude_weekly="$(read_provider_metric claude weekly_used CCH_CLAUDE_WEEKLY_USED)"
claude_exhausted_flag="$(bool_value "$(read_provider_bool claude exhausted CCH_CLAUDE_EXHAUSTED)")"
gemini_hourly="$(read_provider_metric gemini hourly_used CCH_GEMINI_HOURLY_USED)"
gemini_weekly="$(read_provider_metric gemini weekly_used CCH_GEMINI_WEEKLY_USED)"
gemini_exhausted_flag="$(bool_value "$(read_provider_bool gemini exhausted CCH_GEMINI_EXHAUSTED)")"

claude_source="unknown"
gemini_source="unknown"
if [[ -f "$quota_state_file" ]]; then
    claude_source="file"
    gemini_source="file"
fi
if [[ -n "${CCH_CLAUDE_HOURLY_USED:-}${CCH_CLAUDE_WEEKLY_USED:-}${CCH_CLAUDE_EXHAUSTED:-}" ]]; then
    claude_source="env"
fi
if [[ -n "${CCH_GEMINI_HOURLY_USED:-}${CCH_GEMINI_WEEKLY_USED:-}${CCH_GEMINI_EXHAUSTED:-}" ]]; then
    gemini_source="env"
fi

cat <<EOF
{
  "claude": $(provider_json "claude" "$claude_hourly" "$claude_weekly" "$claude_exhausted_flag" "$claude_hourly_warn" "$claude_weekly_warn" "$claude_hourly_exhausted" "$claude_weekly_exhausted" "$claude_source"),
  "gemini": $(provider_json "gemini" "$gemini_hourly" "$gemini_weekly" "$gemini_exhausted_flag" "$gemini_hourly_warn" "$gemini_weekly_warn" "$gemini_hourly_exhausted" "$gemini_weekly_exhausted" "$gemini_source")
}
EOF

