# F56 - Every habit appeared to be gone

**Reported**
"my app isn't filled anymore did you delete everything"

**Nothing was deleted.** The database on the device held 9 habits, 54
occurrences and 17 chat messages the whole time. Verified by pulling
`default.store` off the device and counting rows before changing any code.

**Cause**
The app group container is protected by iOS data protection and cannot be
opened while the phone is locked. When a nudge fired on a locked phone, iOS
launched the app process in the background to run the intent, the store could
not be opened, and `PsstStore.container()` quietly fell through to an
in-memory container.

`PsstStore.shared` was a `static let`, so that empty container was cached for
the lifetime of the process. Unlocking the phone and opening the app reused
the same process, which was still holding the scratch store.

Evidence that pinned it down:
- `default.store-shm` touched at 09:38, but no write to the store or WAL since
  02:43: something opened the file and then gave up.
- No `Library/Application Support` in the app container at all, so the
  on-disk fallback never ran either.
- No crash report, so the process had launched normally.

**This was my bug.** The fallback chain was defensive code that turned a
temporary, recoverable condition into what looked exactly like total data
loss, which is the worst possible way to fail.

**Acceptance**
- A degraded container is never cached; every access retries
- `isDegraded` is published, and nothing writes while it is true: intents,
  snooze, the queue, the widget snapshot and `resync` all refuse
- `resync` in particular must refuse, or it would conclude there are no habits
  and cancel every real notification
- An empty list and a failed load no longer look identical: Home shows
  "Could not open your data. Unlock your phone and reopen Psst."
- Existing habits skip first-run, so a reinstall cannot hide real data behind
  an onboarding screen

**Status**
Fixed and verified on device: the store was written again immediately after
the new build launched.
