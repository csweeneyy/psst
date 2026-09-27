import Foundation
import Testing
@testable import Psst

/// iOS exposes no API for a notification's vibration pattern, so varying the
/// words is the only defence against the alert becoming background noise.
@MainActor
@Suite("Rotating nudge copy")
struct NudgeCopyTests {

    private func habit(_ primary: String, _ variants: [String]) -> Habit {
        let habit = Habit(
            name: "H", nudgeText: primary, intensity: .standard, schedule: .everyTwoHours
        )
        habit.nudgeVariantsRaw = variants.joined(separator: "\n")
        return habit
    }

    @Test("With no variants it always uses the primary copy")
    func singleCopyIsStable() {
        let only = habit("Psst... posture", [])
        for _ in 0..<20 { #expect(only.nudgeCopy() == "Psst... posture") }
    }

    @Test("Blank lines and stray whitespace are not offered as phrasings")
    func variantsAreCleaned() {
        let messy = habit("One", ["", "  Two  ", "\n", "Three"])
        #expect(messy.nudgeVariants == ["One", "Two", "Three"])
    }

    @Test("It never repeats the phrasing it was told to avoid")
    func avoidsImmediateRepeats() {
        let rotating = habit("One", ["Two", "Three"])
        for _ in 0..<50 {
            #expect(rotating.nudgeCopy(avoiding: "Two") != "Two")
        }
    }

    @Test("Avoiding the only phrasing still returns something")
    func degradesRatherThanReturningNothing() {
        let only = habit("Only", [])
        #expect(only.nudgeCopy(avoiding: "Only") == "Only")
    }

    @Test("Every phrasing gets used")
    func rotationReachesAll() {
        let rotating = habit("One", ["Two", "Three"])
        var seen: Set<String> = []
        for _ in 0..<200 { seen.insert(rotating.nudgeCopy()) }
        #expect(seen == ["One", "Two", "Three"])
    }
}
