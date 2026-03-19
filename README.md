# ClaudinCodexHeavy

Cost-first Claude Code plugin focused on one behavior:

- If the user's prompt ends with `ALL`, treat that as an explicit opt-in to full quota-aware orchestration.
- Prefer `Codex(gpt-5.4)` when Claude/Gemini quota is high, unknown, or exhausted.
- Fall back conservatively instead of blocking execution.

## What It Ships

- One auto-activating skill for trailing `ALL`
- One manual command: `/cch:auto`
- One lightweight orchestrator: [`scripts/orchestrate.sh`](./scripts/orchestrate.sh)
- One quota-state adapter: [`scripts/helpers/provider-quota-status.sh`](./scripts/helpers/provider-quota-status.sh)

## v1 Behavior

- `ALL` at the end of a prompt triggers quota-aware orchestration
- Unknown quota state uses `Codex(gpt-5.4)` first
- Gemini exhaustion hands work to GPT/Codex
- Claude exhaustion degrades to Codex-only mode
- Gemini detection is best-effort in v1

## Configuration

Default config template:
- [`templates/config.json.template`](./templates/config.json.template)

Runtime config lookup order:
1. `CCH_CONFIG`
2. `~/.claude/plugins/data/cch-claudin-codex-heavy/config.json`
3. Built-in defaults

Quota state lookup order:
1. `CCH_QUOTA_STATE_FILE`
2. `quota_state_file` in config
3. `~/.claude/plugins/data/cch-claudin-codex-heavy/quota-state.json`

### Example quota-state file

```json
{
  "claude": {
    "hourly_used": 82,
    "weekly_used": 71,
    "exhausted": false
  },
  "gemini": {
    "hourly_used": 24,
    "weekly_used": 95,
    "exhausted": true
  }
}
```

Environment variables can override file values:

- `CCH_CODEX_MODEL`
- `CCH_GEMINI_MODEL`
- `CCH_CLAUDE_HOURLY_USED`
- `CCH_CLAUDE_WEEKLY_USED`
- `CCH_CLAUDE_EXHAUSTED`
- `CCH_GEMINI_HOURLY_USED`
- `CCH_GEMINI_WEEKLY_USED`
- `CCH_GEMINI_EXHAUSTED`
- `CCH_SKIP_PROVIDER_EXEC=1` to skip external Codex/Gemini calls

## Install Into Claude

Add marketplace from local path:

```bash
claude plugin marketplace add /home/ksoe/ClaudinCodexHeavy
claude plugin install cch@claudin-codex-heavy --scope user
```

After installation:

- Append `ALL` to the end of a prompt for auto orchestration
- Or run `/cch:auto ...`

## Validate

```bash
make test
claude plugin validate .claude-plugin/plugin.json
```

