# F50 - Nudges do not read the same twice

**Why**
Requested: vary the buzz so it does not become background noise.

**What is actually possible**
Nothing, on the vibration. There is no public API at any layer for a
third-party app to set a notification's haptic pattern. `UNMutableNotificationContent`
has no haptic property, `UNNotificationSound` has no haptic member, AlarmKit
and ActivityKit expose only `AlertSound`, and CoreHaptics cannot run while the
app is suspended. The haptic is governed solely by the user's global
Settings > Sounds & Haptics > Haptics switch.

What CAN vary per notification: the sound file, the interruption level, and
the words.

**Acceptance**
- A habit can hold alternative phrasings, one per line
- One is chosen at random each time it fires, never repeating the previous
- Applies to all three tiers, plus snooze follow-ups and queued follow-ons
- The assistant can write variants via `update_habit`

**Status**
Done. Five tests.

**Open**
Custom sound rotation is possible (per-request `UNNotificationSound(named:)`,
under 30s, aiff/wav/caf in the bundle) but needs audio files worth shipping.
Not started; would need real sound design, not synthesised beeps.
