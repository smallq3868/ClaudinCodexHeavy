---
description: Trigger quota-aware cost-first orchestration manually. This is an explicit entrypoint and does not require a trailing ALL suffix. It uses the same hybrid quota truth, Claude-led intent inference, category-aware routing, and Codex(gpt-5.4)-first fallback as the automatic ALL-trigger path.
---

# /cch:auto

Run cost-first quota-aware orchestration manually.

Important:
- `/cch:auto` itself is the explicit trigger.
- A trailing `ALL` is optional here, not required.
- `ALL` remains required only for passive natural-language auto activation.

## Execution Contract

1. Use the rest of the user request as the prompt body.
2. Run:

```bash
CCH_TARGET_CWD="$PWD" "${CLAUDE_PLUGIN_ROOT}/scripts/orchestrate.sh" auto "<user request>"
```

3. Do not reject the command if the prompt body does not end with `ALL`.
4. Show the routing summary before any provider output.
5. In the summary, surface:
   - selected category
   - quota truth source (`live|env|file|unknown`)
   - fallback reason when applicable
   - higher-order purpose
   - intent count
6. If intent inference is active, preserve the higher-order purpose across all delegated intent results.
7. Summarize the result for the user.
