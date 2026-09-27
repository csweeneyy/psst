# F22 - Editing a habit had no visible effect

**Why**
Reported from the device: changing a habit's schedule on the Habits tab left
the old times sitting on the Home screen. `resync` materialised new
occurrences but never removed the ones the new plan had orphaned, so an edit
looked like it had silently failed.

**Acceptance**
- Future pending occurrences absent from the new plan are deleted
- Answered occurrences, past occurrences and pinned occurrences are never
  touched
- Editing habit A does not disturb habit B
- Matching is minute-granular, so sub-second drift is not treated as a new nudge

**Status**
Done. Decision extracted to `SchedulingService.stale` so it is testable without
SwiftData. Five regression tests in `PsstTests/ReconciliationTests.swift`.
