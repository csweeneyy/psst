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
Harness written (`worker/eval/cases.ts`, `worker/eval/run.ts`). Blocked on an
API key. Candidate list: GLM 5.3 Flash, DeepSeek V4.1 Flash, GPT OSS 120B,
Nemotron 3.5 Lightning 30B, with Claude Sonnet 4.5 as the control.
