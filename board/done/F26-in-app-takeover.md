# F26 - Nudges that come due with the app open

**Why**
A nudge due while the app is foregrounded fires no notification, so it used to
pass silently, and overdue items sat in "Up next" where they did not belong.

**Acceptance**
- Pending occurrences whose time has passed move to a "Now" section
- A full screen cover takes over when one comes due, with Done and Later
- Right swipe removes any card

**Status**
Done. Swipe is covered by the UI smoke test. The takeover timer is not, since
it needs five seconds of wall clock to trigger.
