# Psst

Accountability app. The whole bet is that notifications are the product: they
arrive at the right moment, in your own words, and take one tap to answer.

## Run it

    cd ios && xcodegen generate && open Psst.xcodeproj

    # tests
    xcodebuild test -scheme Psst -destination 'platform=iOS Simulator,name=iPhone 17'

    # seeded UI, no tapping through setup
    SIMCTL_CHILD_PSST_SEED=1 xcrun simctl launch <device> com.connorsweeney.Psst

Worker:

    cd worker && npm install
    npx wrangler secret put OPENROUTER_API_KEY   # <- required, not yet set
    npx wrangler deploy

    bun run eval                                  # score the deployed chain
    bun run eval openrouter:deepseek/deepseek-chat   # score one model

`ios/project.yml` is the source of truth. `Psst.xcodeproj` is generated and
should not be edited by hand; re-run `xcodegen generate` after adding files.

## Code map

    ios/Shared/          compiled into BOTH the app and the widget extension
      Types/             pure data: Schedule, Intensity, SwiftData models
      Intents/           CompleteHabitIntent, SnoozeHabitIntent
      Services/          SchedulingService (the 64-slot planner)
    ios/Psst/
      Design/Theme.swift one vocabulary for colour, spacing, radius, motion
      Services/          one per iOS subsystem, plus NudgeCoordinator
      Views/             RootView, HomeView, ChatView, HabitsView, HabitSetupView
    ios/PsstWidgets/     Live Activity UI and the AlarmKit attributes registration
    worker/              Cloudflare Worker, D1, Anthropic tool calling
    board/               kanban as folders; see board/README.md

Style follows Safeloop: explicit dependencies, errors returned not thrown,
types separate from services, and the entrypoint (`NudgeCoordinator`, the
Worker's `fetch`) owns every resource lifecycle.

## The three notification tiers

This is the core design and it is not cosmetic. Each tier is a different iOS
API with a different budget.

|Tier|API|Buttons without long press|Breaks Focus + silent|Budget|
|---|---|---|---|---|
|`gentle`|`UNNotificationRequest`|no|no|64 pending, shared|
|`standard`|ActivityKit Live Activity|yes, on Lock Screen|no|undocumented, assume tiny|
|`alarm`|AlarmKit (iOS 26+)|yes, always|yes|`maximumLimitReached`|

Consequences that are easy to forget:

- **64 pending notification requests, app-wide, system enforced.** No
  workaround. Confirmed by Apple DTS:
  https://developer.apple.com/forums/thread/811171
  `SchedulingService` maintains a rolling 48 hour window and allocates fairly,
  so one every-15-minutes habit cannot starve a once-a-day habit.
- **Notification action buttons need a long press** and only the first two
  render. No public API changes this. That is the entire reason the `standard`
  tier exists.
- **Live Activity concurrency is undocumented.** The "5 per app" figure on the
  internet is not Apple-sourced. `LiveActivityService` treats a refusal as
  routine and the coordinator degrades those nudges to notifications.
- **AlarmKit recurs natively**, so a weekday 7 AM habit is one alarm, not one
  request per day, and it never touches the 64-slot budget.
- **Apple Watch is free leverage.** watchOS renders notification actions inline
  with no long press, and Double Tap fires the first non-destructive action.
  "Done" is deliberately registered first in `NotificationService`.

## Model routing

The Worker is provider-agnostic. `src/services/providers/` has two adapters:
Anthropic's `/v1/messages`, and one OpenAI-compatible `/chat/completions`
adapter that covers OpenRouter, Fireworks, DeepSeek, Groq and OpenAI.

`MODEL_CHAIN` is an ordered list of `provider:model`, tried in order:

    MODEL_CHAIN = "fireworks:accounts/fireworks/models/glm-5p3-flash,openrouter:anthropic/claude-sonnet-4.5"

Escalation is driven by **observed failure**, never by predicting difficulty:

- transport error, 429, or 5xx
- unparseable tool arguments
- every tool call failed schema validation
- an empty response

A 4xx that is our fault does not escalate, because the next model would
receive the same malformed request. The response carries `servedBy` and an
`attempts` array so you can see what happened.

`x-psst-model` on a request overrides the chain for that call. The eval
harness uses it to score one model at a time without redeploying.

**The tool schema is deliberately flat.** `ScheduleKind` is a union, but it is
expressed as one object with a `type` field and optional siblings rather than
`oneOf`. Weak models ignore `oneOf` and emit a merged object. Validation lives
in `tools.ts:validateSchedule` either way, so the schema only needs to be
understandable, not airtight.

## Design system

`Psst/Design/Theme.swift` is the only place colour, type, spacing and motion
are defined. Rules that matter:

- **SF Pro, never SF Rounded.** Rounded is Apple's playful face and appears
  almost nowhere in shipping Apple apps. Using it everywhere is the single
  strongest "generated app" signal.
- **UIKit semantic colours, not hex.** `systemGroupedBackground`,
  `secondarySystemGroupedBackground`, `label`, `separator`. These are the exact
  values Settings and Mail draw with, and they track contrast and
  accessibility settings for free.
- **The accent is `.label`, i.e. near-black.** Colour is reserved for state:
  green completed, red missed. The only decorative colour in the app is the
  tint a habit was given, and those come from the iOS system palette.
- **No card shadows.** White on grouped grey, exactly like an inset list. Each
  shadow layer is an offscreen render pass and there were two per card.
- **`.snappy`, not `.spring`.** Overshoot is what read as sluggish.

Screens use real `List` with `.listStyle(.insetGrouped)` rather than a
ScrollView of hand-drawn cards. That brings row reuse, correct section header
treatment, and `swipeActions`, which is the only reliable way to get a swipe
gesture past a scroll view.

## Adaptation

`ScheduleAdvisor` is the piece that makes the app adaptive rather than merely
configurable. It reads the response heatmap and returns at most one suggestion.

It is deliberately conservative: a suggestion rejected twice is worse than
none. It needs 8 answered nudges overall and 3 in any hour before it speaks,
and it will not propose tightening a window unless a reliably-answered hour
survives the trim. Suggestions surface in the habit detail sheet and in the
weekly review, and apply in one tap.

## Traps

- `Shared/` is compiled into three targets. `PsstTests` must NOT compile it, or
  you get two copies of every type and a link failure against
  `@testable import Psst`.
- Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure data types and
  pure-function services need an explicit `nonisolated`, or their `Codable`
  conformances become MainActor-isolated and fail to compile in the widget.
- `SwiftData` calls `fatalError`, not `throw`, when asked for an app group the
  process is not entitled to. `PsstStore.container()` checks with `FileManager`
  first. Never build with `CODE_SIGNING_ALLOWED=NO` and expect the group store.
- Do not name a local enum `Tab` inside a `TabView`; it shadows SwiftUI's `Tab`.
- A custom `DragGesture` will not reliably beat a `ScrollView`'s pan. Use
  `List` + `swipeActions`. Three attempts at a hand-rolled swipe failed before
  switching.
- In a UI test, a swipe starting within ~30pt of the left screen edge is eaten
  by the interactive-pop gesture, and `app.cells.element(boundBy: 0)` is the
  section header, not the first row.
- `AVAudioEngine.inputNode` returns a 0 Hz format until the audio session is
  active; `installTap` then traps. Permissions, then session, then format.
- **Never put a system callback inside a `@MainActor` type here.** With
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, closures inherit main-actor
  isolation, and anything the system calls from another thread (an audio tap,
  a TCC authorization reply, a recognition task) fails Swift's executor check
  and raises SIGTRAP. `SpeechEngine` is `nonisolated` for exactly this reason,
  and its callback parameters are `@Sendable` so they cannot re-inherit it.
- **Never send the assistant a UTC timestamp.** `ISO8601DateFormatter` is GMT
  by default, so a Saturday evening in New York reads as Sunday and the model
  schedules the wrong day. `AssistantService.localTimeDescription` spells out
  the weekday name and number.
- Intents must write through `PsstStore.shared.mainContext`. A separate
  `ModelContext` over the same container saves fine but leaves the running
  app's `@Query` on a stale object.
- `confirmationDialog` is a bottom action sheet on iPhone regardless of what
  triggered it. Row-level confirmations want `.alert`.
- Build chat history BEFORE storing the new turn, or the model receives the
  same sentence twice and says so.
- The tool schema's example values get copied verbatim by the model. A stale
  example colour is why new habits kept coming back terracotta.
- `PsstStore` must be one container per process. Two containers over the same
  store do not share a coordinator, so an intent's write is invisible to the
  app's live `@Query`.
- `Logger.info` is memory-only and never reaches the syslog relay. Diagnostics
  you intend to read over `idevicesyslog` must be `.notice` or higher.
- Only one process may hold the device syslog relay. A background
  `idevicesyslog` will silently starve a foreground one.
- `NotificationService.sync` does NOT own every pending request. Snooze
  follow-ups and the repeating weekly review are preserved by identifier
  prefix; removing everything wipes them.
- `ModelContext` is not `Sendable`. Pass the `ModelContainer` across an actor
  boundary and resolve the context on the far side.
- `Section("Title") { … } footer: { … }` does not compile. Use the explicit
  `header:`/`footer:` closure form.
- `resync` must purge as well as add. `SchedulingService.stale` decides what
  the new plan orphaned; skipping it leaves the old schedule's rows on Home and
  makes every habit edit look like a no-op. Regression: `ReconciliationTests`.
- The `Mutation` and `ScheduleKind` JSON is hand-written on both sides
  (`Shared/Types/Schedule.swift`, `Psst/Services/AssistantService.swift`,
  `worker/src/types.ts`). `PsstTests/WireFormatTests.swift` holds the fixtures.
  Change one side, change the other, or the assistant silently stops working.

## Decisions not worth relitigating

- **Native Swift, not React Native.** `UNUserNotificationCenter`, ActivityKit
  and AlarmKit are the product. A bridge would gate all three.
- **The minimum interval is a code floor, not a prompt instruction.** It is
  enforced in `SchedulingService.fireTimes`, again in `MutationApplier.apply`,
  and again in the Worker's `validateSchedule`. A model cannot talk past it.
- **The device owns the habits, the Worker owns the conversation.** The app
  works offline. D1 mirrors habits only so a future push scheduler has
  something to read.
- **Two tabs.** Home and Chat share a surface; Habits holds aggregation with
  setup behind the plus button.
- **Times are minute-precision everywhere.** Steppers were replaced with
  `DatePicker(.hourAndMinute)`. The interval stepper uses adaptive steps
  (1 min under 15, then 5, 15, 30) so you can dial in a two-minute test
  cadence without hundreds of taps to reach eight hours.
- **The minimum interval is derived from the cadence you picked**, at half its
  natural spacing, rather than a fixed 15 or 30. A hand-set schedule is never
  filtered out by its own floor. The assistant still cannot go below it.
- **A hand-moved nudge is pinned.** `HabitOccurrence.isPinned` survives a
  resync, so moving one reminder to 5:01 does not get undone the next time the
  habit's schedule is recomputed.
