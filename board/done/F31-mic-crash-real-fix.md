# F31 - Voice crash, actual root cause

**Why**
Two attempts failed because I guessed. The third pulled the crash report off
the device:

    EXC_BREAKPOINT (SIGTRAP)
    _dispatch_assert_queue_fail
    swift_task_isCurrentExecutorWithFlagsImpl
    closure #1 in SpeechService.authorize()
    __TCCAccessRequest_block_invoke_8

`SFSpeechRecognizer.requestAuthorization` calls back on a background XPC queue.
Marking the class `@MainActor` (done in the previous round, to fix a different
crash) made that closure main-actor isolated, so the runtime trapped.

**Acceptance**
- The authorization continuation is `nonisolated`
- Mic can be started and stopped repeatedly without terminating the app

**Status**
Code fixed. Not yet confirmed on device.
