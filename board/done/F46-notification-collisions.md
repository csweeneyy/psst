# F46 - Two habits landing on the same minute

**Why**
Edge case, found by asking rather than by hitting it. 9 AM is a popular time.
Three banners arriving together is one interruption the user cannot triage,
and three simultaneous Live Activities would exhaust the undocumented
concurrency limit outright.

**Acceptance**
- Nudges from different habits are pushed at least 2 minutes apart
- The earliest keeps the time the user actually chose
- A single habit's own cadence is never touched: that spacing is its
  `minIntervalMinutes`, which the user set deliberately

**Status**
Done, two regression tests.

**Known gap**
AlarmKit schedules recurring alarms directly from each habit, not from the
plan, so two `alarm` tier habits at the same clock time still both fire. Rare
by construction (the limit is 8 alarms) and left alone rather than refactored
speculatively.
