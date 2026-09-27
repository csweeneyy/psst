# F27 - Chat opens fresh

**Why**
Reopening chat showed yesterday's conversation. The transcript is working
memory, not a history feature.

**Acceptance**
- The view starts empty every time
- Turns are still written to SwiftData and D1
- The last 16 stored turns are still sent to the model as context

**Status**
Done.
