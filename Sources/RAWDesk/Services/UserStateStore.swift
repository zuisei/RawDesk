import Foundation

/// JSON-backed store of per-asset user state in Application Support.
/// Keyed by stable PhotoAsset.id.
public final class UserStateStore: @unchecked Sendable {

    public static let shared = UserStateStore()

    private let storeURL: URL
    private let queue = DispatchQueue(label: "rawdesk.userstate.store")
    private var cache: [String: PhotoUserState] = [:]
    private var loaded = false

    public init(directory: URL? = nil) {
        let dir = RAWDeskStorageDirectory.resolve(directory)
        self.storeURL = dir.appendingPathComponent("user_state.json")
    }

    public func loadAll() -> [String: PhotoUserState] {
        queue.sync {
            if loaded { return cache }
            loaded = true
            guard let data = try? Data(contentsOf: storeURL) else { return cache }
            do {
                cache = try JSONDecoder().decode([String: PhotoUserState].self, from: data)
            } catch {
                // Corrupt JSON: keep a backup once, start fresh.
                let backup = storeURL.appendingPathExtension("corrupt.\(Int(Date().timeIntervalSince1970))")
                try? FileManager.default.moveItem(at: storeURL, to: backup)
                cache = [:]
            }
            return cache
        }
    }

    public func get(id: String) -> PhotoUserState {
        queue.sync {
            if !loaded { _ = loadAllLocked() }
            return cache[id] ?? .empty
        }
    }

    public func set(id: String, state: PhotoUserState) {
        queue.sync {
            if !loaded { _ = loadAllLocked() }
            cache[id] = state
            persistLocked()
        }
    }

    public func set(statesByID: [String: PhotoUserState]) {
        guard !statesByID.isEmpty else { return }
        queue.sync {
            if !loaded { _ = loadAllLocked() }
            for (id, state) in statesByID {
                cache[id] = state
            }
            persistLocked()
        }
    }

    public func remove(id: String) {
        queue.sync {
            if !loaded { _ = loadAllLocked() }
            guard cache.removeValue(forKey: id) != nil else { return }
            persistLocked()
        }
    }

    private func loadAllLocked() -> [String: PhotoUserState] {
        loaded = true
        guard let data = try? Data(contentsOf: storeURL) else { return cache }
        if let decoded = try? JSONDecoder().decode([String: PhotoUserState].self, from: data) {
            cache = decoded
        }
        return cache
    }

    private func persistLocked() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cache)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            // Best effort; do not crash.
        }
    }
}
