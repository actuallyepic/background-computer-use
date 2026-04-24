import XCTest
@testable import BackgroundComputerUse

final class APIDocumentationTests: XCTestCase {
    func testEveryPublicRouteIncludesOperationalDocumentation() {
        let routes = RouteRegistry.publicRoutes()

        XCTAssertEqual(routes.count, RouteID.allCases.count)

        for route in routes {
            XCTAssertFalse(route.usage.whenToUse.isEmpty, route.id)
            XCTAssertFalse(route.usage.successSignals.isEmpty, route.id)
            XCTAssertFalse(route.errors.isEmpty, route.id)
            XCTAssertEqual(route.implementationStatus, .implemented, route.id)
        }
    }

    func testRouteListResponseDocumentsGuideExecutionAndErrors() throws {
        let response = RouteListResponse(
            contractVersion: ContractVersion.current,
            guide: APIDocumentation.guide,
            routes: RouteRegistry.publicRoutes()
        )

        let data = try JSONSupport.encoder.encode(response)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["guide"])

        let routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        let click = try XCTUnwrap(routes.first { $0["id"] as? String == RouteID.click.rawValue })
        XCTAssertNotNil(click["execution"])
        XCTAssertNotNil(click["usage"])

        let errors = try XCTUnwrap(click["errors"] as? [[String: Any]])
        XCTAssertTrue(errors.contains { $0["error"] as? String == "invalid_request" })
        XCTAssertTrue(errors.contains { $0["error"] as? String == "window_not_found" })
    }

    func testInvalidRequestErrorIsVersionedAndActionable() throws {
        let request = try makeRequest(
            method: "POST",
            path: "/v1/list_windows",
            body: "{}"
        )

        let response = Router().response(
            for: request,
            context: RouterContext(baseURL: nil, startedAt: nil)
        )

        XCTAssertEqual(response.statusCode, 400)

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        XCTAssertEqual(json["contractVersion"] as? String, ContractVersion.current)
        XCTAssertEqual(json["ok"] as? Bool, false)
        XCTAssertEqual(json["error"] as? String, "invalid_request")
        XCTAssertTrue((json["message"] as? String)?.contains("Missing required field 'app'") == true)

        let recovery = try XCTUnwrap(json["recovery"] as? [String])
        XCTAssertTrue(recovery.contains { $0.contains("/v1/routes") })
    }

    private func makeRequest(method: String, path: String, body: String = "") throws -> HTTPRequest {
        let bodyData = Data(body.utf8)
        var request = "\(method) \(path) HTTP/1.1\r\n"
        request += "Host: 127.0.0.1\r\n"
        request += "Content-Type: application/json\r\n"
        request += "Content-Length: \(bodyData.count)\r\n"
        request += "\r\n"

        var data = Data(request.utf8)
        data.append(bodyData)

        switch HTTPRequest.parse(data) {
        case .complete(let parsed):
            return parsed
        case .incomplete:
            XCTFail("Request parser returned incomplete")
            throw TestRequestError.parseFailed
        case .invalid:
            XCTFail("Request parser returned invalid")
            throw TestRequestError.parseFailed
        }
    }
}

private enum TestRequestError: Error {
    case parseFailed
}
