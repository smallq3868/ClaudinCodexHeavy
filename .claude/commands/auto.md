---
description: Trigger quota-aware cost-first orchestration manually. Uses the same hard ALL-suffix semantics, hybrid quota truth, category-aware routing, and Codex(gpt-5.4)-first fallback as the automatic skill.
---

# /cch:auto

Run cost-first quota-aware orchestration manually.

## Execution Contract

1. Use the rest of the user request as the prompt body.
2. Run:

```bash
cd "${CLAUDE_PLUGIN_ROOT}" && ./scripts/orchestrate.sh auto "<user request>"
```

3. Show the routing summary before any provider output.
4. In the summary, surface:
   - selected category
   - quota truth source (`live|env|file|unknown`)
   - fallback reason when applicable
5. Summarize the result for the user.
