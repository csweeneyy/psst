# F16 - Push-driven dynamic rescheduling

**Why**
Right now the brain only recalculates when the app is opened or a notification is answered. Background refresh is opportunistic, not guaranteed.

**Acceptance**
- Worker holds the schedule and sends APNs at the right moment
- App never needs to be opened for the schedule to adapt

**Notes**
Requires an Apple Developer Program membership for APNs keys.
