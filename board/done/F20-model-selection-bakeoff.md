# F20 - Model selection bakeoff

**Why**
The assistant's only hard requirement is reliable tool calling with a nested
JSON schema. Cheap models often fail exactly there. Guessing which one works
is how you ship a broken feature; measuring takes twenty minutes.

**Acceptance**
- `bun run eval` scores a named model over 15 real phrasings
- At least 4 candidates scored, with pass rate, median latency and token cost
- `MODEL_CHAIN` pinned to the cheapest model that scores 15/15, with one
  stronger model behind it as the escalation target

**Status**
Settled. Chain is deepseek-v4-flash-0731 then v4.1-flash then v4-pro, chosen by measurement. 20/20 at $0.021/$0.320 per 1M.
