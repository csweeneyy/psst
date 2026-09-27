# F29 - "Nothing due today" looked like a broken app

**Why**
Reported as "the notification didn't fire when locked". It had not fired
because the habit's active window had already passed; the next one was the
following evening. The app gave no way to know that.

**Acceptance**
- `SchedulingService.nextFireTime` looks 8 days ahead, past the scheduler's
  48 hour materialization horizon
- The empty state names the habit and when it next fires
- If no habit fits its own hours and days, it says so

**Status**
Done.
