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
Code is written and compiles. AlarmKit needs a real device and the alarm permission prompt. Verify by creating an Alarm-tier habit and confirming it fires through silent mode.
