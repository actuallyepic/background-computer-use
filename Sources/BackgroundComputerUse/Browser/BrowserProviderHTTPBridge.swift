import Foundation

struct BrowserProviderHTTPBridge {
    func getState(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserGetStateRequest
    ) throws -> BrowserGetStateResponse {
        try post(
            context: context,
            command: "get_state",
            path: "/bcu/v1/browser/get_state",
            request: request
        )
    }

    func navigate(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserNavigateRequest
    ) throws -> BrowserGetStateResponse {
        try post(
            context: context,
            command: "navigate",
            path: "/bcu/v1/browser/navigate",
            request: request
        )
    }

    func resolve(
        context: RegisteredBrowserSurfaceContext,
        target: BrowserActionTargetRequestDTO
    ) throws -> BrowserInteractableDTO {
        try post(
            context: context,
            command: "resolve",
            path: "/bcu/v1/browser/resolve",
            request: target
        )
    }

    func evaluateJavaScript(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserEvaluateJavaScriptRequest
    ) throws -> BrowserEvaluateJavaScriptResponse {
        try post(
            context: context,
            command: "evaluate_js",
            path: "/bcu/v1/browser/evaluate_js",
            request: request
        )
    }

    func injectJavaScript(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserInjectJavaScriptRequest
    ) throws -> BrowserInjectJavaScriptResponse {
        try post(
            context: context,
            command: "inject_js",
            path: "/bcu/v1/browser/inject_js",
            request: request
        )
    }

    func removeInjectedJavaScript(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserRemoveInjectedJavaScriptRequest
    ) throws -> BrowserRemoveInjectedJavaScriptResponse {
        try post(
            context: context,
            command: "remove_injected_js",
            path: "/bcu/v1/browser/remove_injected_js",
            request: request
        )
    }

    func listInjectedJavaScript(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserListInjectedJavaScriptRequest
    ) throws -> BrowserListInjectedJavaScriptResponse {
        try post(
            context: context,
            command: "list_injected_js",
            path: "/bcu/v1/browser/list_injected_js",
            request: request
        )
    }

    func click(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserClickRequest
    ) throws -> BrowserActionResponse {
        try post(
            context: context,
            command: "click",
            path: "/bcu/v1/browser/click",
            request: request
        )
    }

    func typeText(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserTypeTextRequest
    ) throws -> BrowserActionResponse {
        try post(
            context: context,
            command: "type_text",
            path: "/bcu/v1/browser/type_text",
            request: request
        )
    }

    func scroll(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserScrollRequest
    ) throws -> BrowserActionResponse {
        try post(
            context: context,
            command: "scroll",
            path: "/bcu/v1/browser/scroll",
            request: request
        )
    }

    func reload(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserReloadRequest
    ) throws -> BrowserGetStateResponse {
        try post(
            context: context,
            command: "reload",
            path: "/bcu/v1/browser/reload",
            request: request
        )
    }

    func close(
        context: RegisteredBrowserSurfaceContext,
        request: BrowserCloseRequest
    ) throws -> BrowserCloseResponse {
        try post(
            context: context,
            command: "close",
            path: "/bcu/v1/browser/close",
            request: request
        )
    }

    private func post<Request: Codable & Sendable, Response: Decodable>(
        context: RegisteredBrowserSurfaceContext,
        command: String,
        path: String,
        request: Request
    ) throws -> Response {
        guard let baseURL = context.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              baseURL.isEmpty == false else {
            throw BrowserSurfaceError.unsupportedRegisteredProvider(context.target.targetID)
        }
        guard let providerBaseURL = URL(string: baseURL) else {
            throw BrowserSurfaceError.providerBridgeFailed("Provider '\(context.providerID)' supplied invalid baseURL '\(baseURL)'.")
        }
        let url = appendingPath(path, to: providerBaseURL)

        let envelope = BrowserProviderCommandEnvelopeDTO(
            contractVersion: ContractVersion.current,
            providerID: context.providerID,
            providerDisplayName: context.displayName,
            protocolVersion: context.protocolVersion,
            surfaceID: context.surfaceID,
            targetID: context.target.targetID,
            command: command,
            request: request
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 15
        urlRequest.httpBody = try JSONSupport.encoder.encode(envelope)

        let result = SynchronousHTTPClient.post(urlRequest)
        switch result {
        case .success(let response):
            guard (200..<300).contains(response.statusCode) else {
                let bodyPreview = String(data: response.body.prefix(1_000), encoding: .utf8) ?? "<non-utf8 body>"
                throw BrowserSurfaceError.providerBridgeFailed(
                    "Provider '\(context.providerID)' returned HTTP \(response.statusCode) for \(command): \(bodyPreview)"
                )
            }
            do {
                return try JSONSupport.decoder.decode(Response.self, from: response.body)
            } catch {
                throw BrowserSurfaceError.providerBridgeFailed(
                    "Provider '\(context.providerID)' returned an invalid \(String(describing: Response.self)) for \(command): \(error)"
                )
            }
        case .failure(let error):
            throw BrowserSurfaceError.providerBridgeFailed(
                "Provider '\(context.providerID)' request for \(command) failed: \(error.localizedDescription)"
            )
        }
    }

    private func appendingPath(_ path: String, to baseURL: URL) -> URL {
        path.split(separator: "/").reduce(baseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }
}

private struct SynchronousHTTPResponse {
    let statusCode: Int
    let body: Data
}

private enum SynchronousHTTPClient {
    static func post(_ request: URLRequest) -> Result<SynchronousHTTPResponse, Error> {
        let semaphore = DispatchSemaphore(value: 0)
        let box = SynchronousHTTPResultBox()

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let resolved: Result<SynchronousHTTPResponse, Error>
            if let error {
                resolved = .failure(error)
            } else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                resolved = .success(SynchronousHTTPResponse(statusCode: statusCode, body: data ?? Data()))
            }

            box.set(resolved)
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        return box.value ?? .failure(URLError(.unknown))
    }
}

private final class SynchronousHTTPResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<SynchronousHTTPResponse, Error>?

    var value: Result<SynchronousHTTPResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ result: Result<SynchronousHTTPResponse, Error>) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}
