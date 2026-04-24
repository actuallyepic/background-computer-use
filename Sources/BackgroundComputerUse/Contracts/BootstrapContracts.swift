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

struct APIRouteDTO: Encodable {
    let id: String
    let method: String
    let path: String
    let category: String
    let summary: String
    let notes: [String]
    let request: RouteBodySchemaDTO?
    let response: RouteBodySchemaDTO
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
    let routes: [BootstrapRouteDTO]
}

struct RuntimeManifestDTO: Encodable {
    let contractVersion: String
    let baseURL: String
    let startedAt: String
    let permissions: RuntimePermissionsDTO
    let instructions: BootstrapInstructionsDTO
    let routes: [BootstrapRouteDTO]
}

struct RouteListResponse: Encodable {
    let contractVersion: String
    let routes: [APIRouteDTO]
}

struct ErrorResponse: Encodable {
    let error: String
    let message: String
    let requestID: String
}
