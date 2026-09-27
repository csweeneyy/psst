# F53 - Lock the phone until the habit is done

Shields every other app while an alarm-tier habit is due. One tap on the block
screen marks it done and gives the phone back.

## How it is built

Apple splits this across three processes and there is no way to collapse them.

|Target|Extension point|Job|
|---|---|---|
|`PsstMonitor`|`com.apple.deviceactivity.monitor-extension`|Woken at the habit's time with the app not running. Raises the shield.|
|`PsstShield`|`com.apple.ManagedSettingsUI.shield-configuration-service`|Draws the block screen.|
|`PsstShieldAction`|`com.apple.ManagedSettings.shield-action-service`|Owns the buttons.|

The app's side is `LockdownService`: `.individual` authorization, keeping one
`DeviceActivitySchedule` per locking habit, and lowering a shield when the
habit is completed somewhere else.

`shield.applicationCategories = .all(except: [])` covers every category on the
device. Psst is exempt automatically, which is what keeps the unlock
reachable.

## Decisions worth keeping

- **The extensions compile two files, not the shared layer.** A shield
  extension that is slow to answer is replaced by the system's own generic
  blocker, so the weight of SwiftData, ActivityKit and AlarmKit would have been
  paid for on screen. `Lockdown.appGroup` is now the single owner of the app
  group id so those two files stand alone.
- **Alarm tier only.** Shielding the phone for a gentle reminder is a wild
  mismatch between what you asked for and what you got, and the tiers exist so
  that never happens.
- **Ninety minute ceiling, enforced by `intervalDidEnd`.** A deleted habit, a
  crashed extension or a schedule change must never leave a phone bricked.
- **Completions cross the process boundary as ids in shared defaults.** The
  shield extension cannot reach SwiftData. It records the id and lowers the
  shield immediately rather than trying to wake the app, which is slow and can
  fail; the app settles up on its next foreground in
  `drainLockdownCompletions`. Without that the phone unlocks but the habit
  still reads as missed, which is the worst of both.
- **A "Try the lockdown now" button on the habit.** Otherwise the only way to
  see it is to wait for the scheduled time, which makes it impossible to check
  or to show anyone.

## What it cannot do

- Home Screen, Settings, and anything in Screen Time's Always Allowed are
  never shieldable. This is a commitment device, not a cage.
- Under individual authorization the user can revoke it in Settings or delete
  the app.
- `com.apple.developer.family-controls` is a managed capability. Development
  signs fine; TestFlight and the App Store need Apple's approval, requested by
  the Account Holder.
- App Review guideline 4.10 forbids monetising Screen Time APIs, which
  constrains any paid version.

## Signing note

`xcodebuild -allowProvisioningUpdates` failed with `No Accounts` and
`doesn't support the Family Controls (Development) capability` until an Apple
ID was added in Xcode. Signing in there registers the capability on the App ID
and downloads the regenerated profile in one step; doing it on the developer
portal website only does the first half.

Verified: all four binaries carry the entitlement.

    codesign -d --entitlements - Psst.app/PlugIns/PsstShield.appex
