import Foundation

public enum ControlPlaneEventSourceDTO: String, Codable, Sendable {
    case provider
    case surface
    case script
    case console
    case page
    case action
    case client
    case browser
}

public struct ControlPlaneEventDTO: Codable, Sendable {
    public let eventID: String
    public let sequence: UInt64
    public let emittedAt: String
    public let providerID: String?
    public let groupID: String?
    public let surfaceID: String?
    public let targetID: String?
    public let source: ControlPlaneEventSourceDTO
    public let type: String
    public let scriptID: String?
    public let correlationID: String?
    public let payload: JSONValueDTO
}

public struct ControlPlaneEventFilterDTO: Codable, Sendable {
    public let providerID: String?
    public let groupID: String?
    public let surfaceID: String?
    public let targetID: String?
    public let source: ControlPlaneEventSourceDTO?
    public let types: [String]?
    public let scriptID: String?

    public init(
        providerID: String? = nil,
        groupID: String? = nil,
        surfaceID: String? = nil,
        targetID: String? = nil,
        source: ControlPlaneEventSourceDTO? = nil,
        types: [String]? = nil,
        scriptID: String? = nil
    ) {
        self.providerID = providerID
        self.groupID = groupID
        self.surfaceID = surfaceID
        self.targetID = targetID
        self.source = source
        self.types = types
        self.scriptID = scriptID
    }
}

public struct EmitControlPlaneEventRequest: Codable, Sendable {
    public let providerID: String?
    public let groupID: String?
    public let surfaceID: String?
    public let targetID: String?
    public let source: ControlPlaneEventSourceDTO?
    public let type: String
    public let scriptID: String?
    public let correlationID: String?
    public let payload: JSONValueDTO?

    public init(
        providerID: String? = nil,
        groupID: String? = nil,
        surfaceID: String? = nil,
        targetID: String? = nil,
        source: ControlPlaneEventSourceDTO? = nil,
        type: String,
        scriptID: String? = nil,
        correlationID: String? = nil,
        payload: JSONValueDTO? = nil
    ) {
        self.providerID = providerID
        self.groupID = groupID
        self.surfaceID = surfaceID
        self.targetID = targetID
        self.source = source
        self.type = type
        self.scriptID = scriptID
        self.correlationID = correlationID
        self.payload = payload
    }
}

public struct EmitControlPlaneEventResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let event: ControlPlaneEventDTO
}

public struct PollControlPlaneEventsRequest: Codable, Sendable {
    public let sinceEventID: String?
    public let sinceSequence: UInt64?
    public let filter: ControlPlaneEventFilterDTO?
    public let limit: Int?
    public let timeoutMs: Int?

    public init(
        sinceEventID: String? = nil,
        sinceSequence: UInt64? = nil,
        filter: ControlPlaneEventFilterDTO? = nil,
        limit: Int? = nil,
        timeoutMs: Int? = nil
    ) {
        self.sinceEventID = sinceEventID
        self.sinceSequence = sinceSequence
        self.filter = filter
        self.limit = limit
        self.timeoutMs = timeoutMs
    }
}

public struct PollControlPlaneEventsResponse: Codable, Sendable {
    public let contractVersion: String
    public let events: [ControlPlaneEventDTO]
    public let latestEventID: String?
    public let latestSequence: UInt64?
}

public struct ClearControlPlaneEventsRequest: Codable, Sendable {
    public let filter: ControlPlaneEventFilterDTO?

    public init(filter: ControlPlaneEventFilterDTO? = nil) {
        self.filter = filter
    }
}

public struct ClearControlPlaneEventsResponse: Codable, Sendable {
    public let contractVersion: String
    public let ok: Bool
    public let removedCount: Int
}
