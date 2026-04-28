import Foundation

final class ControlPlaneEventStore: @unchecked Sendable {
    static let shared = ControlPlaneEventStore()

    private let condition = NSCondition()
    private var nextSequence: UInt64 = 1
    private var events: [ControlPlaneEventDTO] = []
    private let maximumEvents = 2_000

    private init() {}

    @discardableResult
    func emit(
        providerID: String?,
        groupID: String?,
        surfaceID: String?,
        targetID: String?,
        source: ControlPlaneEventSourceDTO,
        type: String,
        scriptID: String?,
        correlationID: String?,
        payload: JSONValueDTO?
    ) -> ControlPlaneEventDTO {
        condition.lock()
        defer {
            condition.broadcast()
            condition.unlock()
        }

        let sequence = nextSequence
        nextSequence += 1
        let event = ControlPlaneEventDTO(
            eventID: "ev_\(sequence)",
            sequence: sequence,
            emittedAt: Time.iso8601String(from: Date()),
            providerID: emptyToNil(providerID),
            groupID: emptyToNil(groupID),
            surfaceID: emptyToNil(surfaceID),
            targetID: emptyToNil(targetID),
            source: source,
            type: type,
            scriptID: emptyToNil(scriptID),
            correlationID: emptyToNil(correlationID),
            payload: payload ?? .null
        )
        events.append(event)
        if events.count > maximumEvents {
            events.removeFirst(events.count - maximumEvents)
        }
        return event
    }

    func emit(_ request: EmitControlPlaneEventRequest) -> ControlPlaneEventDTO {
        emit(
            providerID: request.providerID,
            groupID: request.groupID,
            surfaceID: request.surfaceID,
            targetID: request.targetID,
            source: request.source ?? .client,
            type: request.type,
            scriptID: request.scriptID,
            correlationID: request.correlationID,
            payload: request.payload
        )
    }

    func poll(_ request: PollControlPlaneEventsRequest) -> PollControlPlaneEventsResponse {
        let timeout = TimeInterval(max(0, min(request.timeoutMs ?? 0, 30_000))) / 1_000
        let deadline = Date().addingTimeInterval(timeout)

        condition.lock()
        defer { condition.unlock() }

        var matched = filteredEventsLocked(request)
        while matched.isEmpty, timeout > 0, Date() < deadline {
            condition.wait(until: deadline)
            matched = filteredEventsLocked(request)
        }

        return PollControlPlaneEventsResponse(
            contractVersion: ContractVersion.current,
            events: matched,
            latestEventID: events.last?.eventID,
            latestSequence: events.last?.sequence
        )
    }

    func clear(_ request: ClearControlPlaneEventsRequest) -> ClearControlPlaneEventsResponse {
        condition.lock()
        defer { condition.unlock() }

        let before = events.count
        if let filter = request.filter {
            events.removeAll { eventMatches($0, filter: filter) }
        } else {
            events.removeAll()
        }
        return ClearControlPlaneEventsResponse(
            contractVersion: ContractVersion.current,
            ok: true,
            removedCount: before - events.count
        )
    }

    func streamBody(_ request: PollControlPlaneEventsRequest) -> String {
        let response = poll(
            PollControlPlaneEventsRequest(
                sinceEventID: request.sinceEventID,
                sinceSequence: request.sinceSequence,
                filter: request.filter,
                limit: request.limit,
                timeoutMs: request.timeoutMs ?? 0
            )
        )
        guard response.events.isEmpty == false else {
            return ": no events\n\n"
        }
        return response.events.map(sseFrame).joined()
    }

    private func filteredEventsLocked(_ request: PollControlPlaneEventsRequest) -> [ControlPlaneEventDTO] {
        let startIndex: Int
        if let sinceEventID = request.sinceEventID,
           let index = events.firstIndex(where: { $0.eventID == sinceEventID }) {
            startIndex = events.index(after: index)
        } else if let sinceSequence = request.sinceSequence,
                  let index = events.firstIndex(where: { $0.sequence > sinceSequence }) {
            startIndex = index
        } else if request.sinceSequence != nil {
            startIndex = events.endIndex
        } else {
            startIndex = events.startIndex
        }

        let scoped = events[startIndex...].filter { event in
            guard let filter = request.filter else { return true }
            return eventMatches(event, filter: filter)
        }
        return Array(scoped.prefix(max(1, min(request.limit ?? 100, 500))))
    }

    private func eventMatches(_ event: ControlPlaneEventDTO, filter: ControlPlaneEventFilterDTO) -> Bool {
        if let providerID = emptyToNil(filter.providerID), event.providerID != providerID { return false }
        if let groupID = emptyToNil(filter.groupID), event.groupID != groupID { return false }
        if let surfaceID = emptyToNil(filter.surfaceID), event.surfaceID != surfaceID { return false }
        if let targetID = emptyToNil(filter.targetID), event.targetID != targetID { return false }
        if let source = filter.source, event.source != source { return false }
        if let scriptID = emptyToNil(filter.scriptID), event.scriptID != scriptID { return false }
        if let types = filter.types?.filter({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }),
           types.isEmpty == false,
           types.contains(event.type) == false {
            return false
        }
        return true
    }

    private func sseFrame(_ event: ControlPlaneEventDTO) -> String {
        let data = (try? JSONSupport.encoder.encode(event))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let dataLines = data
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "data: \($0)" }
            .joined(separator: "\n")
        return "id: \(event.eventID)\nevent: \(event.type)\n\(dataLines)\n\n"
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }
}
