import Foundation

struct HealthResponse: Encodable {
    let ok: Bool
    let contractVersion: String
    let timestamp: String
}

struct BootstrapRouteDTO: Encodable {
    let id: String
    let method: String
    let path: String
    let url: String
    let category: String
    let summary: String
}

struct RouteFieldDTO: Encodable {
    let name: String
    let type: String
    let required: Bool
    let description: String?
    let defaultValue: String?
}

struct RouteBodySchemaDTO: Encodable {
    let contentType: String?
    let fields: [RouteFieldDTO]
}

struct APIConceptDTO: Encodable {
    let name: String
    let description: String
    let fields: [RouteFieldDTO]?
}

struct APIGuideDTO: Encodable {
    let summary: String
    let flow: [String]
    let concepts: [APIConceptDTO]
    let responseReading: [String]
    let troubleshooting: [String]
}

struct RouteUsageDTO: Encodable {
    let whenToUse: String
    let useAfter: [String]
    let successSignals: [String]
    let nextSteps: [String]
    let exampleRequest: String?
}

struct RouteErrorDTO: Encodable {
    let statusCode: Int
    let error: String
    let meaning: String
    let recovery: [String]
}

struct APIRouteDTO: Encodable {
    let id: String
    let method: String
    let path: String
    let category: String
    let summary: String
    let notes: [String]
    let execution: RouteExecutionPolicyDTO
    let implementationStatus: RouteImplementationStatusDTO
    let usage: RouteUsageDTO
    let request: RouteBodySchemaDTO?
    let response: RouteBodySchemaDTO
    let errors: [RouteErrorDTO]
}

struct PermissionStatusDTO: Encodable {
    let granted: Bool
    let promptable: Bool
}

struct RuntimePermissionsDTO: Encodable {
    let accessibility: PermissionStatusDTO
    let screenRecording: PermissionStatusDTO
    let checkedAt: String
    let checkMs: Double
}

struct BootstrapInstructionsDTO: Encodable {
    let ready: Bool
    let summary: String
    let agent: [String]
    let user: [String]
}

struct BootstrapResponse: Encodable {
    let contractVersion: String
    let baseURL: String?
    let startedAt: String?
    let permissions: RuntimePermissionsDTO
    let instructions: BootstrapInstructionsDTO
    let guide: APIGuideDTO
    let routes: [BootstrapRouteDTO]
}

struct RuntimeManifestDTO: Encodable {
    let contractVersion: String
    let baseURL: String
    let startedAt: String
    let permissions: RuntimePermissionsDTO
    let instructions: BootstrapInstructionsDTO
    let guide: APIGuideDTO
    let routes: [BootstrapRouteDTO]
}

struct RouteListResponse: Encodable {
    let contractVersion: String
    let guide: APIGuideDTO
    let routes: [APIRouteDTO]
}

struct ErrorResponse: Encodable {
    let contractVersion: String
    let ok: Bool
    let error: String
    let message: String
    let requestID: String
    let recovery: [String]

    init(
        error: String,
        message: String,
        requestID: String,
        recovery: [String] = [],
        contractVersion: String = ContractVersion.current,
        ok: Bool = false
    ) {
        self.contractVersion = contractVersion
        self.ok = ok
        self.error = error
        self.message = message
        self.requestID = requestID
        self.recovery = recovery
    }
}
