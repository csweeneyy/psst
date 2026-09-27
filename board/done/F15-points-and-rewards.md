# F15 - Points and rewards

**Why**
Deferred by the user to post-MVP.

**Acceptance**
- Not started. Revisit after the notification tiers are proven.

**Status**
Done. A habit is worth `dailyPoints` **per day**, shared across however many
times it fires, so scheduling more nudges cannot inflate a score. Priority
picks the value: Low 5, Normal 10, High 25. Streaks multiply in weekly steps
of 0.25, capped at double.

Shown on the Home navigation bar, the Habits overview, the habit detail
footer, and the weekly review. Seven tests in `PointsServiceTests`.
