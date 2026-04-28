import CodexAppServerClient
import Foundation

struct SpotifyCodexModelOption: Sendable, Equatable {
    let id: String
    let model: String
    let displayName: String
    let isDefault: Bool
    let defaultReasoning: String
    let supportedReasoning: [String]
}

struct SpotifyCodexReasoningTrace: Identifiable, Sendable, Equatable {
    let id: String
    var title: String
    var text: String
    var isComplete: Bool
}

struct SpotifyCodexChatMessage: Sendable, Equatable {
    enum Role: Sendable {
        case user
        case assistant
    }

    enum Phase: Sendable {
        case complete
        case thinking
        case responding
    }

    let id: UUID
    let role: Role
    var text: String
    var traces: [SpotifyCodexReasoningTrace]
    var phase: Phase
    let createdAt: Date

    init(
        id: UUID,
        role: Role,
        text: String,
        traces: [SpotifyCodexReasoningTrace] = [],
        phase: Phase = .complete,
        createdAt: Date
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.traces = traces
        self.phase = phase
        self.createdAt = createdAt
    }
}

@MainActor
final class SpotifyCodexSidebarController {
    var onStatusChanged: (String) -> Void = { _ in }
    var onProviderContextChanged: (String) -> Void = { _ in }
    var onModelsChanged: ([SpotifyCodexModelOption], String?, [String], String?) -> Void = { _, _, _, _ in }
    var onBusyChanged: (Bool) -> Void = { _ in }
    var onMessageAppended: (SpotifyCodexChatMessage) -> Void = { _ in }
    var onMessageUpdated: (SpotifyCodexChatMessage) -> Void = { _ in }
    var onMessagesCleared: () -> Void = {}

    private let workspaceURL: URL
    private let sidecar: PersistentCodexAppServer
    private let preferredModelName = "gpt-5.5"
    private let legacyFallbackModelName = "gpt-5.4"
    private let preferredServiceTier = ServiceTier.fast
    private var client: CodexClient?
    private var threadID: String?
    private var hasValidatedThread = false
    private var controlPlaneBaseURL: URL?
    private var browserTargetID: String?
    private var models: [SpotifyCodexModelOption] = []
    private var selectedModelID: String?
    private var selectedReasoning: String?
    private var approvalTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var modelRefreshTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var isBusy = false
    private var conversationID = UUID()
    private var activeTurn: (threadID: String, turnID: String)?
    private var recentPageEvents: [String] = []

    init(workspaceURL: URL) {
        self.workspaceURL = workspaceURL
        self.sidecar = PersistentCodexAppServer(workspaceURL: workspaceURL)
        self.threadID = Self.loadPersistedThreadID(workspaceURL: workspaceURL)
    }

    func start() {
        onProviderContextChanged(providerContextSummary())
        Task {
            do {
                let client = try await connectIfNeeded()
                try await refreshModels(client: client)
                try await ensureThread(client: client)
                startModelRefreshLoop()
            } catch {
                NSLog("Spotify AI startup failed: \(error.localizedDescription)")
                reportStatus("Spotify AI unavailable: \(error.localizedDescription)")
            }
        }
    }

    func updateBCUContext(baseURL: URL?, browserTargetID: String?) {
        self.controlPlaneBaseURL = baseURL
        self.browserTargetID = browserTargetID
        onProviderContextChanged(providerContextSummary())
    }

    func recordPageEvent(type: String, payload: String) {
        let line = payload.isEmpty ? type : "\(type): \(payload)"
        recentPageEvents.append(line)
        if recentPageEvents.count > 8 {
            recentPageEvents.removeFirst(recentPageEvents.count - 8)
        }
    }

    func refreshModels() {
        Task {
            do {
                try await refreshModels(client: try await connectIfNeeded())
            } catch {
                reportStatus("Model refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func selectModel(id: String?) {
        selectedModelID = id
        let option = selectedModel
        selectedReasoning = option?.supportedReasoning.first(where: { $0 == selectedReasoning })
            ?? option?.defaultReasoning
            ?? selectedReasoning
        publishModels()
    }

    func selectReasoning(_ rawValue: String?) {
        selectedReasoning = rawValue
        publishModels()
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        let currentConversationID = conversationID

        let userMessage = SpotifyCodexChatMessage(id: UUID(), role: .user, text: trimmed, createdAt: Date())
        onMessageAppended(userMessage)

        var assistantMessage = SpotifyCodexChatMessage(
            id: UUID(),
            role: .assistant,
            text: "",
            phase: .thinking,
            createdAt: Date()
        )
        onMessageAppended(assistantMessage)

        isBusy = true
        onBusyChanged(true)

        sendTask = Task {
            do {
                let client = try await connectIfNeeded()
                if models.isEmpty {
                    try await refreshModels(client: client)
                }
                let turn = try await startTurnRecoveringThread(client: client, text: trimmed)
                activeTurn = (threadID: turn.threadID, turnID: turn.turnID)
                var output = ""

                for await event in turn.events {
                    if Task.isCancelled { break }
                    guard conversationID == currentConversationID else { return }
                    guard case .notification(let notification) = event else { continue }

                    switch notification {
                    case .turnStarted(let started) where started.turn.id == turn.turnID:
                        assistantMessage.phase = .thinking
                        onMessageUpdated(assistantMessage)
                    case .itemStarted(let started) where started.turnId == turn.turnID:
                        if started.item.type == .reasoning {
                            upsertReasoningTrace(
                                in: &assistantMessage,
                                id: reasoningTraceID(itemID: started.item.id, summaryIndex: 0),
                                title: "Thinking"
                            )
                            assistantMessage.phase = .thinking
                            onMessageUpdated(assistantMessage)
                        } else if let title = activityTraceTitle(for: started.item) {
                            upsertReasoningTrace(
                                in: &assistantMessage,
                                id: activityTraceID(itemID: started.item.id),
                                title: title,
                                text: activityTraceText(forStartedItem: started.item)
                            )
                            assistantMessage.phase = .thinking
                            onMessageUpdated(assistantMessage)
                        }
                    case .itemReasoningSummaryPartAdded(let part) where part.turnId == turn.turnID:
                        upsertReasoningTrace(
                            in: &assistantMessage,
                            id: reasoningTraceID(itemID: part.itemId, summaryIndex: part.summaryIndex),
                            title: "Thinking"
                        )
                        assistantMessage.phase = .thinking
                        onMessageUpdated(assistantMessage)
                    case .itemReasoningSummaryTextDelta(let delta) where delta.turnId == turn.turnID:
                        appendReasoningTraceDelta(
                            delta.delta,
                            to: &assistantMessage,
                            id: reasoningTraceID(itemID: delta.itemId, summaryIndex: delta.summaryIndex),
                            title: "Thinking"
                        )
                        assistantMessage.phase = .thinking
                        onMessageUpdated(assistantMessage)
                    case .itemAgentMessageDelta(let delta) where delta.turnId == turn.turnID:
                        output += delta.delta
                        assistantMessage.text = output
                        assistantMessage.phase = .responding
                        onMessageUpdated(assistantMessage)
                    case .itemCompleted(let completed) where completed.turnId == turn.turnID:
                        if completed.item.type == .agentMessage,
                           let text = completed.item.text,
                           !text.isEmpty {
                            output = text
                            assistantMessage.text = text
                            assistantMessage.phase = .responding
                        }
                        if activityTraceTitle(for: completed.item) != nil {
                            setReasoningTraceText(
                                activityCompletionText(for: completed.item),
                                in: &assistantMessage,
                                id: activityTraceID(itemID: completed.item.id),
                                title: activityTraceTitle(for: completed.item) ?? "Action"
                            )
                        }
                        markReasoningTracesComplete(for: completed.item.id, in: &assistantMessage)
                        onMessageUpdated(assistantMessage)
                    case .turnCompleted(let completed) where completed.turn.id == turn.turnID:
                        if output.isEmpty && assistantMessage.traces.isEmpty {
                            assistantMessage.text = "Done."
                        }
                        assistantMessage.phase = .complete
                        onMessageUpdated(assistantMessage)
                        activeTurn = nil
                        finishSend(conversationID: currentConversationID)
                        return
                    case .error(let error) where error.turnId == turn.turnID:
                        if error.willRetry {
                            reportStatus("Retrying")
                            continue
                        }
                        if requiresNewerCodex(for: error.error) {
                            selectedModelID = defaultModel?.id
                            publishModels()
                        }
                        assistantMessage.text = userFacingTurnErrorMessage(for: error.error)
                        assistantMessage.phase = .complete
                        onMessageUpdated(assistantMessage)
                        reportStatus("Something went wrong")
                        activeTurn = nil
                        finishSend(conversationID: currentConversationID)
                        return
                    default:
                        continue
                    }
                }

                activeTurn = nil
                finishSend(conversationID: currentConversationID)
            } catch is CancellationError {
                activeTurn = nil
                finishSend(conversationID: currentConversationID)
            } catch {
                if conversationID == currentConversationID {
                    assistantMessage.text = userFacingErrorMessage(for: error)
                    assistantMessage.phase = .complete
                    onMessageUpdated(assistantMessage)
                }
                reportStatus("Something went wrong")
                activeTurn = nil
                finishSend(conversationID: currentConversationID)
            }
        }
    }

    func resetChat() {
        let previousTurn = activeTurn
        conversationID = UUID()
        activeTurn = nil
        sendTask?.cancel()
        sendTask = nil
        isBusy = false
        onBusyChanged(false)
        onMessagesCleared()
        threadID = nil
        hasValidatedThread = false
        Self.deletePersistedThreadID(workspaceURL: workspaceURL)
        if let previousTurn, let client {
            Task {
                try? await client.call(
                    RPC.TurnInterrupt.self,
                    params: TurnInterruptParams(threadId: previousTurn.threadID, turnId: previousTurn.turnID)
                )
            }
        }
        Task {
            do {
                _ = try await createThread(client: try await connectIfNeeded())
            } catch {
                reportStatus("New chat failed: \(error.localizedDescription)")
            }
        }
    }

    func shutdown() {
        sendTask?.cancel()
        modelRefreshTask?.cancel()
        approvalTask?.cancel()
        connectionTask?.cancel()
        guard let client else { return }
        Task {
            await client.disconnect()
        }
    }

    private var selectedModel: SpotifyCodexModelOption? {
        if let selectedModelID,
           let model = models.first(where: { $0.id == selectedModelID }) {
            return model
        }
        return defaultModel
    }

    private var defaultModel: SpotifyCodexModelOption? {
        models.first(where: { $0.model == preferredModelName })
            ?? models.first(where: \.isDefault)
            ?? models.first(where: { $0.model == legacyFallbackModelName })
            ?? models.first
    }

    private var selectedModelName: String {
        selectedModel?.model ?? preferredModelName
    }

    private func connectIfNeeded() async throws -> CodexClient {
        if let client {
            return client
        }

        onStatusChanged("Starting")
        let websocketURL = try await sidecar.resolveWebSocketURL()
        let client = try await CodexClient.connect(
            .remote(
                RemoteServerOptions(
                    url: websocketURL,
                    codexVersion: CodexBindingMetadata.codexVersion
                )
            ),
            options: CodexClientOptions(
                experimentalAPI: true,
                versionPolicy: .exact,
                clientInfo: ClientInfo(
                    name: "spotify_webview_app",
                    title: "Spotify WebView App",
                    version: "0.1.0"
                )
            )
        )
        self.client = client
        startApprovalResponder(client: client)
        startConnectionMonitor(client: client)
        onStatusChanged("Connected")
        return client
    }

    @discardableResult
    private func ensureThread(client: CodexClient) async throws -> String {
        if let threadID, hasValidatedThread {
            return threadID
        }

        if let persisted = threadID ?? Self.loadPersistedThreadID(workspaceURL: workspaceURL) {
            do {
                let response = try await client.call(
                    RPC.ThreadResume.self,
                    params: ThreadResumeParams(
                        approvalPolicy: .enumeration(.never),
                        cwd: workspaceURL.path,
                        developerInstructions: developerInstructions(),
                        model: selectedModelName,
                        persistExtendedHistory: true,
                        sandbox: .dangerFullAccess,
                        serviceTier: preferredServiceTier,
                        threadId: persisted
                    )
                )
                threadID = response.thread.id
                hasValidatedThread = true
                Self.persistThreadID(response.thread.id, workspaceURL: workspaceURL)
                reportStatus("Resumed chat")
                return response.thread.id
            } catch let error as CodexClientError where error.isThreadNotFound {
                threadID = nil
                hasValidatedThread = false
                Self.deletePersistedThreadID(workspaceURL: workspaceURL)
                reportStatus("Starting fresh chat")
            } catch {
                threadID = nil
                hasValidatedThread = false
                reportStatus("Could not resume saved thread: \(error.localizedDescription)")
            }
        }

        return try await createThread(client: client)
    }

    @discardableResult
    private func createThread(client: CodexClient) async throws -> String {
        if models.isEmpty {
            try await refreshModels(client: client)
        }
        let response = try await client.call(
            RPC.ThreadStart.self,
            params: ThreadStartParams(
                approvalPolicy: .enumeration(.never),
                cwd: workspaceURL.path,
                developerInstructions: developerInstructions(),
                ephemeral: false,
                model: selectedModelName,
                persistExtendedHistory: true,
                sandbox: .dangerFullAccess,
                serviceName: "spotify-webview-app",
                serviceTier: preferredServiceTier
            )
        )
        threadID = response.thread.id
        hasValidatedThread = true
        Self.persistThreadID(response.thread.id, workspaceURL: workspaceURL)
        reportStatus("New chat")
        return response.thread.id
    }

    private struct TurnStartContext {
        let threadID: String
        let turnID: String
        let events: AsyncStream<CodexEvent>
    }

    private func startTurnRecoveringThread(client: CodexClient, text: String) async throws -> TurnStartContext {
        do {
            return try await startTurnContext(client: client, text: text)
        } catch let error as CodexClientError where error.isThreadNotFound {
            reportStatus("Refreshing chat")
            threadID = nil
            hasValidatedThread = false
            Self.deletePersistedThreadID(workspaceURL: workspaceURL)
            _ = try await createThread(client: client)
            return try await startTurnContext(client: client, text: text)
        }
    }

    private func startTurnContext(client: CodexClient, text: String) async throws -> TurnStartContext {
        let threadID = try await ensureThread(client: client)
        let events = await client.events(forThread: threadID)
        let turnID = try await startTurn(client: client, threadID: threadID, text: text)
        return TurnStartContext(threadID: threadID, turnID: turnID, events: events)
    }

    private func startTurn(client: CodexClient, threadID: String, text: String) async throws -> String {
        let response = try await client.call(
            RPC.TurnStart.self,
            params: TurnStartParams(
                approvalPolicy: .enumeration(.never),
                cwd: workspaceURL.path,
                effort: selectedReasoning.flatMap(ReasoningEffort.init(rawValue:)),
                input: [.text(turnPrompt(for: text))],
                model: selectedModelName,
                serviceTier: preferredServiceTier,
                summary: .auto,
                threadId: threadID
            )
        )
        return response.turn.id
    }

    private func reasoningTraceID(itemID: String, summaryIndex: Int) -> String {
        "\(itemID)#\(summaryIndex)"
    }

    private func activityTraceID(itemID: String) -> String {
        "\(itemID)#activity"
    }

    private func upsertReasoningTrace(
        in message: inout SpotifyCodexChatMessage,
        id: String,
        title: String,
        text: String? = nil
    ) {
        if let index = message.traces.firstIndex(where: { $0.id == id }) {
            if let text, message.traces[index].text.isEmpty {
                message.traces[index].text = text
            }
            return
        }
        message.traces.append(
            SpotifyCodexReasoningTrace(
                id: id,
                title: title,
                text: text ?? "",
                isComplete: false
            )
        )
    }

    private func setReasoningTraceText(
        _ text: String,
        in message: inout SpotifyCodexChatMessage,
        id: String,
        title: String
    ) {
        upsertReasoningTrace(in: &message, id: id, title: title)
        guard let index = message.traces.firstIndex(where: { $0.id == id }) else { return }
        message.traces[index].text = text
    }

    private func appendReasoningTraceDelta(
        _ delta: String,
        to message: inout SpotifyCodexChatMessage,
        id: String,
        title: String
    ) {
        upsertReasoningTrace(in: &message, id: id, title: title)
        guard let index = message.traces.firstIndex(where: { $0.id == id }) else { return }
        message.traces[index].text += delta
    }

    private func markReasoningTracesComplete(for itemID: String, in message: inout SpotifyCodexChatMessage) {
        for index in message.traces.indices where message.traces[index].id.hasPrefix("\(itemID)#") {
            message.traces[index].isComplete = true
        }
    }

    private func activityTraceTitle(for item: ThreadItem) -> String? {
        switch item.type {
        case .commandExecution:
            return "Action"
        case .dynamicToolCall, .mcpToolCall:
            return "Tool"
        case .fileChange:
            return "File update"
        case .webSearch:
            return "Search"
        default:
            return nil
        }
    }

    private func activityTraceText(forStartedItem item: ThreadItem) -> String {
        switch item.type {
        case .commandExecution:
            return "Using Spotify controls..."
        case .dynamicToolCall, .mcpToolCall:
            if let tool = item.tool, !tool.isEmpty {
                return "Using \(tool)..."
            }
            return "Using a tool..."
        case .fileChange:
            return "Updating files..."
        case .webSearch:
            if let query = item.query, !query.isEmpty {
                return "Searching for \(query)..."
            }
            return "Searching..."
        default:
            return "Working..."
        }
    }

    private func activityCompletionText(for item: ThreadItem) -> String {
        switch item.type {
        case .commandExecution:
            if let exitCode = item.exitCode, exitCode != 0 {
                let output = item.aggregatedOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.isEmpty {
                    return "Action failed with exit code \(exitCode)."
                }
                return "Action failed with exit code \(exitCode).\n\(Self.truncatedActivityOutput(output))"
            }
            return "Action completed."
        case .dynamicToolCall, .mcpToolCall:
            if item.success == false {
                return "Tool call failed."
            }
            return "Tool call completed."
        case .fileChange:
            return "File update completed."
        case .webSearch:
            return "Search completed."
        default:
            return "Completed."
        }
    }

    private static func truncatedActivityOutput(_ output: String) -> String {
        let limit = 480
        guard output.count > limit else { return output }
        return "\(output.prefix(limit))..."
    }

    private func refreshModels(client: CodexClient) async throws {
        let response = try await client.call(
            RPC.ModelList.self,
            params: ModelListParams(includeHidden: false, limit: 200)
        )
        models = response.data.map { model in
            let supported = model.supportedReasoningEfforts.map(\.reasoningEffort.rawValue)
            return SpotifyCodexModelOption(
                id: model.id,
                model: model.model,
                displayName: model.displayName,
                isDefault: model.isDefault,
                defaultReasoning: model.defaultReasoningEffort.rawValue,
                supportedReasoning: supported.isEmpty ? [model.defaultReasoningEffort.rawValue] : supported
            )
        }
        if selectedModelID == nil || !models.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = defaultModel?.id
        }
        if selectedReasoning == nil {
            selectedReasoning = selectedModel?.defaultReasoning
        }
        publishModels()
    }

    private func publishModels() {
        let reasoning = selectedModel?.supportedReasoning ?? ReasoningEffort.allCasesForUI
        if selectedReasoning == nil || !reasoning.contains(selectedReasoning ?? "") {
            selectedReasoning = selectedModel?.defaultReasoning ?? reasoning.first
        }
        onModelsChanged(models, selectedModel?.id, reasoning, selectedReasoning)
    }

    private func startApprovalResponder(client: CodexClient) {
        approvalTask?.cancel()
        approvalTask = Task {
            let events = await client.events()
            for await event in events {
                if Task.isCancelled { break }
                guard case .serverRequest(let request) = event,
                      let approval = request.asApprovalRequest else {
                    continue
                }
                try? await client.respond(to: approval, intent: .allowForSession)
            }
        }
    }

    private func startConnectionMonitor(client: CodexClient) {
        connectionTask?.cancel()
        connectionTask = Task {
            let states = await client.connectionStates()
            for await state in states {
                if Task.isCancelled { break }
                switch state {
                case .connecting:
                    onStatusChanged("Connecting")
                case .connected:
                    onStatusChanged("Connecting")
                case .initialized:
                    onStatusChanged("Spotify AI")
                case .disconnected:
                    reportStatus("Disconnected")
                }
            }
        }
    }

    private func startModelRefreshLoop() {
        modelRefreshTask?.cancel()
        modelRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                if Task.isCancelled { break }
                do {
                    try await refreshModels(client: try await connectIfNeeded())
                } catch {
                    reportStatus("Model refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func finishSend(conversationID id: UUID? = nil) {
        if let id, id != conversationID {
            return
        }
        isBusy = false
        onBusyChanged(false)
    }

    private func reportStatus(_ text: String) {
        onStatusChanged(text)
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        if let error = error as? CodexClientError, error.isThreadNotFound {
            return "I opened a fresh chat. Please send that again."
        }
        return "I could not finish that request. Please try again."
    }

    private func userFacingTurnErrorMessage(for error: TurnError) -> String {
        let message = nestedJSONErrorMessage(error.message) ?? error.message
        if requiresNewerCodex(message: message) {
            return "That model requires a newer Codex build. I switched to \(selectedModelName); please send that again."
        }
        return message.isEmpty ? "I could not finish that request. Please try again." : message
    }

    private func requiresNewerCodex(for error: TurnError) -> Bool {
        requiresNewerCodex(message: nestedJSONErrorMessage(error.message) ?? error.message)
    }

    private func requiresNewerCodex(message: String) -> Bool {
        message.localizedCaseInsensitiveContains("requires a newer version of Codex")
    }

    private func nestedJSONErrorMessage(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }

    private func providerContextSummary() -> String {
        let base = controlPlaneBaseURL?.absoluteString ?? "BCU pending"
        let target = browserTargetID ?? "spotify-main pending"
        return "\(base) / \(target)"
    }

    private func developerInstructions() -> String {
        """
        You are embedded in SpotifyWebViewApp, a native macOS app that hosts a Spotify WKWebView.
        Work in this repository: \(workspaceURL.path)

        The app registers its webview with BackgroundComputerUse as provider xyz.dubdub.spotify-webview, surface spotify-main.
        Current BCU base URL: \(controlPlaneBaseURL?.absoluteString ?? "not registered yet")
        Current browser target ID: \(browserTargetID ?? "not registered yet")

        Use the BCU HTTP API as the control plane for the Spotify webview and local desktop automation.
        Start with GET /v1/bootstrap and GET /v1/routes.
        Browser routes:
        - POST /v1/browser/list_targets with {"includeRegistered":true}
        - POST /v1/browser/get_state with {"browser":"TARGET_ID","imageMode":"path"}
        - POST /v1/browser/evaluate_js with {"browser":"TARGET_ID","javaScript":"..."}
        - POST /v1/browser/inject_js with {"browser":"TARGET_ID","scriptID":"...","javaScript":"...","injectImmediately":true,"persistAcrossReloads":true}
        - POST /v1/browser/click, /v1/browser/type_text, /v1/browser/scroll
        Native sidebar control from the Spotify webview:
        - evaluate window.__bcu.emit("spotify.sidebar.open", {source:"codex"})
        - evaluate window.__bcu.emit("spotify.sidebar.close", {source:"codex"})
        - evaluate window.__bcu.emit("spotify.sidebar.toggle", {source:"codex"})
        Desktop routes include /v1/list_apps, /v1/list_windows, /v1/get_window_state, /v1/click, /v1/type_text, /v1/press_key, and /v1/scroll.

        You may edit this repo and rebuild the app with swift build. Keep changes scoped and preserve the provider SDK surface.
        If the app relaunches, resume this thread and continue from the persisted context.
        """
    }

    private func turnPrompt(for text: String) -> String {
        let pageEvents = recentPageEvents.isEmpty
            ? "none"
            : recentPageEvents.suffix(5).joined(separator: "\n")
        return """
        Runtime context:
        - BCU base URL: \(controlPlaneBaseURL?.absoluteString ?? "not registered yet")
        - Spotify browser target ID: \(browserTargetID ?? "not registered yet")
        - Provider ID: xyz.dubdub.spotify-webview
        - Surface ID: spotify-main
        - Repository: \(workspaceURL.path)
        - Native sidebar events: window.__bcu.emit("spotify.sidebar.open" | "spotify.sidebar.close" | "spotify.sidebar.toggle", {source:"codex"})
        - Recent native/web app events:
        \(pageEvents)

        User:
        \(text)
        """
    }

    private static func threadIDURL(workspaceURL: URL) -> URL {
        workspaceURL
            .appendingPathComponent(".bcu", isDirectory: true)
            .appendingPathComponent("spotify-codex-thread-id.txt")
    }

    private static func loadPersistedThreadID(workspaceURL: URL) -> String? {
        let url = threadIDURL(workspaceURL: workspaceURL)
        guard let value = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func persistThreadID(_ threadID: String, workspaceURL: URL) {
        let url = threadIDURL(workspaceURL: workspaceURL)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? threadID.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func deletePersistedThreadID(workspaceURL: URL) {
        try? FileManager.default.removeItem(at: threadIDURL(workspaceURL: workspaceURL))
    }
}

private extension ReasoningEffort {
    static let allCasesForUI = ["minimal", "low", "medium", "high", "xhigh"]
}

private struct PersistentCodexAppServer {
    private struct Manifest: Codable {
        let websocketURL: String
        let codexVersion: String
        let processID: Int32
        let logPath: String
        let startedAt: Date
    }

    let workspaceURL: URL

    func resolveWebSocketURL() async throws -> URL {
        if let manifest = readManifest(),
           manifest.codexVersion == CodexBindingMetadata.codexVersion,
           let url = URL(string: manifest.websocketURL),
           await isHealthy(websocketURL: url) {
            return url
        }
        return try await launch()
    }

    private func launch() async throws -> URL {
        let directory = supportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let logURL = directory.appendingPathComponent("app-server-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "ws://127.0.0.1:0"]
        process.currentDirectoryURL = workspaceURL
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = logHandle
        try process.run()

        for _ in 0..<120 {
            if let url = parseWebSocketURL(from: logURL),
               await isHealthy(websocketURL: url) {
                writeManifest(
                    Manifest(
                        websocketURL: url.absoluteString,
                        codexVersion: CodexBindingMetadata.codexVersion,
                        processID: process.processIdentifier,
                        logPath: logURL.path,
                        startedAt: Date()
                    )
                )
                return url
            }
            if !process.isRunning {
                throw SidebarCodexError.launchFailed(readLog(logURL))
            }
            try await Task.sleep(for: .milliseconds(250))
        }

        throw SidebarCodexError.launchFailed("Timed out waiting for codex app-server.")
    }

    private var supportDirectory: URL {
        workspaceURL
            .appendingPathComponent(".bcu", isDirectory: true)
            .appendingPathComponent("spotify-codex-app-server", isDirectory: true)
    }

    private var manifestURL: URL {
        supportDirectory.appendingPathComponent("manifest.json")
    }

    private func readManifest() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private func writeManifest(_ manifest: Manifest) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func isHealthy(websocketURL: URL) async -> Bool {
        guard var components = URLComponents(url: websocketURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        components.scheme = "http"
        components.path = "/healthz"
        guard let healthURL = components.url else { return false }

        do {
            let (_, response) = try await URLSession.shared.data(from: healthURL)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private func parseWebSocketURL(from logURL: URL) -> URL? {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"listening on:\s*(ws://127\.0\.0\.1:\d+)"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.matches(in: text, range: range).last,
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return URL(string: String(text[matchRange]))
    }

    private func readLog(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? "No app-server log output."
    }
}

private enum SidebarCodexError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Codex app-server launch failed: \(message)"
        }
    }
}
