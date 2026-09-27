import AVFoundation
import Foundation
import Speech

/// All audio and recognition work, deliberately off the main actor.
///
/// This type exists because of a crash, not for tidiness. The project builds
/// with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a closure written
/// inside a `@MainActor` type inherits main-actor isolation. Two of the
/// callbacks here are invoked by the system on other threads:
///
///   - `AVAudioNode.installTap` calls its block on a realtime audio thread.
///   - `SFSpeechRecognizer.requestAuthorization` and `recognitionTask` call
///     back on background queues.
///
/// An isolated closure reached from those threads fails Swift's executor check
/// and traps:
///
///     _dispatch_assert_queue_fail
///     swift_task_isCurrentExecutorWithFlagsImpl
///     closure #1 in SpeechService.start()
///     AVAudioNodeTap::TapMessage::RealtimeMessenger_Perform()
///
/// Keeping every one of them outside main-actor isolation is the fix. The
/// owner hops to the main actor itself when it publishes state.
nonisolated final class SpeechEngine: @unchecked Sendable {

    enum StartError: Error, LocalizedError {
        case notAuthorized
        case unavailable
        case noInput
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Microphone or dictation access is off. Turn it on in Settings."
            case .unavailable: "Dictation is unavailable right now."
            case .noInput: "No audio input available."
            case .underlying(let error): error.localizedDescription
            }
        }
    }

    /// A mutable box the audio thread can own outright.
    private final class Counter: @unchecked Sendable {
        var value = 0
    }

    /// Holds whichever request the tap should be feeding right now.
    ///
    /// The audio tap is installed once and runs for the whole dictation, but
    /// the recognition request underneath it is replaced every time a segment
    /// finalises. Without this indirection the tap would keep feeding a dead
    /// request and the words would stop arriving.
    private final class RequestBox: @unchecked Sendable {
        let lock = NSLock()
        private var current: SFSpeechAudioBufferRecognitionRequest?

        func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
            lock.lock(); defer { lock.unlock() }
            self.current = request
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.lock(); defer { lock.unlock() }
            current?.append(buffer)
        }

        func endAudio() {
            lock.lock(); defer { lock.unlock() }
            current?.endAudio()
        }
    }

    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var tapped = false

    /// Text from segments the recogniser has already finalised.
    ///
    /// `SFSpeechRecognizer` does not transcribe indefinitely. It finalises
    /// after a pause and again at around a minute of audio, and each new task
    /// starts from an empty string. Reporting only the live task's transcript
    /// is why dictation appeared to wipe what you had just said. Everything
    /// finalised is kept here and prepended.
    private var committed = ""
    private var stopping = false
    private let state = NSLock()

    /// `@Sendable` on every closure is what stops them inheriting the caller's
    /// isolation. Removing it reintroduces the crash.
    func start(
        onPartial: @escaping @Sendable (String) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        onFinish: @escaping @Sendable (Error?) -> Void
    ) async -> StartError? {
        guard await Self.authorize() else { return .notAuthorized }

        let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { return .unavailable }
        self.recognizer = recognizer

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Valid only once the session is active. Before that it reports
            // 0 Hz and `installTap` trips a sample-rate assertion.
            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                deactivate()
                return .noInput
            }


            // Only ever touched from the audio thread, which is serial.
            let throttle = Counter()

            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                // Realtime audio thread. Touch nothing but the request and the
                // level, and do not allocate.
                self.box.append(buffer)

                // A waveform wants roughly 15 updates a second, not the ~23
                // this tap delivers, and each one costs a hop to the main
                // actor. Every other buffer is plenty.
                throttle.value += 1
                guard throttle.value % 2 == 0 else { return }
                guard let channel = buffer.floatChannelData?[0] else { return }

                let count = Int(buffer.frameLength)
                guard count > 0 else { return }
                var sum: Float = 0
                for index in 0..<count {
                    let sample = channel[index]
                    sum += sample * sample
                }
                onLevel((sum / Float(count)).squareRoot())
            }
            tapped = true

            engine.prepare()
            try engine.start()

            listen(onPartial: onPartial, onFinish: onFinish)
            return nil
        } catch {
            stop()
            return .underlying(error)
        }
    }

    /// Starts a recognition task and replaces it whenever it finalises.
    ///
    /// Keeps the audio engine and the tap untouched across the swap, so no
    /// audio is lost in the gap and the waveform never stutters.
    private func listen(
        onPartial: @escaping @Sendable (String) -> Void,
        onFinish: @escaping @Sendable (Error?) -> Void
    ) {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        box.set(request)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                onPartial(self.joined(with: text))

                if result.isFinal {
                    // Computed before taking the lock: `joined` takes it too,
                    // and `NSLock` is not recursive.
                    let merged = self.joined(with: text)
                    self.state.lock()
                    self.committed = merged
                    let stopping = self.stopping
                    self.state.unlock()

                    // A finalised segment is the recogniser taking a breath,
                    // not the user finishing. Pick straight back up unless a
                    // stop is actually in flight.
                    if !stopping {
                        self.task = nil
                        self.listen(onPartial: onPartial, onFinish: onFinish)
                    }
                    return
                }
            }

            if let error {
                self.state.lock()
                let stopping = self.stopping
                self.state.unlock()
                // Cancelling a task to swap it reports an error. Only a
                // failure while we still expect to be listening is real.
                if !stopping { onFinish(error) }
            }
        }
    }

    private func joined(with live: String) -> String {
        state.lock(); defer { state.unlock() }
        guard !committed.isEmpty else { return live }
        guard !live.isEmpty else { return committed }
        return committed + " " + live
    }

    func stop() {
        state.lock()
        stopping = true
        state.unlock()

        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        if engine.isRunning { engine.stop() }
        box.endAudio()
        task?.cancel()
        box.set(nil)
        task = nil
        deactivate()

        state.lock()
        committed = ""
        stopping = false
        state.unlock()
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
