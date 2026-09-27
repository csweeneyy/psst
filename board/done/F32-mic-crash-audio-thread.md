# F32 - Voice crash, take three

**Why**
Third crash report, same signal, different closure. The first fix handled the
authorization callback; this one is the audio tap.

    _dispatch_assert_queue_fail
    swift_task_isCurrentExecutorWithFlagsImpl
    closure #1 in SpeechService.start()
    AVAudioNodeTap::TapMessage::RealtimeMessenger_Perform()

`installTap` invokes its block on a realtime audio thread. The project builds
with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so marking the class
`@MainActor` (my previous fix) made that block main-actor isolated, and the
executor check trapped on every audio buffer.

**Acceptance**
- All audio and recognition work lives in `SpeechEngine`, a `nonisolated` type
- Both system callbacks are `@Sendable`, so they cannot inherit isolation
- `SpeechService` stays `@MainActor` for view state only and hops explicitly

**Status**
Code fixed and addresses the exact stack. NOT yet confirmed on device; two
previous fixes for this looked right and were not.
