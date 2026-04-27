import Foundation

final class BrowserEventStore: @unchecked Sendable {
    static let shared = BrowserEventStore()

    private let lock = NSLock()
    private var nextOrdinal: UInt64 = 1
    private var events: [BrowserEventDTO] = []
    private let maximumEvents = 1_000

    private init() {}

    @discardableResult
    func emit(targetID: String?, scriptID: String?, type: String, payload: JSONValueDTO?) -> BrowserEventDTO {
        lock.lock()
        defer { lock.unlock() }

        let event = BrowserEventDTO(
            eventID: "be_\(nextOrdinal)",
            targetID: targetID,
            scriptID: scriptID,
            type: type,
            payload: payload ?? .null,
            emittedAt: Time.iso8601String(from: Date())
        )
        nextOrdinal += 1
        events.append(event)
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
        return event
    }

    func poll(sinceEventID: String?, targetID: String?, limit: Int?) -> [BrowserEventDTO] {
        lock.lock()
        defer { lock.unlock() }

        let startIndex: Int
        if let sinceEventID,
           let index = events.firstIndex(where: { $0.eventID == sinceEventID }) {
            startIndex = events.index(after: index)
        } else {
            startIndex = events.startIndex
        }

        let filtered = events[startIndex...].filter { event in
            targetID == nil || event.targetID == targetID
        }
        return Array(filtered.prefix(max(1, min(limit ?? 100, 500))))
    }

    func latestEventID() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return events.last?.eventID
    }

    func clear(targetID: String?) -> Int {
        lock.lock()
        defer { lock.unlock() }

        let before = events.count
        if let targetID {
            events.removeAll { $0.targetID == targetID }
        } else {
            events.removeAll()
        }
        return before - events.count
    }
}
