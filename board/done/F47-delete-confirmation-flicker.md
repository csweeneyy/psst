# F47 - Row vanished before the confirmation was answered

**Why**
`Button(role: .destructive)` inside `swipeActions` makes SwiftUI animate the
row out the instant a full swipe completes. Since the delete was gated behind
a confirmation, the row disappeared and then sprang back.

**Acceptance**
- Plain red button, no destructive role
- Row stays put until the user confirms, on both Home and Habits
- UI test asserts the row still exists while the alert is up

**Status**
Done.
