# F52 - Rescheduled nudges did not fire

**Why**
Reported: moved two nudges to one minute out from the Home editor, locked the
phone, and neither fired. Opening the app produced both takeovers about a
minute late.

Two causes, both about the app being suspended mid-work:

1. `NotificationService.sync` removed every pending request and then re-added
   them. Suspend the app inside that window and it owns no scheduled
   notifications at all.
2. `move` kicked off a full resync and returned. Resync touches dozens of
   system calls and takes seconds; locking the phone immediately suspends it
   before the work lands.

**Acceptance**
- `sync` diffs: removes only what the plan no longer wants, adds only what is
  missing, and adds before it removes
- Request identifiers are deterministic, so a re-sync recognises its own work
- `resync` holds a background task assertion so it finishes after a lock
- Moving a nudge schedules its alert immediately, ahead of the slow path

**Status**
Done. Needs a device pass: move a nudge, lock at once, confirm it fires.
