# F33 - The assistant thought Saturday was Sunday

**Why**
"Create a habit called test at 8:27 pm today" produced `weekdays: [1]`, Sunday.
The app sent `ISO8601DateFormatter().string(from: .now)`, which defaults to
GMT. At 8:26 PM Eastern on a Saturday that is `2026-09-27T00:26:29Z`, so the
model read the UTC day and was right about the wrong data.

**Acceptance**
- The app sends a local description including the weekday name and the exact
  weekday number the schedule tool expects
- The system prompt forbids inferring the day from anything else
- Regression tests cover the New York rollover and all seven weekday numbers

**Status**
Done. Verified against the deployed Worker: same request now returns
`weekdays: [7]`.
