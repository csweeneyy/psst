# F03 - SwiftData models

**Why**
Habits, their scheduled occurrences, and chat history need to persist and be readable from the widget extension.

**Acceptance**
- `Habit`, `HabitOccurrence`, `ChatMessage` models persist across app launches
- Store lives in the app group container so the widget extension can read it
