import Foundation
import CodexAppServerProtocol

#if os(macOS)
import Darwin
#endif

#if os(macOS)
internal actor LocalCodexAppServerProcess {
    nonisolated let websocketURL: URL

    private let process: Process
    private let stderrDrainTask: Task<Void, Never>
    private let stderrBroadcaster: StderrBroadcaster

    private init(
        process: Process,
        websocketURL: URL,
        stderrDrainTask: Task<Void, Never>,
        stderrBroadcaster: StderrBroadcaster
    ) {
        self.process = process
        self.websocketURL = websocketURL
        self.stderrDrainTask = stderrDrainTask
        self.stderrBroadcaster = stderrBroadcaster
    }

    static func launch(
        options: LocalServerOptions,
        versionPolicy: VersionPolicy
    ) async throws -> LocalCodexAppServerProcess {
        let executable = options.codexExecutable ?? "codex"
        let installedVersion = try CodexVersionChecker.codexVersion(for: executable)
        try CodexVersionChecker.validate(
            actual: installedVersion,
            expected: CodexBindingMetadata.codexVersion,
            policy: versionPolicy
        )

        let port = findAvailableLoopbackPort()
        let websocketURL = URL(string: "ws://127.0.0.1:\(port)")!
        let readyURL = URL(string: "http://127.0.0.1:\(port)/readyz")!

        var serverArgs: [String] = ["app-server", "--listen", websocketURL.absoluteString]
        for key in options.extraConfig.keys.sorted() {
            serverArgs.append("-c")
            serverArgs.append("\(key)=\(options.extraConfig[key] ?? "")")
        }
        serverArgs.append(contentsOf: options.extraArguments)

        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = serverArgs
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + serverArgs
        }
        process.currentDirectoryURL = options.workingDirectory

        var environment = ProcessInfo.processInfo.environment
        if let codexHome = options.codexHome {
            try? FileManager.default.createDirectory(
                at: codexHome,
                withIntermediateDirectories: true
            )
            environment["CODEX_HOME"] = codexHome.path
        }
        for (key, value) in options.environment {
            environment[key] = value
        }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        let broadcaster = StderrBroadcaster()
        let stderrTask = Task.detached { [handle = stderrPipe.fileHandleForReading] in
            do {
                for try await line in handle.bytes.lines {
                    await broadcaster.append(String(line))
                }
            } catch {
                await broadcaster.append(error.localizedDescription)
            }
            await broadcaster.finish()
        }

        do {
            try process.run()
        } catch {
            stderrTask.cancel()
            throw CodexClientError.processLaunchFailed(error.localizedDescription)
        }

        do {
            try await waitUntilReady(
                process: process,
                readyURL: readyURL,
                broadcaster: broadcaster,
                timeoutSeconds: max(1, Double(options.readinessTimeout.components.seconds))
            )
        } catch {
            stderrTask.cancel()
            await terminate(process)
            throw error
        }

        return LocalCodexAppServerProcess(
            process: process,
            websocketURL: websocketURL,
            stderrDrainTask: stderrTask,
            stderrBroadcaster: broadcaster
        )
    }

    func stderrLines() async -> AsyncStream<String> {
        await stderrBroadcaster.subscribe()
    }

    func stop() async {
        stderrDrainTask.cancel()
        await stderrBroadcaster.finish()
        await terminate(process)
    }
}
#endif

internal enum CodexVersionChecker {
#if os(macOS)
    static func codexVersion(for executable: String) throws -> String {
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["--version"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable, "--version"]
        }

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CodexClientError.executableLookupFailed(executable)
        }

        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        guard let version = parseVersion(from: output) else {
            throw CodexClientError.invalidResponse("unable to parse codex version from: \(output)")
        }
        return version
    }
#endif

    static func parseVersion(from string: String) -> String? {
        let pattern = #"\b\d+\.\d+\.\d+\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              let matchRange = Range(match.range, in: string) else {
            return nil
        }
        return String(string[matchRange])
    }

    static func validate(actual: String, expected: String, policy: VersionPolicy) throws {
        guard policy == .exact, actual != expected else { return }
        throw CodexClientError.versionMismatch(expected: expected, actual: actual)
    }
}

private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CodexClientError.processLaunchFailed("timed out waiting for codex app-server readiness")
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}

#if os(macOS)
internal actor StderrBroadcaster {
    private let maxBufferedLines = 20
    private var recentLines: [String] = []
    private var subscribers: [UUID: AsyncStream<String>.Continuation] = [:]
    private var finished = false

    func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentLines.append(trimmed)
        if recentLines.count > maxBufferedLines {
            recentLines.removeFirst(recentLines.count - maxBufferedLines)
        }
        for (_, continuation) in subscribers {
            continuation.yield(trimmed)
        }
    }

    func subscribe() -> AsyncStream<String> {
        let id = UUID()
        let snapshot = recentLines
        return AsyncStream { continuation in
            for line in snapshot {
                continuation.yield(line)
            }
            if finished {
                continuation.finish()
                return
            }
            subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    func failureDescription(fallback: String) -> String {
        guard !recentLines.isEmpty else { return fallback }
        return "\(fallback)\n\(recentLines.joined(separator: "\n"))"
    }

    func finish() {
        finished = true
        for (_, continuation) in subscribers {
            continuation.finish()
        }
        subscribers.removeAll()
    }
}

private func waitUntilReady(
    process: Process,
    readyURL: URL,
    broadcaster: StderrBroadcaster,
    timeoutSeconds: Double
) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 1
    let session = URLSession(configuration: configuration)
    defer {
        session.invalidateAndCancel()
    }

    do {
        try await withTimeout(seconds: timeoutSeconds) {
            while true {
                if !process.isRunning {
                    let message = await broadcaster.failureDescription(
                        fallback: "codex app-server exited before becoming ready"
                    )
                    throw CodexClientError.processLaunchFailed(message)
                }

                var request = URLRequest(url: readyURL)
                request.timeoutInterval = 1
                if let (_, response) = try? await session.data(for: request),
                   let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    return
                }

                try await Task.sleep(for: .milliseconds(100))
            }
        }
    } catch let error as CodexClientError {
        throw error
    } catch {
        let message = await broadcaster.failureDescription(
            fallback: "timed out waiting for codex app-server readiness"
        )
        throw CodexClientError.processLaunchFailed(message)
    }
}

private func terminate(_ process: Process) async {
    guard process.isRunning else { return }
    process.terminate()
    for _ in 0..<30 where process.isRunning {
        try? await Task.sleep(for: .milliseconds(100))
    }
    if process.isRunning {
        kill(process.processIdentifier, SIGKILL)
    }
}

private func findAvailableLoopbackPort() -> Int {
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    guard sock >= 0 else { return 4500 }
    defer { close(sock) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = 0
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")

    var addrCopy = addr
    let bindResult = withUnsafePointer(to: &addrCopy) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { return 4500 }

    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    let getResult = withUnsafeMutablePointer(to: &addrCopy) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            getsockname(sock, sockPtr, &len)
        }
    }
    guard getResult == 0 else { return 4500 }

    return Int(UInt16(bigEndian: addrCopy.sin_port))
}
#endif
