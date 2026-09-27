# F57 - Preview and snooze ignored the habit's tier

**Reported**
"it's set to alarm but preview nudge still just gave a normal noti"
"snoozes don't follow their noti pattern either"

**Cause**
Three separate paths delivered a plain banner regardless of tier:

1. `NudgeCoordinator` folded pinned occurrences into the plan and routed
   `.alarm` and `.gentle` to `plan.notifications`. A preview creates a pinned
   occurrence, so even when the AlarmKit alarm was scheduled correctly, the
   next resync added a banner on top. "Tap to log it" was that banner.
2. `FollowUp.schedule` always built a notification. I had commented this as
   intentional, on the grounds that getting the nudge delivered beat honouring
   the tier. That reasoning is wrong for a snooze: snoozing an alarm silently
   downgraded the one thing the user said they could not miss.
3. `NudgeQueue` did the same for follow-ons, where the reasoning does hold,
   because a follow-on lands three seconds out.

**Now**
One function, `NudgeDelivery.deliver(habit:occurrenceID:at:)`, used by the
preview, snooze follow-ups, queue follow-ons, hand-moved nudges and pinned
occurrences. It dispatches on the habit's tier and degrades only when the API
genuinely cannot accept the date, reporting the reason rather than silently
sending a banner.

`AlarmService` and `LiveActivityService` moved to `Shared` so intent code can
reach them. Preview delay raised from 10s to 30s: neither AlarmKit nor a
scheduled Live Activity will accept a date closer than that.

**Acceptance**
- Previewing an Alarm habit produces an alarm, not a banner
- Snoozing an Alarm habit produces an alarm ten minutes later
- A degrade names the tier and the reason
- Gentle never counts as a degrade

**Status**
Fixed. Four tests in `NudgeDeliveryTests`. Needs a device pass on the alarm
preview specifically.
