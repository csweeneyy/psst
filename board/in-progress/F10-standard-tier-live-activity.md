# F10 - Standard tier, Live Activity

**Why**
Buttons visible on the Lock Screen with no long press. This is the tier most habits should use.

**Acceptance**
- `Button(intent:)` bound to a `LiveActivityIntent` renders Done and Snooze inline
- Tapping completes without opening the app
- Activity auto-dismisses 15 minutes after the window closes, not 4 hours

**Notes**
8 hour active limit. Concurrency limit is undocumented, so wrap `Activity.request` in do/catch and degrade to the Gentle tier on failure.

**Status**
Code is written and compiles. Cannot be verified in the simulator: scheduled Live Activities need a real device. Verify by installing on the iPhone 17 and creating a Standard-tier habit due in a few minutes.
