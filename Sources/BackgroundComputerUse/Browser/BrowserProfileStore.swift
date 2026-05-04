import Foundation
@preconcurrency import WebKit

@MainActor
final class BrowserProfileStore {
    static let shared = BrowserProfileStore()

    private let mappingURL: URL
    private var cachedMappings: [String: UUID]?

    private init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let directory = appSupport
            .appending(path: "BackgroundComputerUse", directoryHint: .isDirectory)
            .appending(path: "BrowserProfiles", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        mappingURL = directory.appending(path: "profiles.json", directoryHint: .notDirectory)
    }

    func resolvedProfileID(_ requested: String?) throws -> String {
        do {
            return try BrowserProfileIDValidation.validate(requested ?? "default")
        } catch {
            throw BrowserSurfaceError.invalidRequest(String(describing: error))
        }
    }

    func dataStore(profileID requested: String?, ephemeral: Bool?) throws -> (profileID: String, dataStore: WKWebsiteDataStore) {
        let profileID = try resolvedProfileID(requested)
        if ephemeral == true {
            return (profileID, .nonPersistent())
        }
        var mappings = loadMappings()
        let uuid = mappings[profileID] ?? UUID()
        mappings[profileID] = uuid
        saveMappings(mappings)
        return (profileID, WKWebsiteDataStore(forIdentifier: uuid))
    }

    private func loadMappings() -> [String: UUID] {
        if let cachedMappings {
            return cachedMappings
        }
        guard let data = try? Data(contentsOf: mappingURL),
              let raw = try? JSONSupport.decoder.decode([String: String].self, from: data) else {
            cachedMappings = [:]
            return [:]
        }
        let mappings = raw.compactMapValues(UUID.init(uuidString:))
        cachedMappings = mappings
        return mappings
    }

    private func saveMappings(_ mappings: [String: UUID]) {
        cachedMappings = mappings
        let raw = mappings.mapValues(\.uuidString)
        guard let data = try? JSONSupport.encoder.encode(raw) else { return }
        try? data.write(to: mappingURL, options: .atomic)
    }
}
