# F11 - Alarm tier, AlarmKit

**Why**
For habits that genuinely must not be missed. Overrides Focus and silent mode.

**Acceptance**
- `AlarmConfiguration` with `stopIntent` (Done) and `secondaryIntent` (Snooze)
- `NSAlarmKitUsageDescription` present, authorization requested at first use
- Weekly recurrence maps to habit cadence

**Notes**
iOS 26.0+. No Apple entitlement required. App Review posture for a habit app is unconfirmed; irrelevant while this is a personal build.

**Status**
Verified on device: the alarm fires through silence, and stopping it now records a completion (see F51).
