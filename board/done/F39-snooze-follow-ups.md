# F39 - Snooze now actually brings the nudge back

**Why**
"Later" marked the occurrence skipped and stopped. It was a silent way to
cancel a reminder, which is the opposite of an accountability app.

**Acceptance**
- Snoozing schedules a real follow-up 10 minutes out
- Capped at 3 snoozes; three "laters" is an answer
- The follow-up survives a resync, so the 64-slot rebuild cannot wipe it
- Every path routes through `FollowUp`: Lock Screen, alarm, notification
  action, in-app row, takeover

**Status**
Done.
