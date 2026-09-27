# F46 - Simultaneous nudges become a queue

**Why**
First attempt just shoved colliding nudges 2 minutes apart, per tier, and left
AlarmKit out entirely. Arbitrary, and an alarm landing on the same minute as a
Lock Screen card is the same problem as two banners.

**Behaviour**
One nudge keeps the moment its habit asked for. The rest are staked out behind
it 45 seconds apart, tagged with a shared group and a position. Resolved across
every tier at once.

Answering one pulls the next forward to arrive in 3 seconds, so a collision
reads as a queue rather than a stutter. With the app open there is no
notification to receive, so the next takeover is raised directly instead.

**Why nothing can be missed**
Every nudge in a group is pre-scheduled with the operating system at its own
staggered slot before any of this. The queue only ever makes one arrive
*sooner*. If the app is never run again, they all still fire. There is no path
where a collision drops a nudge, which is the property the tests assert.

**Acceptance**
- A three-way collision yields three nudges, one on time, all ≥45s apart
- Alarm and notification tiers collide with each other, not just within a tier
- A single habit's own cadence is never treated as a collision
- Queued follow-ons survive a resync

**Status**
Done. Four tests in `SchedulingServiceTests`.
