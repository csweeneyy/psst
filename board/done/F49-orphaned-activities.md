# F49 - Deleted habits left their Lock Screen cards behind

**Why**
Edge case audit. Deleting a habit removed its rows but not its scheduled Live
Activities, so a card could still fire for something the user could no longer
see.

**Acceptance**
- Every resync ends activities whose habit no longer exists

**Status**
Done.
