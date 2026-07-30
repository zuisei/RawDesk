import Foundation

/// Application Support persistence for named color-label presets.
public final class PhotoColorLabelSetStore: @unchecked Sendable {
    public static let shared = PhotoColorLabelSetStore()

    private let storeURL: URL
    private let queue = DispatchQueue(
        label: "rawdesk.color-label-sets.store"
    )
    private var cachedLibrary: PhotoColorLabelSetLibrary?

    public init(directory: URL? = nil) {
        let directory = RAWDeskStorageDirectory.resolve(directory)
        storeURL = directory.appendingPathComponent(
            "color_label_sets.json"
        )
    }

    public func load() -> PhotoColorLabelSetLibrary {
        queue.sync {
            if let cachedLibrary { return cachedLibrary }
            guard let data = try? Data(contentsOf: storeURL),
                  let decoded = try? JSONDecoder().decode(
                      PhotoColorLabelSetLibrary.self,
                      from: data
                  ) else {
                let initial = PhotoColorLabelSetLibrary()
                cachedLibrary = initial
                return initial
            }
            let normalized = PhotoColorLabelSetLibrary(
                activeSetID: decoded.activeSetID,
                sets: decoded.sets
            )
            cachedLibrary = normalized
            return normalized
        }
    }

    public func save(_ library: PhotoColorLabelSetLibrary) {
        queue.sync {
            let normalized = PhotoColorLabelSetLibrary(
                activeSetID: library.activeSetID,
                sets: library.sets
            )
            cachedLibrary = normalized
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(normalized).write(
                    to: storeURL,
                    options: [.atomic]
                )
            } catch {
                // Keep the in-memory settings available. A future edit will
                // retry the atomic write instead of crashing the library.
            }
        }
    }
}
