# F55 - One definition per decision

**Why**
Requested: make sure settings, habits and styling have a single source so tabs
cannot disagree.

**What was actually duplicated**
- The default habit tint `#007AFF` appeared in eight places, including the
  model's own default and the widget.
- The intensity colour mapping existed three times, and disagreed: the Habits
  row drew Gentle as faint grey while onboarding drew it green.
- The occurrence status symbol and colour existed twice, in Home and the
  calendar.
- The symbol and tint palettes lived inside `HabitSetupView`, so nothing else
  could reach them.

**Now**
`Shared/Types/HabitStyle.swift` owns the palettes, the defaults, and the
`Intensity.accent` and `OccurrenceStatus.symbol`/`.accent` mappings. Every
surface reads from it.

**Already single-source, verified rather than assumed**
Habit and occurrence data (one `ModelContainer`, and intents write through its
`mainContext`), scheduling (`SchedulingService`), stats (`HabitStatsService`),
notification category ids (`NotificationCategory`), colour parsing, and the
day-key format.

**Status**
Done.
