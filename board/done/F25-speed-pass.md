# F25 - Speed pass

**Why**
"The entire app needs to be fast." Chat took about a second to reach the
keyboard, day toggles lagged, Live Activity buttons felt delayed.

**Acceptance**
- Chat opens already focused, with no `@Query` on the presentation path
- `.snappy` motion replaces springs with overshoot
- Card shadows removed (two offscreen passes per card, dozens on screen)
- Live Activity resolution is one `end` call, not `update` then `end`
- The intent repaints the card before it opens the store

**Status**
Done. Keyboard-on-open is asserted in the UI smoke test. The Live Activity
latency fix is reasoned, not measured, and needs a device check.
