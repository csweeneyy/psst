import Foundation
import Testing
@testable import Psst

/// The Worker hand-writes the JSON for `Mutation` and `Schedule` in
/// `worker/src/types.ts`. Nothing generates one side from the other, so these
/// fixtures are the contract. If they drift, the assistant silently stops
/// being able to change anything.
@Suite("Assistant wire format")
struct WireFormatTests {

    private func decode(_ json: String) throws -> Mutation {
        try JSONDecoder().decode(Mutation.self, from: Data(json.utf8))
    }

    @Test("create_habit payload from the Worker decodes")
    func createHabit() throws {
        let mutation = try decode("""
        {
          "type": "createHabit",
          "habit": {
            "name": "Posture check",
            "nudgeText": "Psst... check your posture :)",
            "intensity": "standard",
            "symbol": "figure.stand",
            "tintHex": "#E8846B",
            "schedule": {
              "kind": { "type": "interval", "minutes": 120 },
              "windowStartMinute": 540,
              "windowEndMinute": 1260,
              "weekdays": [2, 3, 4, 5, 6],
              "minIntervalMinutes": 60
            }
          }
        }
        """)
        guard case .createHabit(let draft) = mutation else {
            Issue.record("wrong case"); return
        }
        #expect(draft.name == "Posture check")
        #expect(draft.intensity == .standard)
        #expect(draft.schedule.weekdays == [2, 3, 4, 5, 6])
        guard case .interval(let minutes) = draft.schedule.kind else {
            Issue.record("wrong kind"); return
        }
        #expect(minutes == 120)
    }

    @Test("Every schedule kind survives the round trip")
    func scheduleKinds() throws {
        let cases: [(String, ScheduleKind)] = [
            (#"{"type":"interval","minutes":90}"#, .interval(minutes: 90)),
            (#"{"type":"fixedTimes","times":[540,1080]}"#, .fixedTimes([540, 1080])),
            (#"{"type":"spread","count":6,"period":"day"}"#, .spread(count: 6, period: .day)),
        ]
        for (json, expected) in cases {
            let decoded = try JSONDecoder().decode(ScheduleKind.self, from: Data(json.utf8))
            #expect(decoded == expected)
            // And back out again, so the Worker can read what the app mirrors.
            let reencoded = try JSONEncoder().encode(decoded)
            let round = try JSONDecoder().decode(ScheduleKind.self, from: reencoded)
            #expect(round == expected)
        }
    }

    @Test("Every mutation type the Worker can emit is decodable")
    func allMutationTypes() throws {
        let id = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        let payloads = [
            #"{"type":"setIntensity","habitID":"\#(id)","intensity":"alarm"}"#,
            #"{"type":"pauseHabit","habitID":"\#(id)","paused":true}"#,
            #"{"type":"deleteHabit","habitID":"\#(id)"}"#,
            #"{"type":"updateSchedule","habitID":"\#(id)","schedule":{"kind":{"type":"spread","count":3,"period":"week"},"windowStartMinute":480,"windowEndMinute":1200,"weekdays":[1,2,3,4,5,6,7],"minIntervalMinutes":45}}"#,
        ]
        for payload in payloads {
            #expect(throws: Never.self) { try decode(payload) }
        }
    }

    @Test("An unknown mutation type is rejected, not silently ignored")
    func unknownTypeThrows() {
        #expect(throws: (any Error).self) {
            try decode(#"{"type":"launchRocket","habitID":"x"}"#)
        }
    }
}
