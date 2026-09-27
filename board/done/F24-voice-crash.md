# F24 - Voice input crashed the app

**Why**
Reported from the device. Tapping the mic killed the process.

**Acceptance**
- Permissions requested before the audio session is configured
- Input format read only after the session is active, and validated
- Recognition and tap callbacks marshalled to the main actor
- Repeated start/stop does not crash

**Status**
Done. Three separate faults, any one of which was fatal. Not yet exercised on
device; the simulator has no microphone input worth trusting.
