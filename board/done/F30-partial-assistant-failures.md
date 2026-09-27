# F30 - Half-applied changes reported as success

**Why**
"Make the gym one an alarm and make it everyday at 6" changed the intensity and
nothing else, and the assistant still replied "Done". The schedule tool call
had failed validation and was dropped silently.

**Acceptance**
- Worker returns a `warnings` array for every rejected tool call
- Chat renders them in orange under the reply
- Eval case with the exact failing sentence

**Status**
Done. The underlying validation bug was already fixed; this makes the class of
failure impossible to miss in future. Eval 15/16.
