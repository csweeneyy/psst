# F08 - Scheduling engine

**Why**
iOS caps pending local notification requests at 64 per app, system-wide, no workaround. Naive per-habit scheduling silently drops reminders.

**Acceptance**
- Never more than 64 pending requests
- Maintains a rolling window of roughly the next 48 hours
- Tops up on app launch, on background refresh, and on every notification response
- Unit test proves the cap holds with 20 habits at high frequency

**Notes**
Source: https://developer.apple.com/forums/thread/811171 (Apple DTS).
