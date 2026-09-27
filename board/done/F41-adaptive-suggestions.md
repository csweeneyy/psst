# F41 - Adaptive scheduling

**Why**
The original pitch was a schedule that adapts. Until now the app only did what
it was told.

**Acceptance**
- `ScheduleAdvisor` turns the response heatmap into at most one suggestion
- Every rule demands evidence: 8 answered nudges overall, 3 per hour
- Window tightening only fires if a reliably-answered hour survives the trim
- One tap applies it
- Surfaced both in the detail sheet and the weekly review

**Status**
Done. Five tests, including one proving it stays quiet on healthy habits and
one proving it does not suggest trimming a window where nothing works.
Verified on seeded data: it found "100% at 11 AM, 0% at 6 PM, move to 11 AM"
without being told the pattern existed.
