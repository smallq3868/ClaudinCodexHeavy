---
description: Automatically activate when the user's request ends with the literal suffix `ALL`. Use for full quota-aware orchestration with hard ALL precedence, hybrid quota truth, category-aware routing, Codex(gpt-5.4)-first fallback, Gemini best-effort handling, and Codex-only degrade when Claude is exhausted.
---

# ALL Suffix Orchestrator

When the user's message ends with `ALL`, treat that suffix as an explicit opt-in signal for full orchestration.

## Execution Contract

1. Do not ask clarification questions before orchestration.
2. Run:

```bash
cd "${CLAUDE_PLUGIN_ROOT}" && ./scripts/orchestrate.sh auto "<raw user message>"
```

3. Let the script strip the trailing `ALL`.
4. Present the routing summary first.
5. Ensure the routing summary includes:
   - selected category
   - quota truth source (`live|env|file|unknown`)
   - fallback reason when present
6. If the script returns provider outputs, synthesize them succinctly for the user.
7. If quota is unknown, accept the conservative Codex-first fallback.
8. If Gemini is exhausted, let GPT/Codex take over that work.
9. If Claude is effectively exhausted, accept Codex-only degraded mode.

## Output Shape

- Routing mode
- Selected category
- Quota truth source
- Fallback reason when applicable
- Why that mode was selected
- Which providers ran or were skipped
- Final answer or next-step output from the provider runs
