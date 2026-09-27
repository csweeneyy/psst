# F53 - Lock the phone until the habit is done

**Why**
Requested for the morning routine: something more severe than Alarm, where
other apps cannot be used until a flow is completed.

**Feasibility, not yet verified**
Three candidate mechanisms, in descending order of how likely they are to
work. None has been confirmed against the SDK yet; that is the first task.

1. **`FamilyControls` + `ManagedSettings` + `DeviceActivity`.** Apple's Screen
   Time API. `ManagedSettingsStore.shield.applications` can shield apps, and
   a `DeviceActivitySchedule` can apply a shield over a window. A
   `ShieldActionExtension` can define what dismissing the shield does, which is
   where the "complete an action to unlock" flow would live. Needs the
   `com.apple.developer.family-controls` entitlement, which is a **managed
   capability requiring Apple approval**, and the individual (non-guardian)
   authorization flow. This is the real answer if the entitlement is
   obtainable.
2. **Guided Access.** Locks the device to one app, but it is user-initiated
   from Settings and cannot be triggered by an app. Wrong shape.
3. **A persistent full-screen takeover in our own app.** Already effectively
   built. Does nothing once you leave the app, which is the entire point.

**Open questions**
- Is the family-controls entitlement realistically obtainable for a personal
  or indie app? Apple's approval bar is unpublished.
- Does shielding require the user to pick apps through `FamilyActivityPicker`,
  which returns opaque tokens rather than bundle ids?
- Can a shield be lifted programmatically the instant a habit is completed?

**Acceptance**
To be defined after the feasibility pass.

**Status**
Queued, not started, at the user's instruction. Start with research: confirm
the entitlement path before writing anything.
