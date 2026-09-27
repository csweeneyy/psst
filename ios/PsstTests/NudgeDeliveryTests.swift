import Foundation
import SwiftData
import Testing
@testable import Psst

/// Three separate paths were quietly sending a plain banner regardless of the
/// habit's tier: the preview, snooze follow-ups, and hand-moved nudges. Since
/// choosing a tier per habit is the entire product, a downgrade has to be
/// deliberate and reported, never silent.
@MainActor
@Suite("Tier-aware delivery")
struct NudgeDeliveryTests {

    private func habit(_ intensity: Intensity) -> Habit {
        Habit(name: "H", nudgeText: "n", intensity: intensity, schedule: .everyTwoHours)
    }

    @Test("A nudge too close to now degrades to a banner, and says so")
    func tooSoonDegrades() async {
        // Neither ActivityKit nor AlarmKit will accept a date seconds away, so
        // the honest thing is a banner plus an explanation.
        for intensity in [Intensity.standard, .alarm] {
            let result = await NudgeDelivery.deliver(
                habit: habit(intensity),
                occurrenceID: UUID(),
                at: .now.addingTimeInterval(2)
            )
            guard case .degraded(let tier, let reason) = result else {
                Issue.record("expected a degrade for \(intensity), got \(result)")
                continue
            }
            #expect(tier == intensity)
            #expect(!reason.isEmpty, "a degrade must explain itself")
        }
    }

    @Test("Gentle is never a degrade: a banner is what it asked for")
    func gentleIsAlwaysDelivered() async {
        let result = await NudgeDelivery.deliver(
            habit: habit(.gentle), occurrenceID: UUID(), at: .now.addingTimeInterval(2)
        )
        guard case .delivered(let tier) = result else {
            Issue.record("gentle should never degrade, got \(result)")
            return
        }
        #expect(tier == .gentle)
    }

    @Test("Every outcome explains itself in words a user can act on")
    func summariesAreUseful() {
        for intensity in Intensity.allCases {
            #expect(!NudgeDelivery.Result.delivered(intensity).summary.isEmpty)
            let degraded = NudgeDelivery.Result.degraded(intensity, reason: "Permission is off.")
            #expect(degraded.summary.contains(intensity.title))
            #expect(degraded.summary.contains("Permission is off."))
        }
    }

    @Test("The lead time is long enough for the APIs that need it")
    func leadTimeIsSane() {
        // AlarmKit and scheduled Live Activities both reject near-immediate
        // dates, and the preview has to clear that bar or it is useless.
        #expect(NudgeDelivery.minimumLead >= 20)
        #expect(NudgePreview.delay >= NudgeDelivery.minimumLead)
    }
}
