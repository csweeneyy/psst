import Foundation

/// Main-actor view state for dictation. Owns a `SpeechEngine` but performs no
/// audio work itself, so nothing here can be reached from an audio thread.
@MainActor
@Observable
final class SpeechService {
    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var error: String?

    /// Recent microphone loudness, oldest first, for the waveform. Fixed
    /// length so the bars do not reflow as it fills.
    private(set) var levels: [Float] = Array(repeating: 0, count: SpeechService.barCount)

    static let barCount = 26

    @ObservationIgnored private let engine = SpeechEngine()

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func reset() {
        transcript = ""
        error = nil
        levels = Array(repeating: 0, count: Self.barCount)
    }

    /// Raw RMS sits near zero for ordinary speech, so a linear bar barely
    /// moves. The fourth root opens up the quiet end without clipping the loud
    /// end, which is what makes the waveform look like the room sounds.
    private func push(_ level: Float) {
        let shaped = min(max(Double(level) * 8, 0), 1)
        let eased = Float(pow(shaped, 0.25))
        levels.removeFirst()
        levels.append(eased)
    }

    private func start() async {
        guard !isRecording else { return }
        error = nil
        isRecording = true

        let failure = await engine.start(
            onPartial: { [weak self] text in
                Task { @MainActor [weak self] in self?.transcript = text }
            },
            onLevel: { [weak self] level in
                Task { @MainActor [weak self] in self?.push(level) }
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
