import Foundation

/// Main-actor view state for dictation. Owns a `SpeechEngine` but performs no
/// audio work itself, so nothing here can be reached from an audio thread.
@MainActor
@Observable
final class SpeechService {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var error: String?

    @ObservationIgnored private let engine = SpeechEngine()

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func reset() {
        transcript = ""
        error = nil
    }

    private func start() async {
        guard !isRecording else { return }
        error = nil
        isRecording = true

        let failure = await engine.start(
            onPartial: { [weak self] text in
                Task { @MainActor [weak self] in self?.transcript = text }
            },
            onFinish: { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            }
        )

        if let failure {
            isRecording = false
            error = failure.errorDescription
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
    }
}
