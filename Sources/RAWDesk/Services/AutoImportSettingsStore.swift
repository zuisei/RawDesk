import Foundation

public final class AutoImportSettingsStore:
    @unchecked Sendable {

    public static let shared = AutoImportSettingsStore()

    private struct StoredSettings: Codable {
        var settings: AutoImportSettings
        var watchedFolderBookmark: Data?
        var destinationFolderBookmark: Data?
    }

    private let storeURL: URL
    private let queue = DispatchQueue(
        label: "rawdesk.auto-import.settings"
    )

    public init(directory: URL? = nil) {
        let directory = RAWDeskStorageDirectory.resolve(directory)
        storeURL = directory.appendingPathComponent(
            "auto_import_settings.json"
        )
    }

    public func load() -> AutoImportSettings {
        queue.sync {
            guard let data = try? Data(contentsOf: storeURL) else {
                return AutoImportSettings()
            }
            do {
                return try JSONDecoder()
                    .decode(StoredSettings.self, from: data)
                    .settings.normalized
            } catch {
                let backup = storeURL.appendingPathExtension(
                    "corrupt.\(Int(Date().timeIntervalSince1970))"
                )
                try? FileManager.default.moveItem(
                    at: storeURL,
                    to: backup
                )
                return AutoImportSettings()
            }
        }
    }

    public func save(_ rawSettings: AutoImportSettings) {
        queue.sync {
            let settings = rawSettings.normalized
            let stored = StoredSettings(
                settings: settings,
                watchedFolderBookmark:
                    settings.watchedFolderURL.flatMap {
                        SecurityScopedBookmarkStore
                            .makeReadWriteBookmark(for: $0)
                    },
                destinationFolderBookmark:
                    settings.destinationFolderURL.flatMap {
                        SecurityScopedBookmarkStore
                            .makeReadWriteBookmark(for: $0)
                    }
            )
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .prettyPrinted,
                    .sortedKeys,
                ]
                let data = try encoder.encode(stored)
                try data.write(to: storeURL, options: [.atomic])
            } catch {
                // Best effort. Runtime validation still prevents unsafe work.
            }
        }
    }
}
