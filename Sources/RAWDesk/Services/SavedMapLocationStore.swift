import Foundation

public final class SavedMapLocationStore:
    @unchecked Sendable
{
    public static let shared = SavedMapLocationStore()

    private let storeURL: URL
    private let queue = DispatchQueue(
        label: "rawdesk.saved-map-locations.store"
    )
    private var cachedLibrary: SavedMapLocationLibrary?

    public init(directory: URL? = nil) {
        let directory = RAWDeskStorageDirectory.resolve(directory)
        storeURL = directory.appendingPathComponent(
            "saved_map_locations.json"
        )
    }

    public func load() -> SavedMapLocationLibrary {
        queue.sync {
            if let cachedLibrary { return cachedLibrary }
            guard let data = try? Data(contentsOf: storeURL) else {
                let empty = SavedMapLocationLibrary()
                cachedLibrary = empty
                return empty
            }
            do {
                let decoded = try JSONDecoder().decode(
                    SavedMapLocationLibrary.self,
                    from: data
                )
                let normalized = SavedMapLocationLibrary(
                    locations: decoded.locations
                )
                cachedLibrary = normalized
                return normalized
            } catch {
                let backup = storeURL.appendingPathExtension(
                    "corrupt.\(Int(Date().timeIntervalSince1970))"
                )
                try? FileManager.default.moveItem(
                    at: storeURL,
                    to: backup
                )
                let empty = SavedMapLocationLibrary()
                cachedLibrary = empty
                return empty
            }
        }
    }

    public func save(_ library: SavedMapLocationLibrary) {
        queue.sync {
            let normalized = SavedMapLocationLibrary(
                locations: library.locations
            )
            cachedLibrary = normalized
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [
                    .prettyPrinted,
                    .sortedKeys,
                ]
                try encoder.encode(normalized).write(
                    to: storeURL,
                    options: [.atomic]
                )
            } catch {
                // Keep the in-memory copy and retry on the next edit.
            }
        }
    }
}
