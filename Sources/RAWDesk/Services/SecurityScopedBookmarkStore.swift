import Foundation

/// Helper for creating and resolving security-scoped bookmarks for sandbox-friendly folder access.
/// In an unsandboxed dev build these are still safe to call.
public enum SecurityScopedBookmarkStore {

    public static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Creates a bookmark suitable for workflows that must copy into or
    /// remove files from a user-selected folder.
    public static func makeReadWriteBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Returns the resolved URL and whether the caller must call stopAccessing.
    public static func resolve(bookmark: Data) -> (url: URL, needsStopAccess: Bool)? {
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        let started = url.startAccessingSecurityScopedResource()
        return (url, started)
    }
}
