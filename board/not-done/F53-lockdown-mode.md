# F53 - Lock the phone until the habit is done

**Verdict: buildable, and not a one-hour job.** Researched against Apple's
documentation rather than guessed.

## It works

A third-party app can shield other apps behind a custom "complete this to
unlock" screen, for the user's own device, with no parent/child relationship.

- **`AuthorizationCenter.requestAuthorization(for: .individual)`**, iOS 16+,
  still present in the iOS 26 SDK. The user gets an alert and authenticates
  with Face ID. No family setup.
  <https://developer.apple.com/documentation/familycontrols/authorizationcenter>
- **`ManagedSettingsStore.shield.applications`** takes a `Set<ApplicationToken>`
  chosen through `FamilyActivityPicker`. Opaque tokens, not bundle ids, and
  capped at 50.
  <https://developer.apple.com/documentation/managedsettings/shieldsettings/applications-swift.property>
- **`shield.applicationCategories = .all(except:)`** is the closest thing to a
  total lockdown. Our own app is automatically exempt.
  <https://developer.apple.com/documentation/managedsettings/shieldsettings/applicationcategories-swift.property>
- **`DeviceActivityMonitor`** applies the shield on a schedule with the app not
  running, which is what makes a 7am morning routine work.
  <https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor>
- **`ShieldConfigurationExtension` + `ShieldActionExtension`** own the screen
  the user hits and what its buttons do. Apple's own iOS 26.4 example for the
  new submenu items is a "complete homework to unlock" flow, which is exactly
  this shape.
  <https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration/secondarybuttonsubmenuitems>

## The costs

- **`com.apple.developer.family-controls` is a managed capability.** Local
  development works, but TestFlight and the App Store require Apple's
  approval, requested by the Account Holder through Capability Requests.
  Apple publishes no approval criteria.
  <https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement>
- **Two new extension targets**, each needing the entitlement separately.
- **App Review guideline 4.10 forbids monetising Screen Time APIs.** Not a
  problem for a personal build; it is a problem for any paid version.
- Under individual authorization the user can revoke it in Settings, or just
  delete the app. It is a commitment device, not a prison.
- Home Screen, Settings, and anything in Screen Time's "Always Allowed" can
  never be shielded.

## Why it was not built today

One hour before a demo is the wrong moment to add a managed entitlement and
two extension targets to a working, signed build. A signing failure would have
cost the demo. This is the next thing to build, not the last thing.

**Acceptance**
- `.individual` authorization requested from a setting on the habit
- A per-habit "Lock me out" toggle, alarm tier only
- `DeviceActivityMonitor` shields at the habit's scheduled time
- The shield screen offers one action that marks the habit done and lifts it
- Shield lifts immediately when the habit is completed anywhere else

**Status**
Researched, not started.
