# F51 - Stopping an alarm recorded nothing

**Why**
Reported: stopped an alarm on the Lock Screen, then opened the app and the
in-app takeover asked about it again.

`AlarmService.sync` built its intents with `let occurrenceID = UUID()`, a value
never written to the store. AlarmKit alarms recur, so one baked-in intent is
reused for every future firing and structurally cannot carry a real occurrence
id. The intent ran, looked for that row, found nothing, and returned silently.
The alarm tier had never recorded a single completion.

**Acceptance**
- An answer whose occurrence id matches nothing falls back to the habit's
  nearest pending nudge within 45 minutes
- An exact id still wins over the fallback
- Already answered nudges are never matched again
- The fallback does not reach across hours for something unrelated

**Status**
Done. Five tests in `AnswerMatchingTests`, against a real in-memory store.
