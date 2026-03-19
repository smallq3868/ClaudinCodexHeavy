# ClaudinCodexHeavy

Cost-first Claude Code plugin focused on one behavior:

- If the user's prompt ends with `ALL`, treat that as an explicit opt-in to full quota-aware orchestration.
- Prefer `Codex(gpt-5.4)` when Claude/Gemini quota is high, unknown, or exhausted.
- Fall back conservatively instead of blocking execution.

Phase 1 is intentionally `policy-only`.
It defines how routing should work by category without importing broad workflow families yet.

Phase 2 adds `Claude-led intent inference`.
When `ALL` is present, Claude may infer one higher-order purpose and decompose the request into up to 3 ordered intents, then route each intent by category.

## What It Ships

- One auto-activating skill for trailing `ALL`
- One manual command: `/cch:auto`
- One lightweight orchestrator: [`scripts/orchestrate.sh`](./scripts/orchestrate.sh)
- One quota-state adapter: [`scripts/helpers/provider-quota-status.sh`](./scripts/helpers/provider-quota-status.sh)

## v1 Behavior

- `ALL` at the end of a prompt triggers quota-aware orchestration
- `ALL` precedence is a hard policy, not a config option
- Unknown quota state uses `Codex(gpt-5.4)` first
- Gemini exhaustion hands work to GPT/Codex
- Claude exhaustion degrades to Codex-only mode
- Gemini detection is best-effort in v1
- Category routing is explicit for:
  - implementation
  - research
  - verification
  - security
  - debate
  - documentation
  - planning
- Claude can infer one higher-order purpose and split the request into up to 3 intents
- Each intent must stay inside that single higher-order purpose

## Phase 1 Category Policy

The phase-1 policy table is meant to be stored in config, not hardcoded only in shell logic.

Target category defaults:

- `implementation`
  - leader: `claude`
  - executor: `codex:gpt-5.4`
  - fallback: `codex:gpt-5.4`
  - quota bias: `codex-first`
- `research`
  - leader: `gemini`
  - executor: `gemini:default`
  - fallback: `codex:gpt-5.4`
  - quota bias: `gemini-first`
- `verification`
  - leader: `claude`
  - executor: `codex:gpt-5.4`
  - fallback: `codex:gpt-5.4`
  - quota bias: `codex-first`
- `security`
  - leader: `claude`
  - executor: `codex:gpt-5.4`
  - fallback: `gemini:default`
  - quota bias: `codex-first`
- `debate`
  - leader: `claude`
  - executor: `codex+gemini`
  - fallback: `codex:gpt-5.4`
  - quota bias: `balanced`
- `documentation`
  - leader: `claude`
  - executor: `claude`
  - fallback: `codex:gpt-5.4`
  - quota bias: `claude-first`
- `planning`
  - leader: `claude`
  - executor: `claude`
  - fallback: `codex:gpt-5.4`
  - quota bias: `claude-first`

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

Hybrid quota truth contract:

- prefer `live` provider status when available
- otherwise fall back to `env` or `file`
- if nothing is available, report `unknown`

Target helper fields:

- `live_attempted`
- `source` = `live|env|file|unknown`
- `fallback_reason`
- `high`
- `exhausted`

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

## Category Resolution Contract

Phase 1 should expose one explicit runtime category-resolution path with this conceptual interface:

```text
resolve_category(
  raw_prompt: string,
  command_surface: string,
  explicit_command: boolean
) -> category
```

Accepted categories:

- `implementation`
- `research`
- `verification`
- `security`
- `debate`
- `documentation`
- `planning`

Resolution rules:

1. hard `ALL` policy applies before configurable routing
2. explicit command surface may influence category choice
3. prompt heuristics refine category when command surface is absent or ambiguous
4. unknown category defaults to `implementation`

## Phase 2 Intent Inference

Phase 2 extends category routing into intent bundles.

Conceptual contract:

```text
infer_intent_bundle(raw_prompt) -> {
  higher_order_purpose: string,
  intents: [
    { order: number, intent: string, category: category }
  ],
  truncated_to_max: boolean,
  authority: "claude"
}
```

Rules:

1. Claude is the intent inference authority
2. The request may be decomposed into at most 3 intents
3. All intents must remain inside one Claude-inferred higher-order purpose
4. The system may reassign work by intent, but may not distort the user's core request

For local testing, the runtime also supports:

- `CCH_INTENT_BUNDLE_JSON`
- `CCH_DISABLE_CLAUDE_INTENT_INFERENCE=1`

## Install Into Claude

Add marketplace from local path:

```bash
claude plugin marketplace add /home/ksoe/ClaudinCodexHeavy
claude plugin install cch@claudin-codex-heavy --scope user
```

After installation:

- Append `ALL` to the end of a prompt for auto orchestration
- Or run `/cch:auto ...`
- Expect routing summaries to eventually include:
  - selected category
  - quota truth source
  - fallback reason when applicable
  - higher-order purpose
  - intent count

## Validate

```bash
make test
claude plugin validate .claude-plugin/plugin.json
```
