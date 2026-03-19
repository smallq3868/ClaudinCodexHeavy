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

provider_state_file() {
    local provider="$1"
    local env_name="$2"
    local query="$3"
    local fallback="$4"
    local value
    value="$(config_or_default "${!env_name:-}" "$CONFIG_PATH" "$query" "$fallback")"
    expand_tilde "$value"
}

quota_state_file="$(config_or_default "${CCH_QUOTA_STATE_FILE:-}" "$CONFIG_PATH" '.quota_state_file' '~/.claude/plugins/data/cch-claudin-codex-heavy/quota-state.json')"
quota_state_file="$(expand_tilde "$quota_state_file")"

claude_live_enabled="$(config_or_default "${CCH_CLAUDE_LIVE_ENABLED:-}" "$CONFIG_PATH" '.quota_sources.claude.live_enabled' 'true')"
gemini_live_enabled="$(config_or_default "${CCH_GEMINI_LIVE_ENABLED:-}" "$CONFIG_PATH" '.quota_sources.gemini.live_enabled' 'true')"
claude_live_state_file="$(provider_state_file "claude" "CCH_CLAUDE_LIVE_STATE_FILE" '.quota_sources.claude.live_state_file' '~/.claude/plugins/data/cch-claudin-codex-heavy/live-quota-state.json')"
gemini_live_state_file="$(provider_state_file "gemini" "CCH_GEMINI_LIVE_STATE_FILE" '.quota_sources.gemini.live_state_file' '~/.claude/plugins/data/cch-claudin-codex-heavy/live-quota-state.json')"

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

read_live_provider_metric() {
    local provider="$1"
    local metric="$2"
    local env_name="$3"
    local live_file="$4"
    local env_value="${!env_name:-}"
    if [[ -n "$env_value" ]]; then
        printf '%s\n' "$env_value"
        return 0
    fi
    read_json_value "$live_file" ".${provider}.${metric}"
}

read_live_provider_bool() {
    local provider="$1"
    local metric="$2"
    local env_name="$3"
    local live_file="$4"
    local env_value="${!env_name:-}"
    if [[ -n "$env_value" ]]; then
        printf '%s\n' "$env_value"
        return 0
    fi
    read_json_value "$live_file" ".${provider}.${metric}"
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
    local live_attempted="${10:-false}"
    local fallback_reason="${11:-}"
    local unknown=false
    local high=false
    local exhausted=false
    local rendered_fallback_reason="null"

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
    if [[ -n "$fallback_reason" ]]; then
        rendered_fallback_reason="\"$fallback_reason\""
    fi

    cat <<EOF
{
  "hourly_used": ${hourly:-null},
  "weekly_used": ${weekly:-null},
  "live_attempted": $live_attempted,
  "fallback_reason": $rendered_fallback_reason,
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
claude_live_attempted=false
gemini_live_attempted=false
claude_fallback_reason=""
gemini_fallback_reason=""

resolve_provider_contract() {
    local provider="$1"
    local live_enabled="$2"
    local live_state_file="$3"
    local current_hourly="$4"
    local current_weekly="$5"
    local current_exhausted="$6"
    local env_prefix="$7"

    local source="unknown"
    local fallback_reason=""
    local live_attempted=false
    local hourly="$current_hourly"
    local weekly="$current_weekly"
    local exhausted="$current_exhausted"
    local live_hourly=""
    local live_weekly=""
    local live_exhausted=""
    local env_hourly_var="${env_prefix}_HOURLY_USED"
    local env_weekly_var="${env_prefix}_WEEKLY_USED"
    local env_exhausted_var="${env_prefix}_EXHAUSTED"
    local inline_env_present=""

    if [[ "$live_enabled" == "true" ]]; then
        live_attempted=true
        live_hourly="$(read_live_provider_metric "$provider" hourly_used "${env_prefix}_LIVE_HOURLY_USED" "$live_state_file")"
        live_weekly="$(read_live_provider_metric "$provider" weekly_used "${env_prefix}_LIVE_WEEKLY_USED" "$live_state_file")"
        live_exhausted="$(bool_value "$(read_live_provider_bool "$provider" exhausted "${env_prefix}_LIVE_EXHAUSTED" "$live_state_file")")"
        if [[ -n "$live_hourly" || -n "$live_weekly" || "$live_exhausted" == "true" ]]; then
            hourly="$live_hourly"
            weekly="$live_weekly"
            exhausted="$live_exhausted"
            source="live"
        else
            fallback_reason="live-status-unavailable"
        fi
    else
        fallback_reason="live-status-disabled"
    fi

    if [[ "$source" != "live" ]]; then
        inline_env_present="${!env_hourly_var:-}${!env_weekly_var:-}${!env_exhausted_var:-}"
        if [[ -n "$inline_env_present" ]]; then
            source="env"
        elif [[ -f "$quota_state_file" ]]; then
            source="file"
        else
            source="unknown"
        fi
    fi

    printf '%s|%s|%s|%s|%s|%s\n' "$hourly" "$weekly" "$exhausted" "$source" "$live_attempted" "$fallback_reason"
}

IFS='|' read -r claude_hourly claude_weekly claude_exhausted_flag claude_source claude_live_attempted claude_fallback_reason <<<"$(resolve_provider_contract "claude" "$claude_live_enabled" "$claude_live_state_file" "$claude_hourly" "$claude_weekly" "$claude_exhausted_flag" "CCH_CLAUDE")"
IFS='|' read -r gemini_hourly gemini_weekly gemini_exhausted_flag gemini_source gemini_live_attempted gemini_fallback_reason <<<"$(resolve_provider_contract "gemini" "$gemini_live_enabled" "$gemini_live_state_file" "$gemini_hourly" "$gemini_weekly" "$gemini_exhausted_flag" "CCH_GEMINI")"

cat <<EOF
{
  "claude": $(provider_json "claude" "$claude_hourly" "$claude_weekly" "$claude_exhausted_flag" "$claude_hourly_warn" "$claude_weekly_warn" "$claude_hourly_exhausted" "$claude_weekly_exhausted" "$claude_source" "$claude_live_attempted" "$claude_fallback_reason"),
  "gemini": $(provider_json "gemini" "$gemini_hourly" "$gemini_weekly" "$gemini_exhausted_flag" "$gemini_hourly_warn" "$gemini_weekly_warn" "$gemini_hourly_exhausted" "$gemini_weekly_exhausted" "$gemini_source" "$gemini_live_attempted" "$gemini_fallback_reason")
}
EOF
