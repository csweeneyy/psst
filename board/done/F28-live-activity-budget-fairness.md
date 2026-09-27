# F28 - One habit consumed every Lock Screen slot

**Why**
Found in device logs, not reported. A posture habit configured to fire every 6
minutes inside a 30 minute window took all 3 Live Activity slots, six minutes
apart, for the next day. Every other habit silently lost its Lock Screen card.

**Acceptance**
- Live Activity slots allocated with the same fair-share rule as the 64
  notification slots
- A chatty habit cannot starve a once-a-day habit
- Regression test in `SchedulingServiceTests`

**Status**
Done. 19/19 unit tests pass.
