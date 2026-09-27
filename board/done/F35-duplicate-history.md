# F35 - Assistant thought you sent the message twice

**Why**
Reported as a mic bug. It was not. D1 showed exactly one user row, but
`storedHistory()` ran *after* inserting the new turn, so the model received
the same sentence twice: once inside `history`, once as `message`. It replied
"since you sent it twice".

**Acceptance**
- History is snapshotted before the new turn is stored

**Status**
Done.
