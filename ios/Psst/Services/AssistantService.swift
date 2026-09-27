import Foundation

/// What the assistant is allowed to change. The app applies these locally;
/// the model never writes to the store directly.
nonisolated enum Mutation: Codable, Sendable {
    case createHabit(HabitDraft)
    case updateSchedule(habitID: UUID, schedule: Schedule)
    case setIntensity(habitID: UUID, intensity: Intensity)
    case pauseHabit(habitID: UUID, paused: Bool)
    case deleteHabit(habitID: UUID)
    /// Rename, reword the nudge, change its icon or colour. Every field optional.
    case updateHabit(habitID: UUID, name: String?, nudgeText: String?, symbol: String?, tintHex: String?)
    case setNotes(habitID: UUID, notes: String)
    /// Mark a whole day answered. `habitID` nil means every habit that day.
    case logDay(habitID: UUID?, day: String, status: OccurrenceStatus)
    /// Erase history in a date range. `habitID` nil means every habit.
    case clearRange(habitID: UUID?, from: String, to: String)
    /// Push the next pending nudge for a habit back by `minutes`.
    case snoozeNext(habitID: UUID, minutes: Int)

    /// Anything that destroys data the user cannot reconstruct. The app asks
    /// before applying these, no matter how confidently the model asked.
    var isDestructive: Bool {
        switch self {
        case .deleteHabit, .clearRange: true
        default: false
        }
    }

    /// Flat discriminated union, matching the tool result shapes the Worker
    /// produces. See `worker/src/services/assistant.ts`.
    private enum CodingKeys: String, CodingKey {
        case type, habit, habitID, schedule, intensity, paused
        case name, nudgeText, symbol, tintHex, notes, day, status, from, to, minutes
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "createHabit":
            self = .createHabit(try c.decode(HabitDraft.self, forKey: .habit))
        case "updateSchedule":
            self = .updateSchedule(
                habitID: try c.decode(UUID.self, forKey: .habitID),
                schedule: try c.decode(Schedule.self, forKey: .schedule)
            )
        case "setIntensity":
            self = .setIntensity(
                habitID: try c.decode(UUID.self, forKey: .habitID),
                intensity: try c.decode(Intensity.self, forKey: .intensity)
            )
        case "pauseHabit":
            self = .pauseHabit(
                habitID: try c.decode(UUID.self, forKey: .habitID),
                paused: try c.decode(Bool.self, forKey: .paused)
            )
        case "deleteHabit":
            self = .deleteHabit(habitID: try c.decode(UUID.self, forKey: .habitID))
        case "updateHabit":
            self = .updateHabit(
                habitID: try c.decode(UUID.self, forKey: .habitID),
                name: try c.decodeIfPresent(String.self, forKey: .name),
                nudgeText: try c.decodeIfPresent(String.self, forKey: .nudgeText),
                symbol: try c.decodeIfPresent(String.self, forKey: .symbol),
                tintHex: try c.decodeIfPresent(String.self, forKey: .tintHex)
            )
        case "setNotes":
            self = .setNotes(
                habitID: try c.decode(UUID.self, forKey: .habitID),
                notes: try c.decode(String.self, forKey: .notes)
            )
        case "logDay":
            self = .logDay(
                habitID: try c.decodeIfPresent(UUID.self, forKey: .habitID),
                day: try c.decode(String.self, forKey: .day),
                status: try c.decode(OccurrenceStatus.self, forKey: .status)
            )
        case "clearRange":
            self = .clearRange(
                habitID: try c.decodeIfPresent(UUID.self, forKey: .habitID),
                from: try c.decode(String.self, forKey: .from),
                to: try c.decode(String.self, forKey: .to)
            )
        case "snoozeNext":
            self = .snoozeNext(
                habitID: try c.decode(UUID.self, forKey: .habitID),
                minutes: try c.decode(Int.self, forKey: .minutes)
            )
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown mutation \(other)"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .createHabit(let draft):
            try c.encode("createHabit", forKey: .type)
            try c.encode(draft, forKey: .habit)
        case .updateSchedule(let id, let schedule):
            try c.encode("updateSchedule", forKey: .type)
            try c.encode(id, forKey: .habitID)
            try c.encode(schedule, forKey: .schedule)
        case .setIntensity(let id, let intensity):
            try c.encode("setIntensity", forKey: .type)
            try c.encode(id, forKey: .habitID)
            try c.encode(intensity, forKey: .intensity)
        case .pauseHabit(let id, let paused):
            try c.encode("pauseHabit", forKey: .type)
            try c.encode(id, forKey: .habitID)
            try c.encode(paused, forKey: .paused)
        case .deleteHabit(let id):
            try c.encode("deleteHabit", forKey: .type)
            try c.encode(id, forKey: .habitID)
        case .updateHabit(let id, let name, let nudgeText, let symbol, let tintHex):
            try c.encode("updateHabit", forKey: .type)
            try c.encode(id, forKey: .habitID)
            try c.encodeIfPresent(name, forKey: .name)
            try c.encodeIfPresent(nudgeText, forKey: .nudgeText)
            try c.encodeIfPresent(symbol, forKey: .symbol)
            try c.encodeIfPresent(tintHex, forKey: .tintHex)
        case .setNotes(let id, let notes):
            try c.encode("setNotes", forKey: .type)
            try c.encode(id, forKey: .habitID)
            try c.encode(notes, forKey: .notes)
        case .logDay(let id, let day, let status):
            try c.encode("logDay", forKey: .type)
            try c.encodeIfPresent(id, forKey: .habitID)
            try c.encode(day, forKey: .day)
            try c.encode(status, forKey: .status)
        case .clearRange(let id, let from, let to):
            try c.encode("clearRange", forKey: .type)
            try c.encodeIfPresent(id, forKey: .habitID)
            try c.encode(from, forKey: .from)
            try c.encode(to, forKey: .to)
        case .snoozeNext(let id, let minutes):
            try c.encode("snoozeNext", forKey: .type)
            try c.encode(id, forKey: .habitID)
            try c.encode(minutes, forKey: .minutes)
        }
    }
}

/// Plain `YYYY-MM-DD`, resolved in the device's own calendar. Day-based tools
/// use this rather than timestamps so a late-evening request cannot land on
/// the wrong date the way a UTC instant did.
nonisolated enum DayKey {
    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let pieces = key.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2]))
    }
}

nonisolated struct HabitDraft: Codable, Sendable {
    var name: String
    var nudgeText: String
    var intensity: Intensity
    var schedule: Schedule
    var symbol: String
    var tintHex: String
}

/// The snapshot the assistant reasons over. Sent with every message, because
/// the Worker stays stateless about habit content and the device remains the
/// source of truth.
nonisolated struct DayPoint: Codable, Sendable {
    /// `YYYY-MM-DD`.
    var day: String
    var done: Int
    var of: Int
}

nonisolated struct PeriodPoint: Codable, Sendable {
    /// Bucket start, `YYYY-MM-DD`.
    var start: String
    var done: Int
    var of: Int
}

nonisolated struct HabitSnapshot: Codable, Sendable {
    var id: UUID
    var name: String
    var nudgeText: String
    var intensity: Intensity
    var schedule: Schedule
    var isPaused: Bool
    var completionRate7d: Double
    var currentStreak: Int
    var longestStreak: Int
    var notes: String
    /// Last 14 days, oldest first.
    var recent: [DayPoint]
    /// Last 12 weeks and 12 months, so questions that reach past two weeks are
    /// answerable without a round trip. Day-level detail beyond that comes
    /// from `fetch_history`.
    var weekly: [PeriodPoint]
    var monthly: [PeriodPoint]
    /// Oldest record, `YYYY-MM-DD`. Tells the model how far back it may ask.
    var trackedSince: String?
}

/// The assistant asking for day-level detail it was not given up front.
nonisolated struct HistoryRequest: Codable, Sendable {
    var from: String
    var to: String
    var habitID: UUID?
}

/// The answer to one, supplied by the device on the second pass.
nonisolated struct HistorySlice: Codable, Sendable {
    var habitID: UUID
    var habitName: String
    var days: [DayPoint]
}

nonisolated struct AssistantReply: Codable, Sendable {
    var reply: String
    var mutations: [Mutation]
    /// Present when the model needs history it was not handed. The app fills
    /// it and asks again; see `ChatView.send`.
    var dataRequest: HistoryRequest?
    /// Tool calls the Worker rejected. Shown to the user, because a model that
    /// half-applied a compound request will still say "Done".
    var warnings: [String]?
}

nonisolated enum AssistantService {

    enum ServiceError: Error, LocalizedError {
        case notConfigured
        case transport(Error)
        case badStatus(Int, String)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "No assistant endpoint set. Add PSST_API_BASE to the scheme's environment."
            case .transport(let e): e.localizedDescription
            case .badStatus(let code, let body): "Assistant returned \(code). \(body)"
            case .decoding(let e): "Could not read the assistant's reply. \(e.localizedDescription)"
            }
        }
    }

    struct Request: Codable {
        var message: String
        var habits: [HabitSnapshot]
        var history: [Turn]
        var timezone: String
        var localTime: String
        /// Populated only on a second pass, in answer to a `dataRequest`.
        var extraHistory: [HistorySlice]?
    }

    struct Turn: Codable {
        var role: String
        var text: String
    }

    /// A local, unambiguous description of "now".
    ///
    /// `ISO8601DateFormatter` defaults to GMT. At 8:26 PM on a Saturday in
    /// New York it emits `2026-09-27T00:26:29Z`, so the assistant correctly
    /// read Sunday off a UTC timestamp and scheduled a habit for the wrong
    /// day. The weekday number is spelled out because that is the exact value
    /// the schedule tool expects.
    static func localTimeDescription(_ now: Date = .now, calendar: Calendar = .current) -> String {
        let weekday = calendar.component(.weekday, from: now)
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let name = names[max(0, min(weekday - 1, 6))]
        let stamp = now.formatted(
            .dateTime.year().month(.wide).day().hour().minute().timeZone()
        )
        return "\(name), \(stamp) (weekday number \(weekday))"
    }

    static var baseURL: URL? {
        let info = Bundle.main.object(forInfoDictionaryKey: "PsstAPIBase") as? String
        let env = ProcessInfo.processInfo.environment["PSST_API_BASE"]
        guard let raw = info ?? env, raw.isEmpty == false else { return nil }
        return URL(string: raw)
    }

    static func send(
        _ message: String,
        habits: [HabitSnapshot],
        history: [Turn],
        extraHistory: [HistorySlice]? = nil,
        session: URLSession = .shared
    ) async -> Result<AssistantReply, ServiceError> {
        guard let base = baseURL else { return .failure(.notConfigured) }

        let body = Request(
            message: message,
            habits: habits,
            history: Array(history.suffix(20)),
            timezone: TimeZone.current.identifier,
            localTime: Self.localTimeDescription(),
            extraHistory: extraHistory
        )

        var request = URLRequest(url: base.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            return .failure(.decoding(error))
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                return .failure(.badStatus(status, String(data: data, encoding: .utf8) ?? ""))
            }
            do {
                return .success(try JSONDecoder().decode(AssistantReply.self, from: data))
            } catch {
                return .failure(.decoding(error))
            }
        } catch {
            return .failure(.transport(error))
        }
    }
}
