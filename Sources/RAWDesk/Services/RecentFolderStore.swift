import Foundation

public final class RecentFolderStore: @unchecked Sendable {

    public static let shared = RecentFolderStore()

    private struct Entry: Codable {
        let path: String
        let bookmark: Data?
        let lastOpened: Date
    }

    public struct WorkspaceSnapshot:
        Codable,
        Equatable,
        Sendable
    {
        public var rootPath: String
        public var selectionID: String?
        public var photoWorkspace: PhotoWorkspaceMode

        public init(
            rootPath: String,
            selectionID: String?,
            photoWorkspace: PhotoWorkspaceMode
        ) {
            self.rootPath = rootPath
            self.selectionID = selectionID
            self.photoWorkspace = photoWorkspace
        }
    }

    private let storeURL: URL
    private let workspaceURL: URL
    private let maxEntries = 12
    private let queue = DispatchQueue(label: "rawdesk.recents")

    public init(directory: URL? = nil) {
        let dir = RAWDeskStorageDirectory.resolve(directory)
        self.storeURL = dir.appendingPathComponent("recent_folders.json")
        self.workspaceURL = dir.appendingPathComponent(
            "last_workspace.json"
        )
    }

    public func recents() -> [URL] {
        load().map { URL(fileURLWithPath: $0.path, isDirectory: true) }
    }

    public func record(url: URL, bookmark: Data?) {
        queue.sync {
            var list = load()
            list.removeAll { $0.path == url.path }
            list.insert(Entry(path: url.path, bookmark: bookmark, lastOpened: Date()), at: 0)
            if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
            save(list)
        }
    }

    public func bookmark(for url: URL) -> Data? {
        load().first(where: { $0.path == url.path })?.bookmark
    }

    public func clear() {
        queue.sync { save([]) }
    }

    public func remove(url: URL) {
        queue.sync {
            var list = load()
            list.removeAll { $0.path == url.path }
            save(list)
        }
    }

    public func workspaceSnapshot() -> WorkspaceSnapshot? {
        queue.sync {
            guard let data = try? Data(
                contentsOf: workspaceURL
            ) else {
                return nil
            }
            return try? JSONDecoder().decode(
                WorkspaceSnapshot.self,
                from: data
            )
        }
    }

    public func recordWorkspace(
        rootURL: URL,
        selectionID: String?,
        photoWorkspace: PhotoWorkspaceMode
    ) {
        queue.sync {
            let snapshot = WorkspaceSnapshot(
                rootPath:
                    rootURL.standardizedFileURL.path,
                selectionID: selectionID,
                photoWorkspace: photoWorkspace
            )
            guard let data = try? JSONEncoder().encode(
                snapshot
            ) else {
                return
            }
            try? data.write(
                to: workspaceURL,
                options: [.atomic]
            )
        }
    }

    private func load() -> [Entry] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ list: [Entry]) {
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: storeURL, options: [.atomic])
        }
    }
}
