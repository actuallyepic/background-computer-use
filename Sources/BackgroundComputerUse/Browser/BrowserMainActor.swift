import Foundation

private final class BrowserAsyncResultBox<T: Sendable>: @unchecked Sendable {
    var result: Result<T, Error>?
}

enum BrowserMainActor {
    static func sync<T: Sendable>(_ body: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try body()
            }
        }

        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated {
                try body()
            }
        }
    }

    static func runBlocking<T: Sendable>(
        timeout: TimeInterval = 10,
        _ operation: @escaping @MainActor () async throws -> T
    ) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = BrowserAsyncResultBox<T>()

        Task { @MainActor in
            do {
                box.result = .success(try await operation())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        if Thread.isMainThread {
            let deadline = Date().addingTimeInterval(timeout)
            while semaphore.wait(timeout: .now()) == .timedOut {
                if Date() > deadline {
                    throw BrowserSurfaceError.timedOut("Timed out waiting for main-actor browser work.")
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
        } else if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw BrowserSurfaceError.timedOut("Timed out waiting for main-actor browser work.")
        }

        switch box.result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw BrowserSurfaceError.timedOut("Browser work finished without returning a result.")
        }
    }
}
