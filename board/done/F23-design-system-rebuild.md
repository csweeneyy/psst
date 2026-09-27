# F23 - Design system rebuild

**Why**
The first pass read as generated: SF Rounded everywhere, hand-mixed terracotta
accent, double shadows on every card, over-explanatory labels.

**Acceptance**
- SF Pro throughout with negative tracking on display sizes
- UIKit semantic colours, no hand-picked hex in the chrome
- Accent is near-black; colour only carries state
- Shadows removed, real `List` with `.insetGrouped`
- Habit tints come from the iOS system palette, default blue

**Status**
Done. Verified in the simulator across all six screens.
