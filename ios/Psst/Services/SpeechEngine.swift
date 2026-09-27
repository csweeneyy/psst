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

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var tapped = false

    /// `@Sendable` on both closures is what stops them inheriting the caller's
    /// isolation. Removing it reintroduces the crash.
    func start(
        onPartial: @escaping @Sendable (String) -> Void,
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

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request

            input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
                // Realtime audio thread. Touch nothing but the request.
                request.append(buffer)
            }
            tapped = true

            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: request) { result, error in
                if let result { onPartial(result.bestTranscription.formattedString) }
                if error != nil || result?.isFinal == true { onFinish(error) }
            }
            return nil
        } catch {
            stop()
            return .underlying(error)
        }
    }

    func stop() {
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        deactivate()
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
