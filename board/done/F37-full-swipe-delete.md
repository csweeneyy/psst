# F37 - Full swipe deletes, on both tabs

**Why**
The gesture required swiping and then pressing a button. And the confirmation
was a `confirmationDialog`, which iOS anchors to the bottom of the screen no
matter which row you swiped.

**Acceptance**
- `allowsFullSwipe: true`, gesture alone reaches the confirmation
- Centred `.alert`, like Notes, not a bottom sheet
- Habits page gets the same gesture, which required converting it to a real
  `List`

**Status**
Done, verified in the UI smoke test.
