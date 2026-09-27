# F14 - Habit stats and visualization

**Why**
Second tab needs to be worth visiting. Completion rate, streaks, time-of-day heatmap.

**Acceptance**
- Per-habit completion rate over 7 and 30 days
- Current streak
- Reveals which times of day actually get answered

**Status**
Completion rate and streaks are computed and shown on the Habits tab. The time-of-day heatmap from the Acceptance block is not built; `HabitStatsService.hourlyResponseRate` exists but nothing renders it.
