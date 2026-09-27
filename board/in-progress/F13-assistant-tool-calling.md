# F13 - Assistant tool-calling

**Why**
This is the dynamic part. The model must be able to actually change the schedule, not just talk about it.

**Acceptance**
- Tools: create_habit, update_schedule, set_intensity, snooze, pause_habit, delete_habit
- Returns a typed mutation list the app applies locally
- Rejects a cadence tighter than the habit's declared minimum interval

**Notes**
The 'do not nag every minute' rule lives here as a hard floor per habit, not as a prompt instruction.

**Status**
Worker is deployed and provider-agnostic. Anthropic plus any OpenAI-compatible
endpoint (OpenRouter, Fireworks, DeepSeek, Groq, OpenAI) are supported by
`src/services/providers/`. `MODEL_CHAIN` is an ordered fallback list; a model
loses the turn only when it observably fails, never on prediction.

Blocked on one API key secret. `/health` reports `{"ok":false,"chain":[]}`
until then, which is correct behaviour and was verified against production.

The 15-case scorer in `eval/` is written and typechecks. It cannot be run
until a key exists.
