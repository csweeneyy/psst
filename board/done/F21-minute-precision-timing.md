# F21 - Minute precision timing

**Why**
Every time control snapped to 15 or 30 minute increments, which made it
impossible to aim a notification at a specific minute. That is exactly what you
need when you are trying to catch one firing.

**Acceptance**
- Window start/end, and every fixed time, use `DatePicker(.hourAndMinute)`
- Interval stepper uses adaptive steps rather than a flat 15
- A single nudge can be moved to an exact minute from the Home screen
- `MinuteOfDayTests` proves the conversion round trips at minute precision

**Status**
Done. Verified in the simulator and shipped to the device.
