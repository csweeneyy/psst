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
Verified in production: 20/20 eval, tools cover every action the user can take, destructive calls gated behind a confirmation.
