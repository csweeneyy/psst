# F38 - Answering on the Lock Screen still raised the takeover

**Why**
Reported: pressed Done, saw "Logged", unlocked, and the full screen nudge
appeared anyway.

`OccurrenceWriter` wrote through a freshly constructed `ModelContext`. That
saves to the same store, but the running app's `@Query` was holding a stale
object graph from `mainContext`, so the occurrence still looked pending.

**Acceptance**
- Intents write through `PsstStore.shared.mainContext`, the exact context
  SwiftUI hands views
- The takeover clears itself if its occurrence stops being pending
- Returning to foreground re-reads before deciding anything is owed

**Status**
Done. Needs a device pass to confirm.
