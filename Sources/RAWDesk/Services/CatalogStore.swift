import Foundation
import SQLite3

public enum CatalogStoreError: LocalizedError, Equatable {
    case unavailable(String)
    case queryFailed(String)
    case encodingFailed
    case photoNotFound
    case replacementUnavailable
    case unsupportedReplacement
    case replacementFormatMismatch(expected: String, actual: String)
    case replacementAlreadyCataloged
    case invalidCollectionName
    case collectionNotFound
    case collectionSetNotFound
    case collectionSetDestinationInsideSource
    case collectionSetHierarchyTooDeep
    case invalidKeywordPath
    case invalidKeywordName
    case keywordDestinationInsideSource
    case keywordHierarchyTooDeep
    case keywordChangeNoEffect
    case keywordNotFound
    case photoStackRequiresMultiplePhotos
    case photoStackMembersMustShareFolder
    case photoStackAlreadyContainsSelection
    case photoStackCannotMergeMultipleStacks
    case photoStackNotFound
    case photoStackMoveUnavailable
    case photoStackSplitRequiresOneStack
    case photoStackSplitUnavailable
    case invalidPersonName
    case personNotFound
    case faceNotFound
    case peopleSelectionEmpty
    case personMergeUnchanged

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason):
            return "The photo catalog is unavailable: \(reason)"
        case let .queryFailed(reason):
            return "The photo catalog could not complete the request: \(reason)"
        case .encodingFailed:
            return "The photo catalog could not encode photo metadata."
        case .photoNotFound:
            return "The selected photo is no longer in the catalog."
        case .replacementUnavailable:
            return "The replacement file is unavailable or is not a regular file."
        case .unsupportedReplacement:
            return "The replacement is not a supported image file."
        case let .replacementFormatMismatch(expected, actual):
            return "Choose the same image format. Expected \(expected), but found \(actual)."
        case .replacementAlreadyCataloged:
            return "That replacement file is already linked to another catalog photo."
        case .invalidCollectionName:
            return "Enter a collection name."
        case .collectionNotFound:
            return "That collection is no longer in the catalog."
        case .collectionSetNotFound:
            return "That collection set is no longer in the catalog."
        case .collectionSetDestinationInsideSource:
            return "A collection set cannot be moved inside itself."
        case .collectionSetHierarchyTooDeep:
            return "The collection-set hierarchy cannot exceed 16 levels."
        case .invalidKeywordPath:
            return "The keyword hierarchy path is empty or invalid."
        case .invalidKeywordName:
            return "Enter one keyword name without a hierarchy separator."
        case .keywordDestinationInsideSource:
            return "A keyword hierarchy cannot be moved inside itself."
        case .keywordHierarchyTooDeep:
            return "The resulting keyword hierarchy would exceed 16 levels."
        case .keywordChangeNoEffect:
            return "The requested keyword change would not change the catalog."
        case .keywordNotFound:
            return "That keyword hierarchy is no longer present in the catalog."
        case .photoStackRequiresMultiplePhotos:
            return "Select at least two photos to create a stack."
        case .photoStackMembersMustShareFolder:
            return "A photo stack can contain photos from only one folder."
        case .photoStackAlreadyContainsSelection:
            return "One or more selected photos already belong to a different stack."
        case .photoStackCannotMergeMultipleStacks:
            return "Unstack the selected stacks before combining them."
        case .photoStackNotFound:
            return "That photo stack is no longer in the catalog."
        case .photoStackMoveUnavailable:
            return "That photo cannot move farther in its stack."
        case .photoStackSplitRequiresOneStack:
            return "Select photos from one expanded stack to split them."
        case .photoStackSplitUnavailable:
            return "Choose part of the stack. Selecting only the top photo or the whole stack cannot create a split."
        case .invalidPersonName:
            return "Enter a name for this person."
        case .personNotFound:
            return "That person is no longer in the catalog."
        case .faceNotFound:
            return "That face is no longer in the catalog."
        case .peopleSelectionEmpty:
            return "Choose at least one face."
        case .personMergeUnchanged:
            return "Choose a different person to merge with."
        }
    }
}

/// SQLite-backed index of every folder RAWDesk has scanned.
///
/// The existing JSON user-state store remains as a compatibility safety net,
/// while the catalog stores the complete state as a BLOB as well as indexed
/// columns for fast cross-folder searches and smart collections.
public final class CatalogStore: @unchecked Sendable {
    public static let shared = CatalogStore()

    public let databaseURL: URL
    public private(set) var startupWarning: String?

    private let queue = DispatchQueue(label: "rawdesk.catalog.sqlite")
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private static func duplicateKeySQL(
        tableAlias: String? = nil
    ) -> String {
        let prefix = tableAlias.map { "\($0)." } ?? ""
        return """
            CASE
                WHEN \(prefix)image_content_hash IS NOT NULL
                    THEN 'image:' || \(prefix)image_content_hash
                WHEN \(prefix)content_hash IS NOT NULL
                    THEN 'file:' || \(prefix)content_hash
                ELSE NULL
            END
            """
    }

    public init(directory: URL? = nil) {
        let baseDirectory = RAWDeskStorageDirectory.resolve(directory)
        try? FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        databaseURL = baseDirectory.appendingPathComponent("catalog.sqlite")
        openWithRecovery()
    }

    deinit {
        if let database {
            sqlite3_close_v2(database)
        }
    }

    public func upsert(
        assets: [PhotoAsset],
        rootURL: URL,
        recursive: Bool,
        contentHashes: [PhotoAsset.ID: String] = [:]
    ) throws {
        try queue.sync {
            try transaction {
                let rootStatement = try prepare(
                    """
                    INSERT INTO catalog_roots(path, last_scanned, recursive)
                    VALUES(?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        last_scanned = excluded.last_scanned,
                        recursive = excluded.recursive
                    """
                )
                defer { sqlite3_finalize(rootStatement) }
                bind(rootURL.path, at: 1, in: rootStatement)
                bind(Date().timeIntervalSince1970, at: 2, in: rootStatement)
                bind(recursive ? 1 : 0, at: 3, in: rootStatement)
                try stepDone(rootStatement)

                for asset in assets {
                    try upsert(
                        asset: asset,
                        rootPath: rootURL.path,
                        contentHash: contentHashes[asset.id]
                    )
                }
            }
        }
    }

    public func updateUserState(
        id: String,
        state: PhotoUserState
    ) throws {
        try queue.sync {
            try transaction {
                let data = try encode(state)
                let location = try locationIndexValues(
                    id: id,
                    state: state
                )
                let statement = try prepare(
                    """
                    UPDATE catalog_photos SET
                        state_json = ?,
                        rating = ?,
                        pick_status = ?,
                        favorite = ?,
                        color_label = ?,
                        edited = ?,
                        note = ?,
                        keyword_count = ?,
                        latitude = ?,
                        longitude = ?,
                        altitude = ?,
                        location_source = ?,
                        last_seen = ?
                    WHERE id = ?
                    """
                )
                defer { sqlite3_finalize(statement) }
                bind(data, at: 1, in: statement)
                bind(state.rating, at: 2, in: statement)
                bind(state.pickStatus.rawValue, at: 3, in: statement)
                bind(state.favorite ? 1 : 0, at: 4, in: statement)
                bind(state.colorLabel.rawValue, at: 5, in: statement)
                bind(state.adjustments.isNeutral ? 0 : 1, at: 6, in: statement)
                bind(state.note, at: 7, in: statement)
                bind(state.keywords.count, at: 8, in: statement)
                bind(location.location?.latitude, at: 9, in: statement)
                bind(location.location?.longitude, at: 10, in: statement)
                bind(location.location?.altitude, at: 11, in: statement)
                bind(location.source.rawValue, at: 12, in: statement)
                bind(Date().timeIntervalSince1970, at: 13, in: statement)
                bind(id, at: 14, in: statement)
                try stepDone(statement)
                if sqlite3_changes(try requireDatabase()) > 0 {
                    try replaceKeywords(photoID: id, keywords: state.keywords)
                }
            }
        }
    }

    public func updateUserStates(
        _ statesByID: [String: PhotoUserState]
    ) throws {
        guard !statesByID.isEmpty else { return }
        try queue.sync {
            try transaction {
                let statement = try prepare(
                    """
                    UPDATE catalog_photos SET
                        state_json = ?,
                        rating = ?,
                        pick_status = ?,
                        favorite = ?,
                        color_label = ?,
                        edited = ?,
                        note = ?,
                        keyword_count = ?,
                        latitude = ?,
                        longitude = ?,
                        altitude = ?,
                        location_source = ?,
                        last_seen = ?
                    WHERE id = ?
                    """
                )
                defer { sqlite3_finalize(statement) }
                for (id, state) in statesByID.sorted(
                    by: { $0.key < $1.key }
                ) {
                    let location = try locationIndexValues(
                        id: id,
                        state: state
                    )
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(try encode(state), at: 1, in: statement)
                    bind(state.rating, at: 2, in: statement)
                    bind(state.pickStatus.rawValue, at: 3, in: statement)
                    bind(state.favorite ? 1 : 0, at: 4, in: statement)
                    bind(
                        state.colorLabel.rawValue,
                        at: 5,
                        in: statement
                    )
                    bind(
                        state.adjustments.isNeutral ? 0 : 1,
                        at: 6,
                        in: statement
                    )
                    bind(state.note, at: 7, in: statement)
                    bind(state.keywords.count, at: 8, in: statement)
                    bind(
                        location.location?.latitude,
                        at: 9,
                        in: statement
                    )
                    bind(
                        location.location?.longitude,
                        at: 10,
                        in: statement
                    )
                    bind(
                        location.location?.altitude,
                        at: 11,
                        in: statement
                    )
                    bind(
                        location.source.rawValue,
                        at: 12,
                        in: statement
                    )
                    bind(
                        Date().timeIntervalSince1970,
                        at: 13,
                        in: statement
                    )
                    bind(id, at: 14, in: statement)
                    try stepDone(statement)
                    if sqlite3_changes(try requireDatabase()) > 0 {
                        try replaceKeywords(
                            photoID: id,
                            keywords: state.keywords
                        )
                    }
                }
            }
        }
    }

    public func previewKeywordChange(
        _ change: CatalogKeywordChange
    ) throws -> CatalogKeywordChangePreview {
        try queue.sync {
            try keywordMutationPlan(for: change).preview
        }
    }

    public func applyKeywordChange(
        _ change: CatalogKeywordChange
    ) throws -> CatalogKeywordChangeResult {
        try queue.sync {
            let plan = try keywordMutationPlan(for: change)
            guard plan.preview.affectedPhotoCount > 0
                    || plan.preview.affectedSmartCollectionCount > 0
                    || plan.preview.affectedDefinitionCount > 0 else {
                throw CatalogStoreError.keywordNotFound
            }

            try transaction {
                let updatePhoto = try prepare(
                    """
                    UPDATE catalog_photos SET
                        state_json = ?,
                        keyword_count = ?,
                        last_seen = ?
                    WHERE id = ?
                    """
                )
                defer { sqlite3_finalize(updatePhoto) }
                let now = Date().timeIntervalSince1970
                for (id, state) in plan.updatedStates {
                    sqlite3_reset(updatePhoto)
                    sqlite3_clear_bindings(updatePhoto)
                    bind(try encode(state), at: 1, in: updatePhoto)
                    bind(state.keywords.count, at: 2, in: updatePhoto)
                    bind(now, at: 3, in: updatePhoto)
                    bind(id, at: 4, in: updatePhoto)
                    try stepDone(updatePhoto)
                    try replaceKeywords(
                        photoID: id,
                        keywords: state.keywords
                    )
                }

                if !plan.updatedSmartCollections.isEmpty {
                    let updateCollection = try prepare(
                        """
                        UPDATE catalog_smart_collections
                        SET filter_json = ?
                        WHERE id = ?
                        """
                    )
                    defer { sqlite3_finalize(updateCollection) }
                    for collection in plan.updatedSmartCollections {
                        sqlite3_reset(updateCollection)
                        sqlite3_clear_bindings(updateCollection)
                        bind(
                            try encode(collection.filter),
                            at: 1,
                            in: updateCollection
                        )
                        bind(
                            collection.id.uuidString,
                            at: 2,
                            in: updateCollection
                        )
                        try stepDone(updateCollection)
                    }
                }

                if !plan.definitionKeysToDelete.isEmpty {
                    let deleteDefinition = try prepare(
                        """
                        DELETE FROM catalog_keyword_definitions
                        WHERE keyword_folded = ?
                        """
                    )
                    defer { sqlite3_finalize(deleteDefinition) }
                    for key in plan.definitionKeysToDelete {
                        sqlite3_reset(deleteDefinition)
                        sqlite3_clear_bindings(deleteDefinition)
                        bind(key, at: 1, in: deleteDefinition)
                        try stepDone(deleteDefinition)
                    }
                }

                for definition in plan.definitionsToUpsert {
                    try upsertKeywordDefinition(definition)
                }
            }

            return CatalogKeywordChangeResult(
                preview: plan.preview,
                updatedStates: plan.updatedStates,
                savedSmartCollections: plan.allSmartCollections
            )
        }
    }

    public func keywordDefinition(
        for path: String
    ) throws -> CatalogKeywordDefinition {
        try queue.sync {
            guard let normalized =
                    PhotoUserState.normalizedKeywordPath(path) else {
                throw CatalogStoreError.invalidKeywordPath
            }
            let definitions = try loadKeywordDefinitions()
            return definitions[
                PhotoUserState.foldedKeyword(normalized)
            ] ?? CatalogKeywordDefinition(path: normalized)
        }
    }

    public func saveKeywordDefinition(
        _ rawDefinition: CatalogKeywordDefinition
    ) throws {
        try queue.sync {
            let definition = CatalogKeywordDefinition(
                path: rawDefinition.path,
                synonyms: rawDefinition.synonyms,
                includeOnExport: rawDefinition.includeOnExport,
                exportSynonyms: rawDefinition.exportSynonyms,
                exportContainingKeywords:
                    rawDefinition.exportContainingKeywords
            )
            guard !definition.path.isEmpty else {
                throw CatalogStoreError.invalidKeywordPath
            }
            try transaction {
                try upsertKeywordDefinition(definition)
            }
        }
    }

    public func exportKeywords(
        for keywordPaths: [String]
    ) throws -> [String] {
        try queue.sync {
            let definitions = try loadKeywordDefinitions()
            var exported: [String] = []

            func appendDefinition(
                path: String,
                fallback: CatalogKeywordDefinition
            ) {
                let definition = definitions[
                    PhotoUserState.foldedKeyword(path)
                ] ?? fallback
                guard definition.includeOnExport else { return }
                exported.append(PhotoUserState.keywordLeaf(path))
                if definition.exportSynonyms {
                    exported.append(contentsOf: definition.synonyms)
                }
            }

            for path in PhotoUserState.normalizedKeywords(
                keywordPaths
            ) {
                let definition = definitions[
                    PhotoUserState.foldedKeyword(path)
                ] ?? CatalogKeywordDefinition(path: path)
                guard definition.includeOnExport else { continue }
                appendDefinition(path: path, fallback: definition)
                guard definition.exportContainingKeywords else {
                    continue
                }
                let segments = PhotoUserState.keywordSegments(in: path)
                guard segments.count > 1 else { continue }
                for depth in 1..<segments.count {
                    let parentPath = Array(segments.prefix(depth))
                        .joined(
                            separator:
                                PhotoUserState.keywordPathSeparator
                        )
                    appendDefinition(
                        path: parentPath,
                        fallback: CatalogKeywordDefinition(
                            path: parentPath
                        )
                    )
                }
            }
            return PhotoUserState.normalizedKeywords(exported)
        }
    }

    public func updateMetadata(
        id: String,
        metadata: PhotoMetadata
    ) throws {
        try queue.sync {
            let state = try catalogEntry(id: id)?.userState
                ?? .empty
            let location = locationIndexValues(
                state: state,
                metadata: metadata
            )
            let statement = try prepare(
                """
                UPDATE catalog_photos SET
                    metadata_json = ?,
                    capture_date = ?,
                    camera_make = ?,
                    camera_model = ?,
                    lens_model = ?,
                    latitude = ?,
                    longitude = ?,
                    altitude = ?,
                    location_source = ?
                WHERE id = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(try encode(metadata), at: 1, in: statement)
            bind(metadata.captureDate, at: 2, in: statement)
            bind(metadata.cameraMake, at: 3, in: statement)
            bind(metadata.cameraModel, at: 4, in: statement)
            bind(metadata.lensModel, at: 5, in: statement)
            bind(location.location?.latitude, at: 6, in: statement)
            bind(location.location?.longitude, at: 7, in: statement)
            bind(location.location?.altitude, at: 8, in: statement)
            bind(location.source.rawValue, at: 9, in: statement)
            bind(id, at: 10, in: statement)
            try stepDone(statement)
        }
    }

    public func entries(
        for collection: CatalogSmartCollection
    ) throws -> [CatalogEntry] {
        try queue.sync {
            let duplicateKey = Self.duplicateKeySQL()
            let condition: String
            var recentThreshold: Double?
            switch collection {
            case .allPhotos:
                condition = "missing = 0"
            case .recentlyAdded:
                condition = "missing = 0 AND indexed_at >= ?"
                recentThreshold = Date()
                    .addingTimeInterval(-30 * 24 * 60 * 60)
                    .timeIntervalSince1970
            case .quickCollection:
                condition = """
                    id IN (
                        SELECT photo_id
                        FROM catalog_quick_collection
                    )
                    """
            case .edited:
                condition = "missing = 0 AND edited = 1"
            case .fiveStars:
                condition = "missing = 0 AND rating >= 5"
            case .picked:
                condition = "missing = 0 AND pick_status = 1"
            case .rejected:
                condition = "missing = 0 AND pick_status = -1"
            case .withKeywords:
                condition = "missing = 0 AND keyword_count > 0"
            case .withLocation:
                condition = """
                    missing = 0
                    AND latitude IS NOT NULL
                    AND longitude IS NOT NULL
                    """
            case .withoutLocation:
                condition = """
                    missing = 0
                    AND (latitude IS NULL OR longitude IS NULL)
                    """
            case .assistedCulling:
                condition = "missing = 0"
            case .exactDuplicates:
                condition = """
                    missing = 0
                    AND \(duplicateKey) IN (
                        SELECT duplicate_key
                        FROM (
                            SELECT
                                \(duplicateKey) AS duplicate_key
                            FROM catalog_photos
                            WHERE missing = 0
                        )
                        WHERE duplicate_key IS NOT NULL
                        GROUP BY duplicate_key
                        HAVING COUNT(*) > 1
                    )
                    """
            case .missingFiles:
                condition = "missing = 1"
            }
            let ordering: String
            if collection == .exactDuplicates {
                ordering = """
                    \(duplicateKey) ASC,
                    indexed_at ASC,
                    path COLLATE NOCASE ASC
                    """
            } else if collection == .quickCollection {
                ordering = """
                    (
                        SELECT position
                        FROM catalog_quick_collection
                        WHERE photo_id = catalog_photos.id
                    ) ASC,
                    path COLLATE NOCASE ASC
                    """
            } else {
                ordering = """
                    COALESCE(
                        capture_date,
                        creation_date,
                        modification_date,
                        0
                    ) DESC,
                    filename COLLATE NOCASE ASC
                    """
            }
            let statement = try prepare(
                """
                SELECT
                    id, path, root_path, filename, file_extension,
                    file_size, creation_date, modification_date, format,
                    metadata_json, state_json, indexed_at, last_seen, missing
                FROM catalog_photos
                WHERE \(condition)
                ORDER BY \(ordering)
                """
            )
            defer { sqlite3_finalize(statement) }
            if let recentThreshold {
                bind(recentThreshold, at: 1, in: statement)
            }

            var result: [CatalogEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let entry = decodeCatalogEntry(from: statement) {
                    result.append(entry)
                }
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    public func entries(
        forPhotoCollection collectionID: UUID
    ) throws -> [CatalogEntry] {
        try queue.sync {
            guard try photoCollectionExists(collectionID) else {
                throw CatalogStoreError.collectionNotFound
            }
            let statement = try prepare(
                """
                SELECT
                    photos.id, photos.path, photos.root_path,
                    photos.filename, photos.file_extension,
                    photos.file_size, photos.creation_date,
                    photos.modification_date, photos.format,
                    photos.metadata_json, photos.state_json,
                    photos.indexed_at, photos.last_seen,
                    photos.missing
                FROM catalog_collection_members AS members
                JOIN catalog_photos AS photos
                    ON photos.id = members.photo_id
                WHERE members.collection_id = ?
                ORDER BY members.position ASC,
                    photos.path COLLATE NOCASE ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(collectionID.uuidString, at: 1, in: statement)
            var result: [CatalogEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let entry = decodeCatalogEntry(from: statement) {
                    result.append(entry)
                }
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    public func userStates(
        rootPath: String? = nil
    ) throws -> [String: PhotoUserState] {
        try queue.sync {
            let sql: String
            if rootPath == nil {
                sql = "SELECT id, state_json FROM catalog_photos"
            } else {
                sql = """
                    SELECT id, state_json
                    FROM catalog_photos
                    WHERE root_path = ?
                    """
            }
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            if let rootPath {
                bind(rootPath, at: 1, in: statement)
            }
            var result: [String: PhotoUserState] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = text(at: 0, in: statement),
                      let encoded = data(at: 1, in: statement),
                      let state = try? JSONDecoder().decode(
                          PhotoUserState.self,
                          from: encoded
                      ) else {
                    continue
                }
                result[id] = state
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    public func duplicateCandidates(
        fileSize: Int64
    ) throws -> [CatalogHashCandidate] {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT
                    id, path, file_size, modification_date, content_hash,
                    image_content_hash
                FROM catalog_photos
                WHERE missing = 0 AND file_size = ?
                ORDER BY path COLLATE NOCASE ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(fileSize, at: 1, in: statement)
            var result: [CatalogHashCandidate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = text(at: 0, in: statement),
                      let path = text(at: 1, in: statement) else {
                    continue
                }
                result.append(CatalogHashCandidate(
                    id: id,
                    path: path,
                    fileSize: sqlite3_column_int64(statement, 2),
                    modificationDate: date(at: 3, in: statement),
                    contentHash: text(at: 4, in: statement),
                    imageContentHash: text(at: 5, in: statement)
                ))
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    /// Returns every available photo for an image-data duplicate scan.
    ///
    /// Metadata-only copies can have different file sizes, so byte-size
    /// bucketing is only used later for the whole-file fallback.
    public func duplicateScanCandidates() throws -> [CatalogHashCandidate] {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT
                    id,
                    path,
                    file_size,
                    modification_date,
                    content_hash,
                    image_content_hash
                FROM catalog_photos
                WHERE missing = 0 AND file_size > 0
                ORDER BY
                    file_size ASC,
                    path COLLATE NOCASE ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            var result: [CatalogHashCandidate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = text(at: 0, in: statement),
                      let path = text(at: 1, in: statement) else {
                    continue
                }
                result.append(CatalogHashCandidate(
                    id: id,
                    path: path,
                    fileSize: sqlite3_column_int64(statement, 2),
                    modificationDate: date(at: 3, in: statement),
                    contentHash: text(at: 4, in: statement),
                    imageContentHash: text(at: 5, in: statement)
                ))
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    @discardableResult
    public func recordContentHash(
        _ contentHash: String,
        id: String,
        expectedFileSize: Int64,
        expectedModificationDate: Date?
    ) throws -> Bool {
        try queue.sync {
            let normalized = try validatedSHA256(
                contentHash,
                fieldName: "content"
            )
            let statement = try prepare(
                """
                UPDATE catalog_photos
                SET content_hash = ?
                WHERE id = ?
                    AND file_size = ?
                    AND modification_date IS ?
                    AND missing = 0
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(normalized, at: 1, in: statement)
            bind(id, at: 2, in: statement)
            bind(expectedFileSize, at: 3, in: statement)
            bind(expectedModificationDate, at: 4, in: statement)
            try stepDone(statement)
            return sqlite3_changes(try requireDatabase()) > 0
        }
    }

    private func validatedSHA256(
        _ value: String,
        fieldName: String
    ) throws -> String {
        let normalized = value.lowercased()
        guard normalized.count == 64,
              normalized.allSatisfy({
                  $0.isNumber || ("a"..."f").contains(String($0))
              }) else {
            throw CatalogStoreError.queryFailed(
                "The supplied \(fieldName) hash is invalid."
            )
        }
        return normalized
    }

    public func contentHash(id: String) throws -> String? {
        try queue.sync {
            let statement = try prepare(
                "SELECT content_hash FROM catalog_photos WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            bind(id, at: 1, in: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                return text(at: 0, in: statement)
            }
            guard result == SQLITE_DONE else {
                try ensureNoStepError(statement)
                return nil
            }
            return nil
        }
    }

    @discardableResult
    public func recordImageContentHash(
        _ imageContentHash: String,
        id: String,
        expectedFileSize: Int64,
        expectedModificationDate: Date?
    ) throws -> Bool {
        try queue.sync {
            let normalized = try validatedSHA256(
                imageContentHash,
                fieldName: "image-content"
            )
            let statement = try prepare(
                """
                UPDATE catalog_photos
                SET image_content_hash = ?
                WHERE id = ?
                    AND file_size = ?
                    AND modification_date IS ?
                    AND missing = 0
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(normalized, at: 1, in: statement)
            bind(id, at: 2, in: statement)
            bind(expectedFileSize, at: 3, in: statement)
            bind(expectedModificationDate, at: 4, in: statement)
            try stepDone(statement)
            return sqlite3_changes(try requireDatabase()) > 0
        }
    }

    public func imageContentHash(id: String) throws -> String? {
        try queue.sync {
            let statement = try prepare(
                "SELECT image_content_hash FROM catalog_photos WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            bind(id, at: 1, in: statement)
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                return text(at: 0, in: statement)
            }
            guard result == SQLITE_DONE else {
                try ensureNoStepError(statement)
                return nil
            }
            return nil
        }
    }

    public func clearContentHash(id: String) throws {
        try queue.sync {
            let statement = try prepare(
                "UPDATE catalog_photos SET content_hash = NULL WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            bind(id, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func clearImageContentHash(id: String) throws {
        try queue.sync {
            let statement = try prepare(
                """
                UPDATE catalog_photos
                SET image_content_hash = NULL
                WHERE id = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(id, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func clearDuplicateSignatures(id: String) throws {
        try queue.sync {
            let statement = try prepare(
                """
                UPDATE catalog_photos
                SET content_hash = NULL, image_content_hash = NULL
                WHERE id = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(id, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func exactDuplicateGroups()
        throws -> [CatalogExactDuplicateGroup]
    {
        try queue.sync {
            let duplicateKey = Self.duplicateKeySQL()
            let statement = try prepare(
                """
                WITH keyed AS (
                    SELECT
                        \(duplicateKey) AS duplicate_key,
                        COALESCE(
                            image_content_hash,
                            content_hash
                        ) AS match_hash,
                        CASE
                            WHEN image_content_hash IS NOT NULL
                                THEN 'imageData'
                            ELSE 'wholeFile'
                        END AS match_basis,
                        id,
                        path,
                        filename,
                        file_size,
                        indexed_at
                    FROM catalog_photos
                    WHERE missing = 0
                ),
                duplicate_keys AS (
                    SELECT duplicate_key
                    FROM keyed
                    WHERE duplicate_key IS NOT NULL
                    GROUP BY duplicate_key
                    HAVING COUNT(*) > 1
                )
                SELECT
                    keyed.duplicate_key,
                    keyed.match_hash,
                    keyed.match_basis,
                    keyed.id,
                    keyed.path,
                    keyed.filename,
                    keyed.file_size,
                    keyed.indexed_at
                FROM keyed
                INNER JOIN duplicate_keys
                    ON duplicate_keys.duplicate_key =
                        keyed.duplicate_key
                ORDER BY
                    keyed.duplicate_key ASC,
                    keyed.indexed_at ASC,
                    keyed.path COLLATE NOCASE ASC
                """
            )
            defer { sqlite3_finalize(statement) }

            var groups: [CatalogExactDuplicateGroup] = []
            var currentKey: String?
            var currentHash: String?
            var currentBasis:
                CatalogDuplicateMatchBasis?
            var members: [CatalogExactDuplicateMember] = []

            func finishCurrentGroup() {
                guard let currentHash,
                      let currentBasis,
                      members.count > 1 else {
                    members.removeAll(keepingCapacity: true)
                    return
                }
                groups.append(CatalogExactDuplicateGroup(
                    contentHash: currentHash,
                    matchBasis: currentBasis,
                    members: members
                ))
                members.removeAll(keepingCapacity: true)
            }

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let duplicateKey = text(at: 0, in: statement),
                      let contentHash = text(at: 1, in: statement),
                      let basisRaw = text(at: 2, in: statement),
                      let basis =
                        CatalogDuplicateMatchBasis(
                            rawValue: basisRaw
                        ),
                      let id = text(at: 3, in: statement),
                      let path = text(at: 4, in: statement),
                      let filename = text(at: 5, in: statement) else {
                    continue
                }
                if currentKey != nil, currentKey != duplicateKey {
                    finishCurrentGroup()
                }
                currentKey = duplicateKey
                currentHash = contentHash
                currentBasis = basis
                members.append(CatalogExactDuplicateMember(
                    id: id,
                    path: path,
                    filename: filename,
                    fileSize: sqlite3_column_int64(statement, 6),
                    indexedAt: date(at: 7, in: statement) ?? .distantPast
                ))
            }
            try ensureNoStepError(statement)
            finishCurrentGroup()
            return groups
        }
    }

    public func cullingAnalysisCandidates(
        engineVersion: Int
    ) throws -> [CatalogCullingCandidate] {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT
                    photos.id,
                    photos.path,
                    photos.root_path,
                    photos.filename,
                    photos.file_extension,
                    photos.file_size,
                    photos.creation_date,
                    photos.modification_date,
                    photos.format,
                    photos.metadata_json,
                    photos.state_json,
                    photos.indexed_at,
                    photos.last_seen,
                    photos.missing,
                    CASE
                        WHEN analysis.file_size = photos.file_size
                            AND analysis.modification_date
                                IS photos.modification_date
                            AND analysis.engine_version = ?
                        THEN analysis.analysis_json
                        ELSE NULL
                    END,
                    analysis.manual_decision
                FROM catalog_photos AS photos
                LEFT JOIN catalog_culling_analysis AS analysis
                    ON analysis.photo_id = photos.id
                WHERE photos.missing = 0
                ORDER BY
                    COALESCE(
                        photos.capture_date,
                        photos.creation_date,
                        photos.modification_date,
                        0
                    ) ASC,
                    photos.path COLLATE NOCASE ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(engineVersion, at: 1, in: statement)

            var result: [CatalogCullingCandidate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let entry = decodeCatalogEntry(from: statement) else {
                    continue
                }
                var cached: AssistedCullingAnalysis?
                if let encoded = data(at: 14, in: statement),
                   var decoded = try? JSONDecoder().decode(
                       AssistedCullingAnalysis.self,
                       from: encoded
                   ), decoded.engineVersion == engineVersion {
                    decoded.manualDecision = nil
                    cached = decoded
                }
                let manualDecision = text(at: 15, in: statement)
                    .flatMap(AssistedCullingDecision.init(rawValue:))
                    .flatMap { $0 == .review ? nil : $0 }
                result.append(CatalogCullingCandidate(
                    entry: entry,
                    cachedAnalysis: cached,
                    manualDecision: manualDecision
                ))
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    @discardableResult
    public func recordCullingAnalysis(
        _ analysis: AssistedCullingAnalysis,
        id: String,
        expectedFileSize: Int64,
        expectedModificationDate: Date?
    ) throws -> Bool {
        try queue.sync {
            let statement = try prepare(
                """
                INSERT INTO catalog_culling_analysis(
                    photo_id,
                    file_size,
                    modification_date,
                    engine_version,
                    analysis_json,
                    analyzed_at
                )
                SELECT
                    photos.id,
                    photos.file_size,
                    photos.modification_date,
                    ?,
                    ?,
                    ?
                FROM catalog_photos AS photos
                WHERE photos.id = ?
                    AND photos.file_size = ?
                    AND photos.modification_date IS ?
                    AND photos.missing = 0
                ON CONFLICT(photo_id) DO UPDATE SET
                    file_size = excluded.file_size,
                    modification_date = excluded.modification_date,
                    engine_version = excluded.engine_version,
                    analysis_json = excluded.analysis_json,
                    analyzed_at = excluded.analyzed_at
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(analysis.engineVersion, at: 1, in: statement)
            bind(try encode(analysis), at: 2, in: statement)
            bind(
                analysis.analyzedAt.timeIntervalSince1970,
                at: 3,
                in: statement
            )
            bind(id, at: 4, in: statement)
            bind(expectedFileSize, at: 5, in: statement)
            bind(expectedModificationDate, at: 6, in: statement)
            try stepDone(statement)
            return sqlite3_changes(try requireDatabase()) > 0
        }
    }

    public func clearCullingComputedAnalysis(id: String) throws {
        try queue.sync {
            let statement = try prepare(
                """
                UPDATE catalog_culling_analysis SET
                    file_size = NULL,
                    modification_date = NULL,
                    engine_version = NULL,
                    analysis_json = NULL,
                    analyzed_at = NULL
                WHERE photo_id = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(id, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func setCullingManualDecision(
        _ decision: AssistedCullingDecision?,
        id: String
    ) throws {
        try queue.sync {
            guard decision != .review else {
                throw CatalogStoreError.queryFailed(
                    "Review is the calculated neutral state, not a manual override."
                )
            }
            let statement = try prepare(
                """
                INSERT INTO catalog_culling_analysis(
                    photo_id,
                    manual_decision
                ) VALUES(?, ?)
                ON CONFLICT(photo_id) DO UPDATE SET
                    manual_decision = excluded.manual_decision
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(id, at: 1, in: statement)
            if let decision {
                bind(decision.rawValue, at: 2, in: statement)
            } else {
                bindNull(at: 2, in: statement)
            }
            try stepDone(statement)
        }
    }

    public func peopleAnalysisCandidates(
        engineVersion: Int,
        photoIDs: Set<String>? = nil
    ) throws -> [CatalogPeopleAnalysisCandidate] {
        try queue.sync {
            if let photoIDs, photoIDs.isEmpty {
                return []
            }
            let facesByPhoto = Dictionary(
                grouping: try loadCatalogFaces(
                    photoIDs: photoIDs,
                    includeIgnored: true
                ),
                by: \.photoID
            )
            let photoFilter = photoIDs == nil
                ? ""
                : """
                  AND photos.id IN (
                      SELECT value FROM json_each(?)
                  )
                  """
            let statement = try prepare(
                """
                SELECT
                    photos.id,
                    photos.path,
                    photos.root_path,
                    photos.filename,
                    photos.file_extension,
                    photos.file_size,
                    photos.creation_date,
                    photos.modification_date,
                    photos.format,
                    photos.metadata_json,
                    photos.state_json,
                    photos.indexed_at,
                    photos.last_seen,
                    photos.missing,
                    CASE
                        WHEN analysis.file_size = photos.file_size
                            AND analysis.modification_date
                                IS photos.modification_date
                            AND analysis.engine_version = ?
                        THEN 1
                        ELSE 0
                    END
                FROM catalog_photos AS photos
                LEFT JOIN catalog_face_analysis AS analysis
                    ON analysis.photo_id = photos.id
                WHERE photos.missing = 0
                    \(photoFilter)
                ORDER BY
                    COALESCE(
                        photos.capture_date,
                        photos.creation_date,
                        photos.modification_date,
                        0
                    ) ASC,
                    photos.path COLLATE NOCASE ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(engineVersion, at: 1, in: statement)
            if let photoIDs {
                let encodedIDs = try encode(
                    photoIDs.sorted()
                )
                guard let json = String(
                    data: encodedIDs,
                    encoding: .utf8
                ) else {
                    throw CatalogStoreError.encodingFailed
                }
                bind(json, at: 2, in: statement)
            }

            var result: [CatalogPeopleAnalysisCandidate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let entry = decodeCatalogEntry(from: statement) else {
                    continue
                }
                let isCached =
                    sqlite3_column_int64(statement, 14) == 1
                result.append(CatalogPeopleAnalysisCandidate(
                    entry: entry,
                    cachedFaces:
                        isCached ? (facesByPhoto[entry.id] ?? []) : nil
                ))
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    @discardableResult
    public func recordPeopleFaceAnalysis(
        _ detections: [PeopleFaceDetection],
        id: String,
        engineVersion: Int,
        expectedFileSize: Int64,
        expectedModificationDate: Date?,
        analyzedAt: Date = Date()
    ) throws -> Bool {
        try queue.sync {
            var recorded = false
            try transaction {
                let guardStatement = try prepare(
                    """
                    SELECT COUNT(*)
                    FROM catalog_photos
                    WHERE id = ?
                        AND file_size = ?
                        AND modification_date IS ?
                        AND missing = 0
                    """
                )
                bind(id, at: 1, in: guardStatement)
                bind(expectedFileSize, at: 2, in: guardStatement)
                bind(
                    expectedModificationDate,
                    at: 3,
                    in: guardStatement
                )
                let matches =
                    sqlite3_step(guardStatement) == SQLITE_ROW
                    && sqlite3_column_int64(guardStatement, 0) == 1
                sqlite3_finalize(guardStatement)
                guard matches else { return }

                let existing = try loadCatalogFaces(
                    photoID: id,
                    includeIgnored: true
                )
                let replacements = Self.reconciledFaces(
                    detections: detections,
                    photoID: id,
                    existing: existing,
                    analyzedAt: analyzedAt
                )

                let deleteFaces = try prepare(
                    "DELETE FROM catalog_faces WHERE photo_id = ?"
                )
                bind(id, at: 1, in: deleteFaces)
                try stepDone(deleteFaces)
                sqlite3_finalize(deleteFaces)

                if !replacements.isEmpty {
                    let insert = try prepare(
                        """
                        INSERT INTO catalog_faces(
                            id, photo_id,
                            bounds_x, bounds_y,
                            bounds_width, bounds_height,
                            confidence, capture_quality,
                            feature_print, person_id,
                            disposition, analyzed_at
                        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """
                    )
                    defer { sqlite3_finalize(insert) }
                    for face in replacements {
                        sqlite3_reset(insert)
                        sqlite3_clear_bindings(insert)
                        bind(face.id, at: 1, in: insert)
                        bind(face.photoID, at: 2, in: insert)
                        bind(Double(face.boundingBox.minX), at: 3, in: insert)
                        bind(Double(face.boundingBox.minY), at: 4, in: insert)
                        bind(Double(face.boundingBox.width), at: 5, in: insert)
                        bind(Double(face.boundingBox.height), at: 6, in: insert)
                        bind(face.confidence, at: 7, in: insert)
                        bind(face.captureQuality, at: 8, in: insert)
                        bind(face.featurePrintData, at: 9, in: insert)
                        bind(
                            face.personID?.uuidString,
                            at: 10,
                            in: insert
                        )
                        bind(face.disposition.rawValue, at: 11, in: insert)
                        bind(
                            face.analyzedAt.timeIntervalSince1970,
                            at: 12,
                            in: insert
                        )
                        try stepDone(insert)
                    }
                }

                let analysis = try prepare(
                    """
                    INSERT INTO catalog_face_analysis(
                        photo_id, file_size, modification_date,
                        engine_version, analyzed_at, face_count
                    ) VALUES(?, ?, ?, ?, ?, ?)
                    ON CONFLICT(photo_id) DO UPDATE SET
                        file_size = excluded.file_size,
                        modification_date = excluded.modification_date,
                        engine_version = excluded.engine_version,
                        analyzed_at = excluded.analyzed_at,
                        face_count = excluded.face_count
                    """
                )
                bind(id, at: 1, in: analysis)
                bind(expectedFileSize, at: 2, in: analysis)
                bind(expectedModificationDate, at: 3, in: analysis)
                bind(engineVersion, at: 4, in: analysis)
                bind(analyzedAt.timeIntervalSince1970, at: 5, in: analysis)
                bind(replacements.count, at: 6, in: analysis)
                try stepDone(analysis)
                sqlite3_finalize(analysis)
                recorded = true
            }
            return recorded
        }
    }

    public func clearPeopleFaceAnalysis(id: String) throws {
        try queue.sync {
            try transaction {
                let deleteFaces = try prepare(
                    "DELETE FROM catalog_faces WHERE photo_id = ?"
                )
                bind(id, at: 1, in: deleteFaces)
                try stepDone(deleteFaces)
                sqlite3_finalize(deleteFaces)

                let deleteAnalysis = try prepare(
                    "DELETE FROM catalog_face_analysis WHERE photo_id = ?"
                )
                bind(id, at: 1, in: deleteAnalysis)
                try stepDone(deleteAnalysis)
                sqlite3_finalize(deleteAnalysis)
            }
        }
    }

    public func catalogFaces(
        includeIgnored: Bool = true
    ) throws -> [CatalogFace] {
        try queue.sync {
            try loadCatalogFaces(includeIgnored: includeIgnored)
        }
    }

    public func catalogFaces(
        photoID: String,
        includeIgnored: Bool = true
    ) throws -> [CatalogFace] {
        try queue.sync {
            try loadCatalogFaces(
                photoID: photoID,
                includeIgnored: includeIgnored
            )
        }
    }

    public func catalogPeople() throws -> [CatalogPerson] {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT id, name, created_at, updated_at
                FROM catalog_people
                ORDER BY name COLLATE NOCASE ASC, created_at ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            var result: [CatalogPerson] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let rawID = text(at: 0, in: statement),
                      let id = UUID(uuidString: rawID),
                      let name = text(at: 1, in: statement) else {
                    continue
                }
                result.append(CatalogPerson(
                    id: id,
                    name: name,
                    createdAt: date(at: 2, in: statement)
                        ?? .distantPast,
                    updatedAt: date(at: 3, in: statement)
                        ?? .distantPast
                ))
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    @discardableResult
    public func createPerson(
        name rawName: String,
        faceIDs: [String]
    ) throws -> CatalogPerson {
        let name = Self.normalizedPersonName(rawName)
        guard !name.isEmpty else {
            throw CatalogStoreError.invalidPersonName
        }
        let uniqueFaceIDs = Array(Set(faceIDs)).sorted()
        guard !uniqueFaceIDs.isEmpty else {
            throw CatalogStoreError.peopleSelectionEmpty
        }
        return try queue.sync {
            let person = CatalogPerson(name: name)
            try transaction {
                try ensureFacesExist(uniqueFaceIDs)
                let statement = try prepare(
                    """
                    INSERT INTO catalog_people(
                        id, name, created_at, updated_at
                    ) VALUES(?, ?, ?, ?)
                    """
                )
                bind(person.id.uuidString, at: 1, in: statement)
                bind(person.name, at: 2, in: statement)
                bind(person.createdAt.timeIntervalSince1970, at: 3, in: statement)
                bind(person.updatedAt.timeIntervalSince1970, at: 4, in: statement)
                try stepDone(statement)
                sqlite3_finalize(statement)
                try assignFacesUnchecked(
                    uniqueFaceIDs,
                    to: person.id
                )
            }
            return person
        }
    }

    public func renamePerson(
        id: UUID,
        name rawName: String
    ) throws {
        let name = Self.normalizedPersonName(rawName)
        guard !name.isEmpty else {
            throw CatalogStoreError.invalidPersonName
        }
        try queue.sync {
            let statement = try prepare(
                """
                UPDATE catalog_people
                SET name = ?, updated_at = ?
                WHERE id = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(name, at: 1, in: statement)
            bind(Date().timeIntervalSince1970, at: 2, in: statement)
            bind(id.uuidString, at: 3, in: statement)
            try stepDone(statement)
            guard sqlite3_changes(try requireDatabase()) > 0 else {
                throw CatalogStoreError.personNotFound
            }
        }
    }

    public func assignFaces(
        _ faceIDs: [String],
        to personID: UUID
    ) throws {
        let uniqueFaceIDs = Array(Set(faceIDs)).sorted()
        guard !uniqueFaceIDs.isEmpty else {
            throw CatalogStoreError.peopleSelectionEmpty
        }
        try queue.sync {
            try transaction {
                try ensurePersonExists(personID)
                try ensureFacesExist(uniqueFaceIDs)
                try assignFacesUnchecked(
                    uniqueFaceIDs,
                    to: personID
                )
            }
        }
    }

    public func unassignFaces(_ faceIDs: [String]) throws {
        try updateFaces(
            faceIDs,
            personID: nil,
            disposition: .candidate
        )
    }

    public func ignoreFaces(_ faceIDs: [String]) throws {
        try updateFaces(
            faceIDs,
            personID: nil,
            disposition: .ignored
        )
    }

    public func restoreIgnoredFaces(_ faceIDs: [String]) throws {
        try updateFaces(
            faceIDs,
            personID: nil,
            disposition: .candidate
        )
    }

    public func mergePeople(
        sourceID: UUID,
        destinationID: UUID
    ) throws {
        guard sourceID != destinationID else {
            throw CatalogStoreError.personMergeUnchanged
        }
        try queue.sync {
            try transaction {
                try ensurePersonExists(sourceID)
                try ensurePersonExists(destinationID)
                let update = try prepare(
                    """
                    UPDATE catalog_faces
                    SET person_id = ?, disposition = 'candidate'
                    WHERE person_id = ?
                    """
                )
                bind(destinationID.uuidString, at: 1, in: update)
                bind(sourceID.uuidString, at: 2, in: update)
                try stepDone(update)
                sqlite3_finalize(update)

                let touch = try prepare(
                    """
                    UPDATE catalog_people
                    SET updated_at = ?
                    WHERE id = ?
                    """
                )
                bind(Date().timeIntervalSince1970, at: 1, in: touch)
                bind(destinationID.uuidString, at: 2, in: touch)
                try stepDone(touch)
                sqlite3_finalize(touch)

                let delete = try prepare(
                    "DELETE FROM catalog_people WHERE id = ?"
                )
                bind(sourceID.uuidString, at: 1, in: delete)
                try stepDone(delete)
                sqlite3_finalize(delete)
            }
        }
    }

    public func deletePerson(id: UUID) throws {
        try queue.sync {
            let statement = try prepare(
                "DELETE FROM catalog_people WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)
            guard sqlite3_changes(try requireDatabase()) > 0 else {
                throw CatalogStoreError.personNotFound
            }
        }
    }

    public func photoStacks() throws -> [CatalogPhotoStack] {
        try queue.sync {
            try loadPhotoStacks()
        }
    }

    public func photoStack(
        containing photoID: PhotoAsset.ID
    ) throws -> CatalogPhotoStack? {
        try queue.sync {
            guard let stackID = try photoStackID(
                containing: photoID
            ) else {
                return nil
            }
            return try loadPhotoStack(id: stackID)
        }
    }

    @discardableResult
    public func createPhotoStack(
        photoIDs: [PhotoAsset.ID],
        collapsed: Bool = true
    ) throws -> CatalogPhotoStack {
        let normalized = uniquePhotoIDs(photoIDs)
        guard normalized.count >= 2 else {
            throw CatalogStoreError.photoStackRequiresMultiplePhotos
        }
        return try queue.sync {
            var result: CatalogPhotoStack?
            try transaction {
                result = try createOrMergePhotoStack(
                    photoIDs: normalized,
                    collapsed: collapsed,
                    allowsExistingStack: true
                )
            }
            guard let result else {
                throw CatalogStoreError.queryFailed(
                    "The photo stack could not be reloaded."
                )
            }
            return result
        }
    }

    /// Commits AI suggestions only after an explicit user action.
    ///
    /// Every suggestion is validated before the transaction commits. Existing
    /// stack membership or a folder boundary rolls the whole operation back,
    /// so accepting suggestions can never create a partial result.
    @discardableResult
    public func createSuggestedPhotoStacks(
        _ suggestedPhotoIDs: [[PhotoAsset.ID]],
        collapsed: Bool = true
    ) throws -> [CatalogPhotoStack] {
        let groups = suggestedPhotoIDs.map(uniquePhotoIDs)
        guard groups.allSatisfy({ $0.count >= 2 }) else {
            throw CatalogStoreError.photoStackRequiresMultiplePhotos
        }
        var seen: Set<PhotoAsset.ID> = []
        guard groups.flatMap({ $0 }).allSatisfy({
            seen.insert($0).inserted
        }) else {
            throw CatalogStoreError.photoStackAlreadyContainsSelection
        }
        guard !groups.isEmpty else { return [] }

        return try queue.sync {
            var results: [CatalogPhotoStack] = []
            try transaction {
                for group in groups {
                    results.append(
                        try createOrMergePhotoStack(
                            photoIDs: group,
                            collapsed: collapsed,
                            allowsExistingStack: false
                        )
                    )
                }
            }
            return results
        }
    }

    public func setPhotoStackCollapsed(
        id: UUID,
        collapsed: Bool
    ) throws {
        try queue.sync {
            guard try loadPhotoStack(id: id) != nil else {
                throw CatalogStoreError.photoStackNotFound
            }
            let statement = try prepare(
                """
                UPDATE catalog_photo_stacks
                SET collapsed = ?, updated_at = ?
                WHERE id = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(collapsed ? 1 : 0, at: 1, in: statement)
            bind(Date().timeIntervalSince1970, at: 2, in: statement)
            bind(id.uuidString, at: 3, in: statement)
            try stepDone(statement)
        }
    }

    public func setAllPhotoStacksCollapsed(
        _ collapsed: Bool
    ) throws {
        try queue.sync {
            let statement = try prepare(
                """
                UPDATE catalog_photo_stacks
                SET collapsed = ?, updated_at = ?
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(collapsed ? 1 : 0, at: 1, in: statement)
            bind(Date().timeIntervalSince1970, at: 2, in: statement)
            try stepDone(statement)
        }
    }

    public func unstackPhotoStack(id: UUID) throws {
        try queue.sync {
            let statement = try prepare(
                "DELETE FROM catalog_photo_stacks WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)
            guard sqlite3_changes(try requireDatabase()) > 0 else {
                throw CatalogStoreError.photoStackNotFound
            }
        }
    }

    public func removePhotosFromStacks(
        photoIDs: [PhotoAsset.ID]
    ) throws {
        let normalized = uniquePhotoIDs(photoIDs)
        guard !normalized.isEmpty else { return }
        try queue.sync {
            try transaction {
                let stackIDs = try photoStackIDs(
                    containingAny: normalized
                )
                let statement = try prepare(
                    """
                    DELETE FROM catalog_photo_stack_members
                    WHERE photo_id = ?
                    """
                )
                defer { sqlite3_finalize(statement) }
                for photoID in normalized {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(photoID, at: 1, in: statement)
                    try stepDone(statement)
                }
                for stackID in stackIDs {
                    try normalizeOrRemovePhotoStack(id: stackID)
                }
            }
        }
    }

    @discardableResult
    public func movePhotoInStack(
        photoID: PhotoAsset.ID,
        _ move: CatalogPhotoStackMove
    ) throws -> CatalogPhotoStack {
        try queue.sync {
            var result: CatalogPhotoStack?
            try transaction {
                guard let stackID = try photoStackID(
                    containing: photoID
                ),
                var stack = try loadPhotoStack(id: stackID),
                let sourceIndex = stack.memberIDs.firstIndex(
                    of: photoID
                ) else {
                    throw CatalogStoreError.photoStackNotFound
                }

                let targetIndex: Int
                switch move {
                case .top:
                    targetIndex = 0
                case .up:
                    targetIndex = sourceIndex - 1
                case .down:
                    targetIndex = sourceIndex + 1
                }
                guard targetIndex >= 0,
                      targetIndex < stack.memberIDs.count,
                      targetIndex != sourceIndex else {
                    throw CatalogStoreError.photoStackMoveUnavailable
                }

                let movedID = stack.memberIDs.remove(
                    at: sourceIndex
                )
                stack.memberIDs.insert(movedID, at: targetIndex)
                try replacePhotoStackMembers(
                    stackID: stack.id,
                    photoIDs: stack.memberIDs
                )
                try touchPhotoStack(id: stack.id)
                result = try loadPhotoStack(id: stack.id)
            }
            guard let result else {
                throw CatalogStoreError.photoStackNotFound
            }
            return result
        }
    }

    @discardableResult
    public func splitPhotoStack(
        photoIDs: [PhotoAsset.ID]
    ) throws -> [CatalogPhotoStack] {
        let normalized = uniquePhotoIDs(photoIDs)
        guard !normalized.isEmpty else {
            throw CatalogStoreError.photoStackSplitRequiresOneStack
        }
        return try queue.sync {
            var results: [CatalogPhotoStack] = []
            try transaction {
                let stackIDs = try photoStackIDs(
                    containingAny: normalized
                )
                guard stackIDs.count == 1,
                      let stack = try loadPhotoStack(
                          id: stackIDs[0]
                      ),
                      normalized.allSatisfy({
                          stack.memberIDs.contains($0)
                      }) else {
                    throw CatalogStoreError
                        .photoStackSplitRequiresOneStack
                }
                let selected = Set(normalized)
                guard selected.count < stack.memberIDs.count,
                      !(selected.count == 1
                        && selected.contains(
                            stack.topPhotoID ?? ""
                        )) else {
                    throw CatalogStoreError
                        .photoStackSplitUnavailable
                }

                let separated = stack.memberIDs.filter {
                    selected.contains($0)
                }
                let remaining = stack.memberIDs.filter {
                    !selected.contains($0)
                }

                if remaining.count >= 2 {
                    try replacePhotoStackMembers(
                        stackID: stack.id,
                        photoIDs: remaining
                    )
                    try touchPhotoStack(id: stack.id)
                } else {
                    let delete = try prepare(
                        "DELETE FROM catalog_photo_stacks WHERE id = ?"
                    )
                    bind(stack.id.uuidString, at: 1, in: delete)
                    try stepDone(delete)
                    sqlite3_finalize(delete)
                }

                if separated.count >= 2 {
                    _ = try createOrMergePhotoStack(
                        photoIDs: separated,
                        collapsed: false,
                        allowsExistingStack: false
                    )
                }
                results = try loadPhotoStacks()
            }
            return results
        }
    }

    public func refreshMissingStatus(
        photoIDs: Set<String>? = nil
    ) throws {
        try queue.sync {
            if let photoIDs, photoIDs.isEmpty {
                return
            }
            let photoFilter = photoIDs == nil
                ? ""
                : """
                  WHERE id IN (
                      SELECT value FROM json_each(?)
                  )
                  """
            let statement = try prepare(
                """
                SELECT id, path, missing
                FROM catalog_photos
                \(photoFilter)
                """
            )
            defer { sqlite3_finalize(statement) }
            if let photoIDs {
                let encodedIDs = try encode(
                    photoIDs.sorted()
                )
                guard let json = String(
                    data: encodedIDs,
                    encoding: .utf8
                ) else {
                    throw CatalogStoreError.encodingFailed
                }
                bind(json, at: 1, in: statement)
            }
            var changes: [(String, Bool)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let id = text(at: 0, in: statement),
                      let path = text(at: 1, in: statement) else {
                    continue
                }
                let recordedMissing = sqlite3_column_int(statement, 2) != 0
                let missing = !FileManager.default.fileExists(atPath: path)
                if missing != recordedMissing {
                    changes.append((id, missing))
                }
            }
            try ensureNoStepError(statement)
            guard !changes.isEmpty else { return }
            try transaction {
                let update = try prepare(
                    "UPDATE catalog_photos SET missing = ? WHERE id = ?"
                )
                defer { sqlite3_finalize(update) }
                for (id, missing) in changes {
                    sqlite3_reset(update)
                    sqlite3_clear_bindings(update)
                    bind(missing ? 1 : 0, at: 1, in: update)
                    bind(id, at: 2, in: update)
                    try stepDone(update)
                }
            }
        }
    }

    public func relinkPhoto(
        id: String,
        to replacementURL: URL
    ) throws -> CatalogRelinkResult {
        try queue.sync {
            guard let existing = try catalogEntry(id: id) else {
                throw CatalogStoreError.photoNotFound
            }

            let url = replacementURL.standardizedFileURL
            guard FileTypeDetector.isSupported(url: url) else {
                throw CatalogStoreError.unsupportedReplacement
            }
            let resourceKeys: Set<URLResourceKey> = [
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isRegularFileKey,
                .fileResourceIdentifierKey,
            ]
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                throw CatalogStoreError.replacementUnavailable
            }
            guard values.isRegularFile == true else {
                throw CatalogStoreError.replacementUnavailable
            }

            let format = FileTypeDetector.format(
                forExtension: url.pathExtension
            )
            guard format == existing.format else {
                throw CatalogStoreError.replacementFormatMismatch(
                    expected: existing.format.displayName,
                    actual: format.displayName
                )
            }

            let size = Int64(values.fileSize ?? 0)
            let modification = values.contentModificationDate
            let replacementID = PhotoLibraryScanner.stableID(
                path: url.path,
                size: size,
                modification: modification,
                resourceIdentifier: values.fileResourceIdentifier
            )
            if let conflict = try catalogEntry(path: url.path),
               conflict.id != id {
                throw CatalogStoreError.replacementAlreadyCataloged
            }
            if replacementID != id,
               let conflict = try catalogEntry(id: replacementID),
               conflict.path != existing.path {
                throw CatalogStoreError.replacementAlreadyCataloged
            }

            let rootPath: String
            let oldRoot = URL(
                fileURLWithPath: existing.rootPath,
                isDirectory: true
            ).standardizedFileURL.path
            if url.path == oldRoot
                || url.path.hasPrefix(oldRoot + "/") {
                rootPath = existing.rootPath
            } else {
                rootPath = url.deletingLastPathComponent().path
            }

            let replacementAsset = PhotoAsset(
                id: replacementID,
                url: url,
                path: url.path,
                filename: url.lastPathComponent,
                fileExtension: url.pathExtension,
                fileSize: size,
                creationDate: values.creationDate,
                modificationDate: modification,
                format: format,
                metadata: existing.metadata,
                userState: existing.userState,
                xmpSidecarURL:
                    XMPSidecarService.existingSidecarURL(for: url)
            )

            try transaction {
                let root = try prepare(
                    """
                    INSERT INTO catalog_roots(path, last_scanned, recursive)
                    VALUES(?, ?, 0)
                    ON CONFLICT(path) DO UPDATE SET
                        last_scanned = excluded.last_scanned
                    """
                )
                bind(rootPath, at: 1, in: root)
                bind(Date().timeIntervalSince1970, at: 2, in: root)
                try stepDone(root)
                sqlite3_finalize(root)

                try upsert(
                    asset: replacementAsset,
                    rootPath: rootPath,
                    indexedAt: existing.indexedAt
                )
                if replacementID != id {
                    let previousStackID = try photoStackID(
                        containing: id
                    )
                    let previousFolder = URL(
                        fileURLWithPath: existing.path
                    )
                    .deletingLastPathComponent()
                    .standardizedFileURL
                    .path
                    let replacementFolder = url
                        .deletingLastPathComponent()
                        .standardizedFileURL
                        .path
                    if previousFolder == replacementFolder {
                        try replaceStackMemberPhotoID(
                            previousID: id,
                            replacementID: replacementID
                        )
                    }
                    let quickCollection = try prepare(
                        """
                        UPDATE catalog_quick_collection
                        SET photo_id = ?
                        WHERE photo_id = ?
                        """
                    )
                    bind(replacementID, at: 1, in: quickCollection)
                    bind(id, at: 2, in: quickCollection)
                    try stepDone(quickCollection)
                    sqlite3_finalize(quickCollection)
                    let photoCollections = try prepare(
                        """
                        UPDATE catalog_collection_members
                        SET photo_id = ?
                        WHERE photo_id = ?
                        """
                    )
                    bind(
                        replacementID,
                        at: 1,
                        in: photoCollections
                    )
                    bind(id, at: 2, in: photoCollections)
                    try stepDone(photoCollections)
                    sqlite3_finalize(photoCollections)
                    let delete = try prepare(
                        "DELETE FROM catalog_photos WHERE id = ?"
                    )
                    bind(id, at: 1, in: delete)
                    try stepDone(delete)
                    sqlite3_finalize(delete)
                    if previousFolder != replacementFolder,
                       let previousStackID {
                        try normalizeOrRemovePhotoStack(
                            id: previousStackID
                        )
                    } else {
                        try removeOrphanedPhotoStacks()
                    }
                }
                try removeEmptyRoots()
            }
            guard let updated = try catalogEntry(id: replacementID) else {
                throw CatalogStoreError.queryFailed(
                    "The relinked photo could not be reloaded."
                )
            }
            return CatalogRelinkResult(
                previousID: id,
                entry: updated
            )
        }
    }

    public func removePhoto(id: String) throws {
        try queue.sync {
            try transaction {
                let stackID = try photoStackID(containing: id)
                let statement = try prepare(
                    "DELETE FROM catalog_photos WHERE id = ?"
                )
                bind(id, at: 1, in: statement)
                try stepDone(statement)
                sqlite3_finalize(statement)
                guard sqlite3_changes(try requireDatabase()) > 0 else {
                    throw CatalogStoreError.photoNotFound
                }
                if let stackID {
                    try normalizeOrRemovePhotoStack(id: stackID)
                } else {
                    try removeOrphanedPhotoStacks()
                }
                try removeEmptyRoots()
            }
        }
    }

    public func summary() throws -> CatalogSummary {
        try queue.sync {
            let duplicateKey = Self.duplicateKeySQL()
            var counts: [CatalogSmartCollection: Int] = [:]
            for collection in CatalogSmartCollection.allCases {
                counts[collection] = try count(for: collection)
            }

            let keywordStatement = try prepare(
                """
                SELECT keyword, COUNT(*)
                FROM catalog_photo_keywords AS keywords
                INNER JOIN catalog_photos AS photos
                    ON photos.id = keywords.photo_id
                GROUP BY keyword_folded
                ORDER BY COUNT(*) DESC, keyword COLLATE NOCASE ASC
                """
            )
            defer { sqlite3_finalize(keywordStatement) }
            var keywordCounts: [String: Int] = [:]
            while sqlite3_step(keywordStatement) == SQLITE_ROW {
                guard let keyword = text(at: 0, in: keywordStatement) else {
                    continue
                }
                keywordCounts[keyword] = Int(
                    sqlite3_column_int64(keywordStatement, 1)
                )
            }
            try ensureNoStepError(keywordStatement)

            let colorLabelStatement = try prepare(
                """
                SELECT color_label, COUNT(*)
                FROM catalog_photos
                WHERE missing = 0
                GROUP BY color_label
                """
            )
            defer { sqlite3_finalize(colorLabelStatement) }
            var colorLabelCounts: [PhotoColorLabel: Int] = [:]
            while sqlite3_step(colorLabelStatement) == SQLITE_ROW {
                guard let rawValue = text(
                    at: 0,
                    in: colorLabelStatement
                ),
                let label = PhotoColorLabel(rawValue: rawValue) else {
                    continue
                }
                colorLabelCounts[label] = Int(
                    sqlite3_column_int64(colorLabelStatement, 1)
                )
            }
            try ensureNoStepError(colorLabelStatement)

            return CatalogSummary(
                counts: counts,
                keywordCounts: keywordCounts,
                colorLabelCounts: colorLabelCounts,
                rootCount: try scalarInt(
                    "SELECT COUNT(*) FROM catalog_roots"
                ),
                databaseBytes: databaseByteCount(),
                exactDuplicateGroupCount: try scalarInt(
                    """
                    WITH keyed AS (
                        SELECT
                            \(duplicateKey) AS duplicate_key
                        FROM catalog_photos
                        WHERE missing = 0
                    )
                    SELECT COUNT(*)
                    FROM (
                        SELECT duplicate_key
                        FROM keyed
                        WHERE duplicate_key IS NOT NULL
                        GROUP BY duplicate_key
                        HAVING COUNT(*) > 1
                    )
                    """
                ),
                duplicateReclaimableBytes: try scalarInt64(
                    """
                    WITH keyed AS (
                        SELECT
                            \(duplicateKey) AS duplicate_key,
                            file_size,
                            indexed_at,
                            path
                        FROM catalog_photos
                        WHERE missing = 0
                    ),
                    duplicate_keys AS (
                        SELECT duplicate_key
                        FROM keyed
                        WHERE duplicate_key IS NOT NULL
                        GROUP BY duplicate_key
                        HAVING COUNT(*) > 1
                    ),
                    ranked AS (
                        SELECT
                            keyed.file_size,
                            ROW_NUMBER() OVER (
                                PARTITION BY keyed.duplicate_key
                                ORDER BY
                                    keyed.indexed_at ASC,
                                    keyed.path COLLATE NOCASE ASC
                            ) AS member_rank
                        FROM keyed
                        INNER JOIN duplicate_keys
                            ON duplicate_keys.duplicate_key =
                                keyed.duplicate_key
                    )
                    SELECT COALESCE(
                        SUM(
                            CASE
                                WHEN member_rank > 1
                                    THEN file_size
                                ELSE 0
                            END
                        ),
                        0
                    )
                    FROM ranked
                    """
                ),
                hashedPhotoCount: try scalarInt(
                    """
                    SELECT COUNT(*)
                    FROM catalog_photos
                    WHERE missing = 0
                        AND (
                            image_content_hash IS NOT NULL
                            OR content_hash IS NOT NULL
                        )
                    """
                ),
                photoStackCount: try scalarInt(
                    "SELECT COUNT(*) FROM catalog_photo_stacks"
                ),
                stackedPhotoCount: try scalarInt(
                    """
                    SELECT COUNT(*)
                    FROM catalog_photo_stack_members
                    """
                ),
                peopleCount: try scalarInt(
                    "SELECT COUNT(*) FROM catalog_people"
                ),
                faceCount: try scalarInt(
                    """
                    SELECT COUNT(*)
                    FROM catalog_faces
                    WHERE disposition <> 'ignored'
                    """
                ),
                unconfirmedFaceCount: try scalarInt(
                    """
                    SELECT COUNT(*)
                    FROM catalog_faces
                    WHERE person_id IS NULL
                        AND disposition = 'candidate'
                    """
                )
            )
        }
    }

    public func savedSmartCollections() throws -> [SavedSmartCollection] {
        try queue.sync {
            try loadSavedSmartCollections()
        }
    }

    public func saveSmartCollection(
        _ collection: SavedSmartCollection
    ) throws {
        try queue.sync {
            try validateCollectionSetExists(collection.parentSetID)
            let statement = try prepare(
                """
                INSERT INTO catalog_smart_collections(
                    id, name, filter_json, created_at, parent_set_id
                ) VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    filter_json = excluded.filter_json,
                    parent_set_id = excluded.parent_set_id
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(collection.id.uuidString, at: 1, in: statement)
            bind(collection.name, at: 2, in: statement)
            bind(try encode(collection.filter), at: 3, in: statement)
            bind(
                collection.createdAt.timeIntervalSince1970,
                at: 4,
                in: statement
            )
            bind(
                collection.parentSetID?.uuidString,
                at: 5,
                in: statement
            )
            try stepDone(statement)
        }
    }

    public func deleteSmartCollection(id: UUID) throws {
        try queue.sync {
            let statement = try prepare(
                "DELETE FROM catalog_smart_collections WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func collectionSets() throws -> [CatalogCollectionSet] {
        try queue.sync {
            try loadCollectionSets()
        }
    }

    public func saveCollectionSet(
        _ collectionSet: CatalogCollectionSet
    ) throws {
        try queue.sync {
            try validateCollectionSetParent(
                id: collectionSet.id,
                parentSetID: collectionSet.parentSetID
            )
            let statement = try prepare(
                """
                INSERT INTO catalog_collection_sets(
                    id, name, parent_set_id, created_at
                ) VALUES(?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    parent_set_id = excluded.parent_set_id
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(collectionSet.id.uuidString, at: 1, in: statement)
            bind(collectionSet.name, at: 2, in: statement)
            bind(
                collectionSet.parentSetID?.uuidString,
                at: 3,
                in: statement
            )
            bind(
                collectionSet.createdAt.timeIntervalSince1970,
                at: 4,
                in: statement
            )
            try stepDone(statement)
        }
    }

    public func deleteCollectionSet(id: UUID) throws {
        try queue.sync {
            let descendants =
                try collectionSetDescendantIDs(including: id)
            guard !descendants.isEmpty else {
                throw CatalogStoreError.collectionSetNotFound
            }
            try transaction {
                let smart = try prepare(
                    """
                    WITH RECURSIVE descendants(id) AS (
                        SELECT ?
                        UNION ALL
                        SELECT sets.id
                        FROM catalog_collection_sets AS sets
                        JOIN descendants
                            ON sets.parent_set_id =
                                descendants.id
                    )
                    DELETE FROM catalog_smart_collections
                    WHERE parent_set_id IN (
                        SELECT id FROM descendants
                    )
                    """
                )
                bind(id.uuidString, at: 1, in: smart)
                try stepDone(smart)
                sqlite3_finalize(smart)

                let statement = try prepare(
                    "DELETE FROM catalog_collection_sets WHERE id = ?"
                )
                bind(id.uuidString, at: 1, in: statement)
                try stepDone(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    public func duplicateCollectionSet(
        id: UUID
    ) throws -> CatalogCollectionSet {
        try queue.sync {
            let sets = try loadCollectionSets()
            guard let source = sets.first(where: {
                $0.id == id
            }) else {
                throw CatalogStoreError.collectionSetNotFound
            }
            let photos = try loadPhotoCollections()
            let smart = try loadSavedSmartCollections()
            let setsByID = Dictionary(
                uniqueKeysWithValues: sets.map {
                    ($0.id, $0)
                }
            )
            let childSets = Dictionary(
                grouping: sets,
                by: \.parentSetID
            )
            let photoBySet = Dictionary(
                grouping: photos,
                by: \.parentSetID
            )
            let smartBySet = Dictionary(
                grouping: smart,
                by: \.parentSetID
            )
            let duplicateRoot = CatalogCollectionSet(
                name: "\(source.name) Copy",
                parentSetID: source.parentSetID
            )

            func copySet(
                sourceID: UUID,
                destination: CatalogCollectionSet
            ) throws {
                let createSet = try prepare(
                    """
                    INSERT INTO catalog_collection_sets(
                        id, name, parent_set_id, created_at
                    ) VALUES(?, ?, ?, ?)
                    """
                )
                bind(
                    destination.id.uuidString,
                    at: 1,
                    in: createSet
                )
                bind(destination.name, at: 2, in: createSet)
                bind(
                    destination.parentSetID?.uuidString,
                    at: 3,
                    in: createSet
                )
                bind(
                    destination.createdAt.timeIntervalSince1970,
                    at: 4,
                    in: createSet
                )
                try stepDone(createSet)
                sqlite3_finalize(createSet)

                for sourceCollection in
                    photoBySet[Optional(sourceID)] ?? [] {
                    let duplicate = CatalogPhotoCollection(
                        name: sourceCollection.name,
                        parentSetID: destination.id
                    )
                    let createCollection = try prepare(
                        """
                        INSERT INTO catalog_collections(
                            id, name, parent_set_id,
                            created_at, is_target
                        ) VALUES(?, ?, ?, ?, 0)
                        """
                    )
                    bind(
                        duplicate.id.uuidString,
                        at: 1,
                        in: createCollection
                    )
                    bind(
                        duplicate.name,
                        at: 2,
                        in: createCollection
                    )
                    bind(
                        destination.id.uuidString,
                        at: 3,
                        in: createCollection
                    )
                    bind(
                        duplicate.createdAt.timeIntervalSince1970,
                        at: 4,
                        in: createCollection
                    )
                    try stepDone(createCollection)
                    sqlite3_finalize(createCollection)

                    let copyMembers = try prepare(
                        """
                        INSERT INTO catalog_collection_members(
                            collection_id, photo_id,
                            position, added_at
                        )
                        SELECT ?, photo_id, position, added_at
                        FROM catalog_collection_members
                        WHERE collection_id = ?
                        ORDER BY position ASC
                        """
                    )
                    bind(
                        duplicate.id.uuidString,
                        at: 1,
                        in: copyMembers
                    )
                    bind(
                        sourceCollection.id.uuidString,
                        at: 2,
                        in: copyMembers
                    )
                    try stepDone(copyMembers)
                    sqlite3_finalize(copyMembers)
                }

                for sourceSmart in
                    smartBySet[Optional(sourceID)] ?? [] {
                    let duplicate = SavedSmartCollection(
                        name: sourceSmart.name,
                        filter: sourceSmart.filter,
                        parentSetID: destination.id
                    )
                    let createSmart = try prepare(
                        """
                        INSERT INTO catalog_smart_collections(
                            id, name, filter_json,
                            created_at, parent_set_id
                        ) VALUES(?, ?, ?, ?, ?)
                        """
                    )
                    bind(
                        duplicate.id.uuidString,
                        at: 1,
                        in: createSmart
                    )
                    bind(
                        duplicate.name,
                        at: 2,
                        in: createSmart
                    )
                    bind(
                        try encode(duplicate.filter),
                        at: 3,
                        in: createSmart
                    )
                    bind(
                        duplicate.createdAt.timeIntervalSince1970,
                        at: 4,
                        in: createSmart
                    )
                    bind(
                        destination.id.uuidString,
                        at: 5,
                        in: createSmart
                    )
                    try stepDone(createSmart)
                    sqlite3_finalize(createSmart)
                }

                for child in childSets[Optional(sourceID)] ?? [] {
                    guard setsByID[child.id] != nil else {
                        continue
                    }
                    let duplicateChild =
                        CatalogCollectionSet(
                            name: child.name,
                            parentSetID: destination.id
                        )
                    try copySet(
                        sourceID: child.id,
                        destination: duplicateChild
                    )
                }
            }

            try transaction {
                try copySet(
                    sourceID: source.id,
                    destination: duplicateRoot
                )
            }
            return duplicateRoot
        }
    }

    public func photoCollections() throws
        -> [CatalogPhotoCollection] {
        try queue.sync {
            try loadPhotoCollections()
        }
    }

    public func savePhotoCollection(
        _ collection: CatalogPhotoCollection
    ) throws {
        try queue.sync {
            try validateCollectionSetExists(collection.parentSetID)
            try transaction {
                if collection.isTarget {
                    try execute(
                        "UPDATE catalog_collections SET is_target = 0"
                    )
                }
                let statement = try prepare(
                    """
                    INSERT INTO catalog_collections(
                        id, name, parent_set_id, created_at, is_target
                    ) VALUES(?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        parent_set_id = excluded.parent_set_id,
                        is_target = CASE
                            WHEN excluded.is_target = 1 THEN 1
                            ELSE catalog_collections.is_target
                        END
                    """
                )
                defer { sqlite3_finalize(statement) }
                bind(collection.id.uuidString, at: 1, in: statement)
                bind(collection.name, at: 2, in: statement)
                bind(
                    collection.parentSetID?.uuidString,
                    at: 3,
                    in: statement
                )
                bind(
                    collection.createdAt.timeIntervalSince1970,
                    at: 4,
                    in: statement
                )
                bind(collection.isTarget ? 1 : 0, at: 5, in: statement)
                try stepDone(statement)
            }
        }
    }

    @discardableResult
    public func saveQuickCollection(
        as collection: CatalogPhotoCollection,
        clearQuickCollection: Bool
    ) throws -> Int {
        try queue.sync {
            try validateCollectionSetExists(collection.parentSetID)
            var copiedCount = 0
            try transaction {
                let create = try prepare(
                    """
                    INSERT INTO catalog_collections(
                        id, name, parent_set_id, created_at, is_target
                    ) VALUES(?, ?, ?, ?, 0)
                    """
                )
                bind(collection.id.uuidString, at: 1, in: create)
                bind(collection.name, at: 2, in: create)
                bind(
                    collection.parentSetID?.uuidString,
                    at: 3,
                    in: create
                )
                bind(
                    collection.createdAt.timeIntervalSince1970,
                    at: 4,
                    in: create
                )
                try stepDone(create)
                sqlite3_finalize(create)

                let copy = try prepare(
                    """
                    INSERT INTO catalog_collection_members(
                        collection_id, photo_id, position, added_at
                    )
                    SELECT ?, photo_id, position, added_at
                    FROM catalog_quick_collection
                    ORDER BY position ASC
                    """
                )
                bind(collection.id.uuidString, at: 1, in: copy)
                try stepDone(copy)
                copiedCount = Int(
                    sqlite3_changes(try requireDatabase())
                )
                sqlite3_finalize(copy)

                if clearQuickCollection {
                    try execute(
                        "DELETE FROM catalog_quick_collection"
                    )
                }
            }
            return copiedCount
        }
    }

    public func duplicatePhotoCollection(
        id: UUID,
        name: String? = nil
    ) throws -> CatalogPhotoCollection {
        try queue.sync {
            guard let source = try loadPhotoCollections().first(
                where: { $0.id == id }
            ) else {
                throw CatalogStoreError.collectionNotFound
            }
            let duplicate = CatalogPhotoCollection(
                name: name ?? "\(source.name) Copy",
                parentSetID: source.parentSetID
            )
            try transaction {
                let create = try prepare(
                    """
                    INSERT INTO catalog_collections(
                        id, name, parent_set_id, created_at, is_target
                    ) VALUES(?, ?, ?, ?, 0)
                    """
                )
                bind(duplicate.id.uuidString, at: 1, in: create)
                bind(duplicate.name, at: 2, in: create)
                bind(
                    duplicate.parentSetID?.uuidString,
                    at: 3,
                    in: create
                )
                bind(
                    duplicate.createdAt.timeIntervalSince1970,
                    at: 4,
                    in: create
                )
                try stepDone(create)
                sqlite3_finalize(create)

                let copy = try prepare(
                    """
                    INSERT INTO catalog_collection_members(
                        collection_id, photo_id, position, added_at
                    )
                    SELECT ?, photo_id, position, added_at
                    FROM catalog_collection_members
                    WHERE collection_id = ?
                    ORDER BY position ASC
                    """
                )
                bind(duplicate.id.uuidString, at: 1, in: copy)
                bind(id.uuidString, at: 2, in: copy)
                try stepDone(copy)
                sqlite3_finalize(copy)
            }
            return CatalogPhotoCollection(
                id: duplicate.id,
                name: duplicate.name,
                parentSetID: duplicate.parentSetID,
                createdAt: duplicate.createdAt,
                photoCount: source.photoCount
            )
        }
    }

    public func deletePhotoCollection(id: UUID) throws {
        try queue.sync {
            let statement = try prepare(
                "DELETE FROM catalog_collections WHERE id = ?"
            )
            defer { sqlite3_finalize(statement) }
            bind(id.uuidString, at: 1, in: statement)
            try stepDone(statement)
            guard sqlite3_changes(try requireDatabase()) > 0 else {
                throw CatalogStoreError.collectionNotFound
            }
        }
    }

    public func setTargetPhotoCollection(id: UUID?) throws {
        try queue.sync {
            try transaction {
                try execute(
                    "UPDATE catalog_collections SET is_target = 0"
                )
                guard let id else { return }
                let statement = try prepare(
                    """
                    UPDATE catalog_collections
                    SET is_target = 1
                    WHERE id = ?
                    """
                )
                defer { sqlite3_finalize(statement) }
                bind(id.uuidString, at: 1, in: statement)
                try stepDone(statement)
                guard sqlite3_changes(try requireDatabase()) > 0 else {
                    throw CatalogStoreError.collectionNotFound
                }
            }
        }
    }

    public func photoCollectionPhotoIDs(
        collectionID: UUID
    ) throws -> [String] {
        try queue.sync {
            try loadPhotoCollectionPhotoIDs(
                collectionID: collectionID
            )
        }
    }

    public func photoCollectionMemberships() throws
        -> [String: Set<UUID>] {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT photo_id, collection_id
                FROM catalog_collection_members
                ORDER BY photo_id ASC, collection_id ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            var result: [String: Set<UUID>] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let photoID = text(at: 0, in: statement),
                      let collectionText = text(at: 1, in: statement),
                      let collectionID = UUID(
                          uuidString: collectionText
                      ) else {
                    continue
                }
                result[photoID, default: []].insert(collectionID)
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    @discardableResult
    public func setPhotoCollectionMembership(
        collectionID: UUID,
        photoIDs: [String],
        included: Bool
    ) throws -> Int {
        var seen: Set<String> = []
        let ids = photoIDs.filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
        guard !ids.isEmpty else { return 0 }

        return try queue.sync {
            guard try photoCollectionExists(collectionID) else {
                throw CatalogStoreError.collectionNotFound
            }
            var changedCount = 0
            try transaction {
                if included {
                    var nextPosition =
                        try scalarInt64(
                            """
                            SELECT COALESCE(MAX(position), 0)
                            FROM catalog_collection_members
                            WHERE collection_id =
                                '\(collectionID.uuidString)'
                            """
                        ) + 1
                    let statement = try prepare(
                        """
                        INSERT INTO catalog_collection_members(
                            collection_id, photo_id, position, added_at
                        )
                        SELECT ?, ?, ?, ?
                        WHERE EXISTS(
                            SELECT 1
                            FROM catalog_photos
                            WHERE id = ?
                        )
                        ON CONFLICT(collection_id, photo_id)
                            DO NOTHING
                        """
                    )
                    defer { sqlite3_finalize(statement) }
                    for id in ids {
                        sqlite3_reset(statement)
                        sqlite3_clear_bindings(statement)
                        bind(
                            collectionID.uuidString,
                            at: 1,
                            in: statement
                        )
                        bind(id, at: 2, in: statement)
                        bind(nextPosition, at: 3, in: statement)
                        bind(
                            Date().timeIntervalSince1970,
                            at: 4,
                            in: statement
                        )
                        bind(id, at: 5, in: statement)
                        try stepDone(statement)
                        if sqlite3_changes(
                            try requireDatabase()
                        ) > 0 {
                            changedCount += 1
                            nextPosition += 1
                        }
                    }
                } else {
                    let statement = try prepare(
                        """
                        DELETE FROM catalog_collection_members
                        WHERE collection_id = ? AND photo_id = ?
                        """
                    )
                    defer { sqlite3_finalize(statement) }
                    for id in ids {
                        sqlite3_reset(statement)
                        sqlite3_clear_bindings(statement)
                        bind(
                            collectionID.uuidString,
                            at: 1,
                            in: statement
                        )
                        bind(id, at: 2, in: statement)
                        try stepDone(statement)
                        changedCount += Int(
                            sqlite3_changes(
                                try requireDatabase()
                            )
                        )
                    }
                }
            }
            return changedCount
        }
    }

    public func reorderPhotoCollection(
        collectionID: UUID,
        photoIDs: [String]
    ) throws {
        var seen: Set<String> = []
        let ids = photoIDs.filter { seen.insert($0).inserted }
        try queue.sync {
            let existing = try loadPhotoCollectionPhotoIDs(
                collectionID: collectionID
            )
            let collectionExists =
                try photoCollectionExists(collectionID)
            guard !existing.isEmpty || collectionExists else {
                throw CatalogStoreError.collectionNotFound
            }
            guard Set(existing) == Set(ids),
                  existing.count == ids.count else {
                throw CatalogStoreError.queryFailed(
                    "Collection order must include every member exactly once."
                )
            }
            try transaction {
                let offset = max(1, ids.count)
                let moveAside = try prepare(
                    """
                    UPDATE catalog_collection_members
                    SET position = position + ?
                    WHERE collection_id = ?
                    """
                )
                bind(offset, at: 1, in: moveAside)
                bind(
                    collectionID.uuidString,
                    at: 2,
                    in: moveAside
                )
                try stepDone(moveAside)
                sqlite3_finalize(moveAside)

                let statement = try prepare(
                    """
                    UPDATE catalog_collection_members
                    SET position = ?
                    WHERE collection_id = ? AND photo_id = ?
                    """
                )
                defer { sqlite3_finalize(statement) }
                for (offset, id) in ids.enumerated() {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(offset + 1, at: 1, in: statement)
                    bind(
                        collectionID.uuidString,
                        at: 2,
                        in: statement
                    )
                    bind(id, at: 3, in: statement)
                    try stepDone(statement)
                }
            }
        }
    }

    public func quickCollectionPhotoIDs() throws -> Set<String> {
        try queue.sync {
            let statement = try prepare(
                """
                SELECT photo_id
                FROM catalog_quick_collection
                ORDER BY position ASC
                """
            )
            defer { sqlite3_finalize(statement) }
            var result: Set<String> = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let id = text(at: 0, in: statement) {
                    result.insert(id)
                }
            }
            try ensureNoStepError(statement)
            return result
        }
    }

    @discardableResult
    public func setQuickCollectionMembership(
        photoIDs: [String],
        included: Bool
    ) throws -> Int {
        var seen: Set<String> = []
        let ids = photoIDs.filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
        guard !ids.isEmpty else { return 0 }

        return try queue.sync {
            var changedCount = 0
            try transaction {
                if included {
                    var nextPosition =
                        try scalarInt64(
                            """
                            SELECT COALESCE(MAX(position), 0)
                            FROM catalog_quick_collection
                            """
                        ) + 1
                    let statement = try prepare(
                        """
                        INSERT INTO catalog_quick_collection(
                            photo_id, position, added_at
                        )
                        SELECT ?, ?, ?
                        WHERE EXISTS(
                            SELECT 1
                            FROM catalog_photos
                            WHERE id = ?
                        )
                        ON CONFLICT(photo_id) DO NOTHING
                        """
                    )
                    defer { sqlite3_finalize(statement) }
                    for id in ids {
                        sqlite3_reset(statement)
                        sqlite3_clear_bindings(statement)
                        bind(id, at: 1, in: statement)
                        bind(nextPosition, at: 2, in: statement)
                        bind(
                            Date().timeIntervalSince1970,
                            at: 3,
                            in: statement
                        )
                        bind(id, at: 4, in: statement)
                        try stepDone(statement)
                        if sqlite3_changes(
                            try requireDatabase()
                        ) > 0 {
                            changedCount += 1
                            nextPosition += 1
                        }
                    }
                } else {
                    let statement = try prepare(
                        """
                        DELETE FROM catalog_quick_collection
                        WHERE photo_id = ?
                        """
                    )
                    defer { sqlite3_finalize(statement) }
                    for id in ids {
                        sqlite3_reset(statement)
                        sqlite3_clear_bindings(statement)
                        bind(id, at: 1, in: statement)
                        try stepDone(statement)
                        changedCount += Int(
                            sqlite3_changes(
                                try requireDatabase()
                            )
                        )
                    }
                }
            }
            return changedCount
        }
    }

    @discardableResult
    public func clearQuickCollection() throws -> Int {
        try queue.sync {
            let statement = try prepare(
                "DELETE FROM catalog_quick_collection"
            )
            defer { sqlite3_finalize(statement) }
            try stepDone(statement)
            return Int(sqlite3_changes(try requireDatabase()))
        }
    }

    public func integrityCheck() throws -> Bool {
        try queue.sync {
            let statement = try prepare("PRAGMA quick_check")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                try ensureNoStepError(statement)
                return false
            }
            return text(at: 0, in: statement)?.lowercased() == "ok"
        }
    }

    private func loadCatalogFaces(
        photoID: String? = nil,
        photoIDs: Set<String>? = nil,
        includeIgnored: Bool
    ) throws -> [CatalogFace] {
        if let photoIDs, photoIDs.isEmpty {
            return []
        }
        var conditions: [String] = []
        if photoID != nil {
            conditions.append("photo_id = ?")
        }
        if photoIDs != nil {
            conditions.append(
                "photo_id IN (SELECT value FROM json_each(?))"
            )
        }
        if !includeIgnored {
            conditions.append("disposition <> 'ignored'")
        }
        let whereClause = conditions.isEmpty
            ? ""
            : "WHERE " + conditions.joined(separator: " AND ")
        let statement = try prepare(
            """
            SELECT
                id, photo_id,
                bounds_x, bounds_y,
                bounds_width, bounds_height,
                confidence, capture_quality,
                feature_print, person_id,
                disposition, analyzed_at
            FROM catalog_faces
            \(whereClause)
            ORDER BY photo_id ASC, bounds_x ASC, bounds_y DESC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        var bindingIndex: Int32 = 1
        if let photoID {
            bind(photoID, at: bindingIndex, in: statement)
            bindingIndex += 1
        }
        if let photoIDs {
            let encodedIDs = try encode(photoIDs.sorted())
            guard let json = String(
                data: encodedIDs,
                encoding: .utf8
            ) else {
                throw CatalogStoreError.encodingFailed
            }
            bind(json, at: bindingIndex, in: statement)
        }

        var result: [CatalogFace] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(at: 0, in: statement),
                  let photoID = text(at: 1, in: statement),
                  let featurePrintData = data(at: 8, in: statement),
                  let rawDisposition = text(at: 10, in: statement),
                  let disposition = PeopleFaceDisposition(
                    rawValue: rawDisposition
                  ) else {
                continue
            }
            let personID = text(at: 9, in: statement)
                .flatMap(UUID.init(uuidString:))
            result.append(CatalogFace(
                id: id,
                photoID: photoID,
                boundingBox: CGRect(
                    x: sqlite3_column_double(statement, 2),
                    y: sqlite3_column_double(statement, 3),
                    width: sqlite3_column_double(statement, 4),
                    height: sqlite3_column_double(statement, 5)
                ),
                confidence: sqlite3_column_double(statement, 6),
                captureQuality:
                    sqlite3_column_type(statement, 7) == SQLITE_NULL
                        ? nil
                        : sqlite3_column_double(statement, 7),
                featurePrintData: featurePrintData,
                personID: personID,
                disposition: disposition,
                analyzedAt: date(at: 11, in: statement)
                    ?? .distantPast
            ))
        }
        try ensureNoStepError(statement)
        return result
    }

    private func ensurePersonExists(_ id: UUID) throws {
        let statement = try prepare(
            "SELECT COUNT(*) FROM catalog_people WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              sqlite3_column_int64(statement, 0) == 1 else {
            throw CatalogStoreError.personNotFound
        }
    }

    private func ensureFacesExist(_ ids: [String]) throws {
        let statement = try prepare(
            "SELECT COUNT(*) FROM catalog_faces WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        for id in ids {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(id, at: 1, in: statement)
            guard sqlite3_step(statement) == SQLITE_ROW,
                  sqlite3_column_int64(statement, 0) == 1 else {
                throw CatalogStoreError.faceNotFound
            }
        }
    }

    private func assignFacesUnchecked(
        _ ids: [String],
        to personID: UUID
    ) throws {
        let statement = try prepare(
            """
            UPDATE catalog_faces
            SET person_id = ?, disposition = 'candidate'
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        for id in ids {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(personID.uuidString, at: 1, in: statement)
            bind(id, at: 2, in: statement)
            try stepDone(statement)
        }
        let touch = try prepare(
            """
            UPDATE catalog_people
            SET updated_at = ?
            WHERE id = ?
            """
        )
        bind(Date().timeIntervalSince1970, at: 1, in: touch)
        bind(personID.uuidString, at: 2, in: touch)
        try stepDone(touch)
        sqlite3_finalize(touch)
    }

    private func updateFaces(
        _ faceIDs: [String],
        personID: UUID?,
        disposition: PeopleFaceDisposition
    ) throws {
        let ids = Array(Set(faceIDs)).sorted()
        guard !ids.isEmpty else {
            throw CatalogStoreError.peopleSelectionEmpty
        }
        try queue.sync {
            try transaction {
                if let personID {
                    try ensurePersonExists(personID)
                }
                try ensureFacesExist(ids)
                let statement = try prepare(
                    """
                    UPDATE catalog_faces
                    SET person_id = ?, disposition = ?
                    WHERE id = ?
                    """
                )
                defer { sqlite3_finalize(statement) }
                for id in ids {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    bind(
                        personID?.uuidString,
                        at: 1,
                        in: statement
                    )
                    bind(disposition.rawValue, at: 2, in: statement)
                    bind(id, at: 3, in: statement)
                    try stepDone(statement)
                }
            }
        }
    }

    private static func normalizedPersonName(
        _ rawName: String
    ) -> String {
        rawName
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }

    private static func reconciledFaces(
        detections: [PeopleFaceDetection],
        photoID: String,
        existing: [CatalogFace],
        analyzedAt: Date
    ) -> [CatalogFace] {
        var available = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.id, $0) }
        )
        let orderedDetections = detections
            .prefix(32)
            .map { detection in
                PeopleFaceDetection(
                    boundingBox:
                        normalizedFaceBounds(detection.boundingBox),
                    confidence: detection.confidence,
                    captureQuality: detection.captureQuality,
                    featurePrintData: detection.featurePrintData
                )
            }
            .filter {
                $0.boundingBox.width > 0
                    && $0.boundingBox.height > 0
                    && !$0.featurePrintData.isEmpty
            }
            .sorted {
                if $0.boundingBox.minX != $1.boundingBox.minX {
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                return $0.boundingBox.maxY > $1.boundingBox.maxY
            }

        return orderedDetections.map { detection in
            let match = available.values
                .map {
                    (
                        face: $0,
                        overlap: intersectionOverUnion(
                            detection.boundingBox,
                            $0.boundingBox
                        )
                    )
                }
                .filter { $0.overlap >= 0.45 }
                .max {
                    if $0.overlap != $1.overlap {
                        return $0.overlap < $1.overlap
                    }
                    return $0.face.id > $1.face.id
                }?
                .face
            if let match {
                available[match.id] = nil
            }
            return CatalogFace(
                id: match?.id ?? UUID().uuidString,
                photoID: photoID,
                boundingBox: detection.boundingBox,
                confidence: detection.confidence,
                captureQuality: detection.captureQuality,
                featurePrintData: detection.featurePrintData,
                personID: match?.personID,
                disposition:
                    match?.disposition ?? .candidate,
                analyzedAt: analyzedAt
            )
        }
    }

    private static func normalizedFaceBounds(
        _ rect: CGRect
    ) -> CGRect {
        let minX = min(1, max(0, rect.minX))
        let minY = min(1, max(0, rect.minY))
        let maxX = min(1, max(0, rect.maxX))
        let maxY = min(1, max(0, rect.maxY))
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    private static func intersectionOverUnion(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea =
            Double(intersection.width * intersection.height)
        let unionArea =
            Double(lhs.width * lhs.height + rhs.width * rhs.height)
                - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    // MARK: - Database setup

    private func openWithRecovery() {
        do {
            try openDatabase(at: databaseURL.path)
            try migrate()
            guard try checkIntegrity() else {
                throw SQLiteFailure(code: SQLITE_CORRUPT, message: "quick_check failed")
            }
        } catch let failure as SQLiteFailure
            where failure.code == SQLITE_CORRUPT
                || failure.code == SQLITE_NOTADB {
            closeDatabase()
            let backupName = backupCorruptDatabase()
            do {
                try openDatabase(at: databaseURL.path)
                try migrate()
                startupWarning =
                    "A damaged catalog was moved to \(backupName). A new catalog was created."
            } catch {
                closeDatabase()
                openMemoryFallback(after: error)
            }
        } catch {
            closeDatabase()
            openMemoryFallback(after: error)
        }
    }

    private func openMemoryFallback(after error: Error) {
        do {
            try openDatabase(at: ":memory:")
            try migrate()
            startupWarning =
                "The disk catalog could not be opened. This session is using a temporary catalog: \(error.localizedDescription)"
        } catch {
            startupWarning =
                "The photo catalog could not be opened: \(error.localizedDescription)"
        }
    }

    private func openDatabase(at path: String) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "unknown SQLite error"
            if let handle { sqlite3_close_v2(handle) }
            throw SQLiteFailure(code: result, message: message)
        }
        database = handle
        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA foreign_keys = ON")
        if path != ":memory:" {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = NORMAL")
            try execute("PRAGMA wal_autocheckpoint = 1000")
        }
    }

    private func closeDatabase() {
        if let database {
            sqlite3_close_v2(database)
            self.database = nil
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_roots (
                path TEXT PRIMARY KEY NOT NULL,
                last_scanned REAL NOT NULL,
                recursive INTEGER NOT NULL DEFAULT 1
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_photos (
                id TEXT PRIMARY KEY NOT NULL,
                path TEXT NOT NULL,
                root_path TEXT NOT NULL,
                filename TEXT NOT NULL,
                file_extension TEXT NOT NULL,
                file_size INTEGER NOT NULL,
                creation_date REAL,
                modification_date REAL,
                format TEXT NOT NULL,
                metadata_json BLOB,
                state_json BLOB NOT NULL,
                capture_date REAL,
                camera_make TEXT,
                camera_model TEXT,
                lens_model TEXT,
                rating INTEGER NOT NULL DEFAULT 0,
                pick_status INTEGER NOT NULL DEFAULT 0,
                favorite INTEGER NOT NULL DEFAULT 0,
                color_label TEXT NOT NULL DEFAULT '',
                edited INTEGER NOT NULL DEFAULT 0,
                note TEXT NOT NULL DEFAULT '',
                keyword_count INTEGER NOT NULL DEFAULT 0,
                latitude REAL,
                longitude REAL,
                altitude REAL,
                location_source TEXT NOT NULL DEFAULT 'none',
                indexed_at REAL NOT NULL,
                last_seen REAL NOT NULL,
                missing INTEGER NOT NULL DEFAULT 0,
                content_hash TEXT,
                image_content_hash TEXT,
                FOREIGN KEY(root_path) REFERENCES catalog_roots(path)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_photo_keywords (
                photo_id TEXT NOT NULL,
                keyword TEXT NOT NULL,
                keyword_folded TEXT NOT NULL,
                PRIMARY KEY(photo_id, keyword_folded),
                FOREIGN KEY(photo_id) REFERENCES catalog_photos(id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_collection_sets (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                parent_set_id TEXT,
                created_at REAL NOT NULL,
                FOREIGN KEY(parent_set_id)
                    REFERENCES catalog_collection_sets(id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_smart_collections (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                filter_json BLOB NOT NULL,
                created_at REAL NOT NULL,
                parent_set_id TEXT,
                FOREIGN KEY(parent_set_id)
                    REFERENCES catalog_collection_sets(id)
                    ON DELETE SET NULL
            )
            """
        )
        if try !tableHasColumn(
            table: "catalog_smart_collections",
            column: "parent_set_id"
        ) {
            try execute(
                """
                ALTER TABLE catalog_smart_collections
                ADD COLUMN parent_set_id TEXT
                """
            )
        }
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_collections (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                parent_set_id TEXT,
                created_at REAL NOT NULL,
                is_target INTEGER NOT NULL DEFAULT 0
                    CHECK(is_target IN (0, 1)),
                FOREIGN KEY(parent_set_id)
                    REFERENCES catalog_collection_sets(id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_collection_members (
                collection_id TEXT NOT NULL,
                photo_id TEXT NOT NULL,
                position INTEGER NOT NULL CHECK(position >= 1),
                added_at REAL NOT NULL,
                PRIMARY KEY(collection_id, photo_id),
                UNIQUE(collection_id, position),
                FOREIGN KEY(collection_id)
                    REFERENCES catalog_collections(id)
                    ON DELETE CASCADE,
                FOREIGN KEY(photo_id) REFERENCES catalog_photos(id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_quick_collection (
                photo_id TEXT PRIMARY KEY NOT NULL,
                position INTEGER NOT NULL UNIQUE
                    CHECK(position >= 1),
                added_at REAL NOT NULL,
                FOREIGN KEY(photo_id) REFERENCES catalog_photos(id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_keyword_definitions (
                keyword_folded TEXT PRIMARY KEY NOT NULL,
                keyword TEXT NOT NULL,
                synonyms_json BLOB NOT NULL,
                include_on_export INTEGER NOT NULL DEFAULT 1,
                export_synonyms INTEGER NOT NULL DEFAULT 1,
                export_containing INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_culling_analysis (
                photo_id TEXT PRIMARY KEY NOT NULL,
                file_size INTEGER,
                modification_date REAL,
                engine_version INTEGER,
                analysis_json BLOB,
                analyzed_at REAL,
                manual_decision TEXT,
                FOREIGN KEY(photo_id) REFERENCES catalog_photos(id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_people (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_face_analysis (
                photo_id TEXT PRIMARY KEY NOT NULL,
                file_size INTEGER NOT NULL,
                modification_date REAL,
                engine_version INTEGER NOT NULL,
                analyzed_at REAL NOT NULL,
                face_count INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY(photo_id) REFERENCES catalog_photos(id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_faces (
                id TEXT PRIMARY KEY NOT NULL,
                photo_id TEXT NOT NULL,
                bounds_x REAL NOT NULL,
                bounds_y REAL NOT NULL,
                bounds_width REAL NOT NULL,
                bounds_height REAL NOT NULL,
                confidence REAL NOT NULL,
                capture_quality REAL,
                feature_print BLOB NOT NULL,
                person_id TEXT,
                disposition TEXT NOT NULL DEFAULT 'candidate',
                analyzed_at REAL NOT NULL,
                FOREIGN KEY(photo_id) REFERENCES catalog_photos(id)
                    ON DELETE CASCADE,
                FOREIGN KEY(person_id) REFERENCES catalog_people(id)
                    ON DELETE SET NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_photo_stacks (
                id TEXT PRIMARY KEY NOT NULL,
                scope_path TEXT NOT NULL,
                collapsed INTEGER NOT NULL DEFAULT 1,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS catalog_photo_stack_members (
                stack_id TEXT NOT NULL,
                photo_id TEXT NOT NULL UNIQUE,
                position INTEGER NOT NULL CHECK(position >= 1),
                PRIMARY KEY(stack_id, photo_id),
                UNIQUE(stack_id, position),
                FOREIGN KEY(stack_id) REFERENCES catalog_photo_stacks(id)
                    ON DELETE CASCADE,
                FOREIGN KEY(photo_id) REFERENCES catalog_photos(id)
                    ON DELETE CASCADE
            )
            """
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS catalog_photos_path ON catalog_photos(path)"
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS catalog_photos_root ON catalog_photos(root_path)"
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_photos_smart
            ON catalog_photos(missing, edited, rating, pick_status, keyword_count)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_keywords_name
            ON catalog_photo_keywords(keyword_folded)
            """
        )
        if try !tableHasColumn(
            table: "catalog_photos",
            column: "content_hash"
        ) {
            try execute(
                "ALTER TABLE catalog_photos ADD COLUMN content_hash TEXT"
            )
        }
        if try !tableHasColumn(
            table: "catalog_photos",
            column: "image_content_hash"
        ) {
            try execute(
                """
                ALTER TABLE catalog_photos
                ADD COLUMN image_content_hash TEXT
                """
            )
        }
        if try !tableHasColumn(
            table: "catalog_photos",
            column: "color_label"
        ) {
            try execute(
                """
                ALTER TABLE catalog_photos
                ADD COLUMN color_label TEXT NOT NULL DEFAULT ''
                """
            )
            try execute(
                """
                UPDATE catalog_photos
                SET color_label = CASE LOWER(
                    COALESCE(
                        json_extract(
                            CAST(state_json AS TEXT),
                            '$.colorLabel'
                        ),
                        ''
                    )
                )
                    WHEN 'red' THEN 'red'
                    WHEN 'yellow' THEN 'yellow'
                    WHEN 'green' THEN 'green'
                    WHEN 'blue' THEN 'blue'
                    WHEN 'purple' THEN 'purple'
                    ELSE ''
                END
                """
            )
        }
        let hasLatitude = try tableHasColumn(
            table: "catalog_photos",
            column: "latitude"
        )
        let hasLongitude = try tableHasColumn(
            table: "catalog_photos",
            column: "longitude"
        )
        let hasAltitude = try tableHasColumn(
            table: "catalog_photos",
            column: "altitude"
        )
        let hasLocationSource = try tableHasColumn(
            table: "catalog_photos",
            column: "location_source"
        )
        let needsLocationBackfill =
            !hasLatitude
                || !hasLongitude
                || !hasAltitude
                || !hasLocationSource
        if !hasLatitude {
            try execute(
                "ALTER TABLE catalog_photos ADD COLUMN latitude REAL"
            )
        }
        if !hasLongitude {
            try execute(
                "ALTER TABLE catalog_photos ADD COLUMN longitude REAL"
            )
        }
        if !hasAltitude {
            try execute(
                "ALTER TABLE catalog_photos ADD COLUMN altitude REAL"
            )
        }
        if !hasLocationSource {
            try execute(
                """
                ALTER TABLE catalog_photos
                ADD COLUMN location_source TEXT NOT NULL DEFAULT 'none'
                """
            )
        }
        if needsLocationBackfill {
            try execute(
            """
            UPDATE catalog_photos
            SET
                latitude = CASE
                    WHEN COALESCE(
                        json_extract(
                            CAST(state_json AS TEXT),
                            '$.locationIsRemoved'
                        ),
                        0
                    ) = 1
                    THEN NULL
                    ELSE COALESCE(
                        json_extract(
                            CAST(state_json AS TEXT),
                            '$.locationOverride.latitude'
                        ),
                        json_extract(
                            CAST(metadata_json AS TEXT),
                            '$.location.latitude'
                        )
                    )
                END,
                longitude = CASE
                    WHEN COALESCE(
                        json_extract(
                            CAST(state_json AS TEXT),
                            '$.locationIsRemoved'
                        ),
                        0
                    ) = 1
                    THEN NULL
                    ELSE COALESCE(
                        json_extract(
                            CAST(state_json AS TEXT),
                            '$.locationOverride.longitude'
                        ),
                        json_extract(
                            CAST(metadata_json AS TEXT),
                            '$.location.longitude'
                        )
                    )
                END,
                altitude = CASE
                    WHEN COALESCE(
                        json_extract(
                            CAST(state_json AS TEXT),
                            '$.locationIsRemoved'
                        ),
                        0
                    ) = 1
                    THEN NULL
                    ELSE COALESCE(
                        json_extract(
                            CAST(state_json AS TEXT),
                            '$.locationOverride.altitude'
                        ),
                        json_extract(
                            CAST(metadata_json AS TEXT),
                            '$.location.altitude'
                        )
                    )
                END,
                location_source = CASE
                    WHEN COALESCE(
                        json_extract(
                            CAST(state_json AS TEXT),
                            '$.locationIsRemoved'
                        ),
                        0
                    ) = 1
                    THEN 'removed'
                    WHEN json_extract(
                        CAST(state_json AS TEXT),
                        '$.locationOverride.latitude'
                    ) IS NOT NULL
                    THEN 'manual'
                    WHEN json_extract(
                        CAST(metadata_json AS TEXT),
                        '$.location.latitude'
                    ) IS NOT NULL
                    THEN 'embedded'
                    ELSE 'none'
                END
            """
            )
        }
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_photos_content_hash
            ON catalog_photos(content_hash)
            WHERE content_hash IS NOT NULL
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_photos_image_content_hash
            ON catalog_photos(image_content_hash)
            WHERE image_content_hash IS NOT NULL
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_photos_color_label
            ON catalog_photos(missing, color_label)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_photos_location
            ON catalog_photos(missing, latitude, longitude)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_culling_engine
            ON catalog_culling_analysis(engine_version)
            WHERE analysis_json IS NOT NULL
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_face_analysis_engine
            ON catalog_face_analysis(engine_version)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_faces_photo
            ON catalog_faces(photo_id)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_faces_person
            ON catalog_faces(person_id, disposition)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_photo_stack_members_stack
            ON catalog_photo_stack_members(stack_id, position)
            """
        )
        try execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS catalog_collections_target
            ON catalog_collections(is_target)
            WHERE is_target = 1
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_collection_members_photo
            ON catalog_collection_members(photo_id, collection_id)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_collection_sets_parent
            ON catalog_collection_sets(parent_set_id, name)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_collections_parent
            ON catalog_collections(parent_set_id, name)
            """
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS catalog_smart_collections_parent
            ON catalog_smart_collections(parent_set_id, name)
            """
        )
        try removeOrphanedPhotoStacks()
        try execute("PRAGMA user_version = 12")
    }

    private func tableHasColumn(
        table: String,
        column: String
    ) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if text(at: 1, in: statement) == column {
                return true
            }
        }
        try ensureNoStepError(statement)
        return false
    }

    private func checkIntegrity() throws -> Bool {
        let statement = try prepare("PRAGMA quick_check")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            try ensureNoStepError(statement)
            return false
        }
        return text(at: 0, in: statement)?.lowercased() == "ok"
    }

    private func backupCorruptDatabase() -> String {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = databaseURL.appendingPathExtension("corrupt.\(stamp)")
        let fm = FileManager.default
        if fm.fileExists(atPath: databaseURL.path) {
            try? fm.moveItem(at: databaseURL, to: backup)
        }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            guard fm.fileExists(atPath: sidecar.path) else { continue }
            let destination = URL(fileURLWithPath: backup.path + suffix)
            try? fm.moveItem(at: sidecar, to: destination)
        }
        return backup.lastPathComponent
    }

    // MARK: - Mutations

    private func locationIndexValues(
        id: String,
        state: PhotoUserState
    ) throws -> (
        location: PhotoLocation?,
        source: PhotoLocationSource
    ) {
        let statement = try prepare(
            """
            SELECT metadata_json
            FROM catalog_photos
            WHERE id = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        let metadata: PhotoMetadata?
        if sqlite3_step(statement) == SQLITE_ROW,
           let data = data(at: 0, in: statement) {
            metadata = try? JSONDecoder().decode(
                PhotoMetadata.self,
                from: data
            )
        } else {
            metadata = nil
        }
        return locationIndexValues(
            state: state,
            metadata: metadata
        )
    }

    private func locationIndexValues(
        state: PhotoUserState,
        metadata: PhotoMetadata?
    ) -> (
        location: PhotoLocation?,
        source: PhotoLocationSource
    ) {
        (
            state.effectiveLocation(
                embedded: metadata?.location
            ),
            state.locationSource(
                embedded: metadata?.location
            )
        )
    }

    private func upsert(
        asset: PhotoAsset,
        rootPath: String,
        indexedAt: Date? = nil,
        contentHash: String? = nil
    ) throws {
        let removeOldPath = try prepare(
            "DELETE FROM catalog_photos WHERE path = ? AND id <> ?"
        )
        bind(asset.path, at: 1, in: removeOldPath)
        bind(asset.id, at: 2, in: removeOldPath)
        try stepDone(removeOldPath)
        sqlite3_finalize(removeOldPath)

        let now = Date().timeIntervalSince1970
        let statement = try prepare(
            """
            INSERT INTO catalog_photos (
                id, path, root_path, filename, file_extension, file_size,
                creation_date, modification_date, format, metadata_json,
                state_json, capture_date, camera_make, camera_model,
                lens_model, rating, pick_status, favorite, color_label,
                edited, note, keyword_count, latitude, longitude, altitude,
                location_source, indexed_at, last_seen, missing, content_hash,
                image_content_hash
            )
            VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
                ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, NULL
            )
            ON CONFLICT(id) DO UPDATE SET
                path = excluded.path,
                root_path = excluded.root_path,
                filename = excluded.filename,
                file_extension = excluded.file_extension,
                file_size = excluded.file_size,
                creation_date = excluded.creation_date,
                modification_date = excluded.modification_date,
                format = excluded.format,
                metadata_json = COALESCE(
                    excluded.metadata_json,
                    catalog_photos.metadata_json
                ),
                state_json = excluded.state_json,
                capture_date = COALESCE(
                    excluded.capture_date,
                    catalog_photos.capture_date
                ),
                camera_make = COALESCE(
                    excluded.camera_make,
                    catalog_photos.camera_make
                ),
                camera_model = COALESCE(
                    excluded.camera_model,
                    catalog_photos.camera_model
                ),
                lens_model = COALESCE(
                    excluded.lens_model,
                    catalog_photos.lens_model
                ),
                rating = excluded.rating,
                pick_status = excluded.pick_status,
                favorite = excluded.favorite,
                color_label = excluded.color_label,
                edited = excluded.edited,
                note = excluded.note,
                keyword_count = excluded.keyword_count,
                latitude = excluded.latitude,
                longitude = excluded.longitude,
                altitude = excluded.altitude,
                location_source = excluded.location_source,
                last_seen = excluded.last_seen,
                missing = 0,
                content_hash = CASE
                    WHEN excluded.content_hash IS NOT NULL
                        THEN excluded.content_hash
                    WHEN excluded.file_size = catalog_photos.file_size
                        AND excluded.modification_date
                            IS catalog_photos.modification_date
                        THEN catalog_photos.content_hash
                    ELSE NULL
                END,
                image_content_hash = CASE
                    WHEN excluded.file_size = catalog_photos.file_size
                        AND excluded.modification_date
                            IS catalog_photos.modification_date
                        THEN catalog_photos.image_content_hash
                    ELSE NULL
                END
            """
        )
        defer { sqlite3_finalize(statement) }
        let state = asset.userState
        let location = locationIndexValues(
            state: state,
            metadata: asset.metadata
        )
        bind(asset.id, at: 1, in: statement)
        bind(asset.path, at: 2, in: statement)
        bind(rootPath, at: 3, in: statement)
        bind(asset.filename, at: 4, in: statement)
        bind(asset.fileExtension, at: 5, in: statement)
        bind(asset.fileSize, at: 6, in: statement)
        bind(asset.creationDate, at: 7, in: statement)
        bind(asset.modificationDate, at: 8, in: statement)
        bind(asset.format.rawValue, at: 9, in: statement)
        if let metadata = asset.metadata {
            bind(try encode(metadata), at: 10, in: statement)
        } else {
            bindNull(at: 10, in: statement)
        }
        bind(try encode(state), at: 11, in: statement)
        bind(asset.metadata?.captureDate, at: 12, in: statement)
        bind(asset.metadata?.cameraMake, at: 13, in: statement)
        bind(asset.metadata?.cameraModel, at: 14, in: statement)
        bind(asset.metadata?.lensModel, at: 15, in: statement)
        bind(state.rating, at: 16, in: statement)
        bind(state.pickStatus.rawValue, at: 17, in: statement)
        bind(state.favorite ? 1 : 0, at: 18, in: statement)
        bind(state.colorLabel.rawValue, at: 19, in: statement)
        bind(state.adjustments.isNeutral ? 0 : 1, at: 20, in: statement)
        bind(state.note, at: 21, in: statement)
        bind(state.keywords.count, at: 22, in: statement)
        bind(location.location?.latitude, at: 23, in: statement)
        bind(location.location?.longitude, at: 24, in: statement)
        bind(location.location?.altitude, at: 25, in: statement)
        bind(location.source.rawValue, at: 26, in: statement)
        bind(
            indexedAt?.timeIntervalSince1970 ?? now,
            at: 27,
            in: statement
        )
        bind(now, at: 28, in: statement)
        bind(contentHash?.lowercased(), at: 29, in: statement)
        try stepDone(statement)
        try replaceKeywords(photoID: asset.id, keywords: state.keywords)
    }

    private func replaceKeywords(
        photoID: String,
        keywords: [String]
    ) throws {
        let delete = try prepare(
            "DELETE FROM catalog_photo_keywords WHERE photo_id = ?"
        )
        bind(photoID, at: 1, in: delete)
        try stepDone(delete)
        sqlite3_finalize(delete)

        guard !keywords.isEmpty else { return }
        let insert = try prepare(
            """
            INSERT OR REPLACE INTO catalog_photo_keywords(
                photo_id, keyword, keyword_folded
            ) VALUES(?, ?, ?)
            """
        )
        defer { sqlite3_finalize(insert) }
        for keyword in keywords {
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            bind(photoID, at: 1, in: insert)
            bind(keyword, at: 2, in: insert)
            bind(foldedKeyword(keyword), at: 3, in: insert)
            try stepDone(insert)
        }
    }

    private func catalogEntry(id: String) throws -> CatalogEntry? {
        try catalogEntry(
            whereClause: "id = ?",
            value: id
        )
    }

    private func catalogEntry(path: String) throws -> CatalogEntry? {
        try catalogEntry(
            whereClause: "path = ?",
            value: path
        )
    }

    private func catalogEntry(
        whereClause: String,
        value: String
    ) throws -> CatalogEntry? {
        let statement = try prepare(
            """
            SELECT
                id, path, root_path, filename, file_extension,
                file_size, creation_date, modification_date, format,
                metadata_json, state_json, indexed_at, last_seen, missing
            FROM catalog_photos
            WHERE \(whereClause)
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(value, at: 1, in: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return decodeCatalogEntry(from: statement)
        }
        guard result == SQLITE_DONE else {
            try ensureNoStepError(statement)
            return nil
        }
        return nil
    }

    private func decodeCatalogEntry(
        from statement: OpaquePointer
    ) -> CatalogEntry? {
        guard let id = text(at: 0, in: statement),
              let path = text(at: 1, in: statement),
              let rootPath = text(at: 2, in: statement),
              let filename = text(at: 3, in: statement),
              let fileExtension = text(at: 4, in: statement),
              let formatRaw = text(at: 8, in: statement),
              let format = FileFormat(rawValue: formatRaw),
              let stateData = data(at: 10, in: statement),
              let state = try? JSONDecoder().decode(
                  PhotoUserState.self,
                  from: stateData
              ) else {
            return nil
        }
        let metadata: PhotoMetadata?
        if let metadataData = data(at: 9, in: statement) {
            metadata = try? JSONDecoder().decode(
                PhotoMetadata.self,
                from: metadataData
            )
        } else {
            metadata = nil
        }
        return CatalogEntry(
            id: id,
            path: path,
            rootPath: rootPath,
            filename: filename,
            fileExtension: fileExtension,
            fileSize: sqlite3_column_int64(statement, 5),
            creationDate: date(at: 6, in: statement),
            modificationDate: date(at: 7, in: statement),
            format: format,
            metadata: metadata,
            userState: state,
            indexedAt: date(at: 11, in: statement) ?? .distantPast,
            lastSeen: date(at: 12, in: statement) ?? .distantPast,
            isMissing: sqlite3_column_int(statement, 13) != 0
        )
    }

    private func removeEmptyRoots() throws {
        try execute(
            """
            DELETE FROM catalog_roots
            WHERE NOT EXISTS (
                SELECT 1
                FROM catalog_photos
                WHERE catalog_photos.root_path = catalog_roots.path
            )
            """
        )
    }

    // MARK: - Photo stacks

    private func uniquePhotoIDs(
        _ photoIDs: [PhotoAsset.ID]
    ) -> [PhotoAsset.ID] {
        var seen: Set<PhotoAsset.ID> = []
        return photoIDs.filter { seen.insert($0).inserted }
    }

    private func photoDirectoryPaths(
        for photoIDs: [PhotoAsset.ID]
    ) throws -> [PhotoAsset.ID: String] {
        guard !photoIDs.isEmpty else { return [:] }
        let placeholders = Array(
            repeating: "?",
            count: photoIDs.count
        ).joined(separator: ", ")
        let statement = try prepare(
            """
            SELECT id, path
            FROM catalog_photos
            WHERE id IN (\(placeholders))
            """
        )
        defer { sqlite3_finalize(statement) }
        for (offset, photoID) in photoIDs.enumerated() {
            bind(photoID, at: Int32(offset + 1), in: statement)
        }
        var result: [PhotoAsset.ID: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let photoID = text(at: 0, in: statement),
                  let path = text(at: 1, in: statement) else {
                continue
            }
            result[photoID] = URL(
                fileURLWithPath: path
            )
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        }
        try ensureNoStepError(statement)
        guard result.count == photoIDs.count else {
            throw CatalogStoreError.photoNotFound
        }
        return result
    }

    private func photoStackID(
        containing photoID: PhotoAsset.ID
    ) throws -> UUID? {
        let statement = try prepare(
            """
            SELECT stack_id
            FROM catalog_photo_stack_members
            WHERE photo_id = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(photoID, at: 1, in: statement)
        let step = sqlite3_step(statement)
        if step == SQLITE_ROW,
           let rawID = text(at: 0, in: statement) {
            return UUID(uuidString: rawID)
        }
        guard step == SQLITE_DONE else {
            try ensureNoStepError(statement)
            return nil
        }
        return nil
    }

    private func photoStackIDs(
        containingAny photoIDs: [PhotoAsset.ID]
    ) throws -> [UUID] {
        guard !photoIDs.isEmpty else { return [] }
        let placeholders = Array(
            repeating: "?",
            count: photoIDs.count
        ).joined(separator: ", ")
        let statement = try prepare(
            """
            SELECT DISTINCT stack_id
            FROM catalog_photo_stack_members
            WHERE photo_id IN (\(placeholders))
            ORDER BY stack_id
            """
        )
        defer { sqlite3_finalize(statement) }
        for (offset, photoID) in photoIDs.enumerated() {
            bind(photoID, at: Int32(offset + 1), in: statement)
        }
        var result: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let rawID = text(at: 0, in: statement),
               let id = UUID(uuidString: rawID) {
                result.append(id)
            }
        }
        try ensureNoStepError(statement)
        return result
    }

    private func loadPhotoStacks() throws -> [CatalogPhotoStack] {
        let statement = try prepare(
            """
            SELECT id
            FROM catalog_photo_stacks
            ORDER BY created_at ASC, id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        var ids: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let rawID = text(at: 0, in: statement),
               let id = UUID(uuidString: rawID) {
                ids.append(id)
            }
        }
        try ensureNoStepError(statement)
        return try ids.compactMap(loadPhotoStack)
    }

    private func loadPhotoStack(
        id: UUID
    ) throws -> CatalogPhotoStack? {
        let stackStatement = try prepare(
            """
            SELECT scope_path, collapsed, created_at, updated_at
            FROM catalog_photo_stacks
            WHERE id = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(stackStatement) }
        bind(id.uuidString, at: 1, in: stackStatement)
        let step = sqlite3_step(stackStatement)
        guard step == SQLITE_ROW else {
            guard step == SQLITE_DONE else {
                try ensureNoStepError(stackStatement)
                return nil
            }
            return nil
        }
        guard let scopePath = text(at: 0, in: stackStatement) else {
            throw CatalogStoreError.queryFailed(
                "A photo stack has no folder scope."
            )
        }
        let isCollapsed = sqlite3_column_int(
            stackStatement,
            1
        ) != 0
        let createdAt = date(at: 2, in: stackStatement) ?? .distantPast
        let updatedAt = date(at: 3, in: stackStatement) ?? createdAt

        let memberStatement = try prepare(
            """
            SELECT photo_id
            FROM catalog_photo_stack_members
            WHERE stack_id = ?
            ORDER BY position ASC
            """
        )
        defer { sqlite3_finalize(memberStatement) }
        bind(id.uuidString, at: 1, in: memberStatement)
        var memberIDs: [PhotoAsset.ID] = []
        while sqlite3_step(memberStatement) == SQLITE_ROW {
            if let photoID = text(at: 0, in: memberStatement) {
                memberIDs.append(photoID)
            }
        }
        try ensureNoStepError(memberStatement)
        return CatalogPhotoStack(
            id: id,
            scopePath: scopePath,
            memberIDs: memberIDs,
            isCollapsed: isCollapsed,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func createOrMergePhotoStack(
        photoIDs: [PhotoAsset.ID],
        collapsed: Bool,
        allowsExistingStack: Bool
    ) throws -> CatalogPhotoStack {
        let paths = try photoDirectoryPaths(for: photoIDs)
        let scopePaths = Set(paths.values)
        guard scopePaths.count == 1,
              let scopePath = scopePaths.first else {
            throw CatalogStoreError.photoStackMembersMustShareFolder
        }

        let existingStackIDs = try photoStackIDs(
            containingAny: photoIDs
        )
        if !allowsExistingStack, !existingStackIDs.isEmpty {
            throw CatalogStoreError.photoStackAlreadyContainsSelection
        }
        guard existingStackIDs.count <= 1 else {
            throw CatalogStoreError.photoStackCannotMergeMultipleStacks
        }

        let now = Date()
        let stackID: UUID
        let memberIDs: [PhotoAsset.ID]
        if let existingStackID = existingStackIDs.first {
            guard let existing = try loadPhotoStack(
                id: existingStackID
            ) else {
                throw CatalogStoreError.photoStackNotFound
            }
            guard existing.scopePath == scopePath else {
                throw CatalogStoreError.photoStackMembersMustShareFolder
            }
            stackID = existingStackID
            memberIDs = uniquePhotoIDs(
                photoIDs + existing.memberIDs
            )
            let update = try prepare(
                """
                UPDATE catalog_photo_stacks
                SET collapsed = ?, updated_at = ?
                WHERE id = ?
                """
            )
            bind(collapsed ? 1 : 0, at: 1, in: update)
            bind(now.timeIntervalSince1970, at: 2, in: update)
            bind(stackID.uuidString, at: 3, in: update)
            try stepDone(update)
            sqlite3_finalize(update)
        } else {
            stackID = UUID()
            memberIDs = photoIDs
            let insert = try prepare(
                """
                INSERT INTO catalog_photo_stacks(
                    id, scope_path, collapsed, created_at, updated_at
                ) VALUES(?, ?, ?, ?, ?)
                """
            )
            bind(stackID.uuidString, at: 1, in: insert)
            bind(scopePath, at: 2, in: insert)
            bind(collapsed ? 1 : 0, at: 3, in: insert)
            bind(now.timeIntervalSince1970, at: 4, in: insert)
            bind(now.timeIntervalSince1970, at: 5, in: insert)
            try stepDone(insert)
            sqlite3_finalize(insert)
        }

        try replacePhotoStackMembers(
            stackID: stackID,
            photoIDs: memberIDs
        )
        guard let result = try loadPhotoStack(id: stackID) else {
            throw CatalogStoreError.photoStackNotFound
        }
        return result
    }

    private func replacePhotoStackMembers(
        stackID: UUID,
        photoIDs: [PhotoAsset.ID]
    ) throws {
        let delete = try prepare(
            """
            DELETE FROM catalog_photo_stack_members
            WHERE stack_id = ?
            """
        )
        bind(stackID.uuidString, at: 1, in: delete)
        try stepDone(delete)
        sqlite3_finalize(delete)

        let insert = try prepare(
            """
            INSERT INTO catalog_photo_stack_members(
                stack_id, photo_id, position
            ) VALUES(?, ?, ?)
            """
        )
        defer { sqlite3_finalize(insert) }
        for (offset, photoID) in photoIDs.enumerated() {
            sqlite3_reset(insert)
            sqlite3_clear_bindings(insert)
            bind(stackID.uuidString, at: 1, in: insert)
            bind(photoID, at: 2, in: insert)
            bind(offset + 1, at: 3, in: insert)
            try stepDone(insert)
        }
    }

    private func normalizeOrRemovePhotoStack(
        id: UUID
    ) throws {
        guard let stack = try loadPhotoStack(id: id) else {
            return
        }
        guard stack.memberIDs.count >= 2 else {
            let delete = try prepare(
                "DELETE FROM catalog_photo_stacks WHERE id = ?"
            )
            bind(id.uuidString, at: 1, in: delete)
            try stepDone(delete)
            sqlite3_finalize(delete)
            return
        }
        try replacePhotoStackMembers(
            stackID: id,
            photoIDs: stack.memberIDs
        )
        try touchPhotoStack(id: id)
    }

    private func touchPhotoStack(id: UUID) throws {
        let statement = try prepare(
            """
            UPDATE catalog_photo_stacks
            SET updated_at = ?
            WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(Date().timeIntervalSince1970, at: 1, in: statement)
        bind(id.uuidString, at: 2, in: statement)
        try stepDone(statement)
    }

    private func replaceStackMemberPhotoID(
        previousID: PhotoAsset.ID,
        replacementID: PhotoAsset.ID
    ) throws {
        guard let stackID = try photoStackID(
            containing: previousID
        ) else {
            return
        }
        let statement = try prepare(
            """
            UPDATE catalog_photo_stack_members
            SET photo_id = ?
            WHERE stack_id = ? AND photo_id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(replacementID, at: 1, in: statement)
        bind(stackID.uuidString, at: 2, in: statement)
        bind(previousID, at: 3, in: statement)
        try stepDone(statement)
        try touchPhotoStack(id: stackID)
    }

    private func removeOrphanedPhotoStacks() throws {
        try execute(
            """
            DELETE FROM catalog_photo_stacks
            WHERE (
                SELECT COUNT(*)
                FROM catalog_photo_stack_members AS members
                WHERE members.stack_id = catalog_photo_stacks.id
            ) < 2
            """
        )
    }

    // MARK: - Catalog-wide keyword management

    private struct KeywordStateRecord {
        var id: String
        var state: PhotoUserState
        var isMissing: Bool
    }

    private struct ValidatedKeywordChange {
        var sourcePath: String
        var sourceSegments: [String]
        var destinationPath: String?
        var destinationSegments: [String]
        var deletesBranch: Bool

        func transformedPath(_ candidate: String) throws -> String? {
            guard PhotoUserState.keywordPath(
                candidate,
                isEqualToOrDescendantOf: sourcePath
            ) else {
                return PhotoUserState.normalizedKeywordPath(candidate)
            }
            guard !deletesBranch else { return nil }
            let candidateSegments = PhotoUserState.keywordSegments(
                in: candidate
            )
            let transformed = destinationSegments + Array(
                candidateSegments.dropFirst(sourceSegments.count)
            )
            guard transformed.count <= 16 else {
                throw CatalogStoreError.keywordHierarchyTooDeep
            }
            return transformed.joined(
                separator: PhotoUserState.keywordPathSeparator
            )
        }
    }

    private struct KeywordMutationPlan {
        var preview: CatalogKeywordChangePreview
        var updatedStates: [String: PhotoUserState]
        var updatedSmartCollections: [SavedSmartCollection]
        var allSmartCollections: [SavedSmartCollection]
        var definitionKeysToDelete: [String]
        var definitionsToUpsert: [CatalogKeywordDefinition]
    }

    private func keywordMutationPlan(
        for change: CatalogKeywordChange
    ) throws -> KeywordMutationPlan {
        let validated = try validateKeywordChange(change)
        let records = try keywordStateRecords(
            matching: validated.sourcePath
        )
        var updatedStates: [String: PhotoUserState] = [:]
        var affectedAssignments = 0
        var affectedPaths: Set<String> = []
        var missingPhotoCount = 0
        var mergedAssignments = 0

        for record in records {
            var mapped: [String] = []
            mapped.reserveCapacity(record.state.keywords.count)
            var matchedAssignments = 0
            for keyword in record.state.keywords {
                if PhotoUserState.keywordPath(
                    keyword,
                    isEqualToOrDescendantOf: validated.sourcePath
                ) {
                    matchedAssignments += 1
                    affectedPaths.insert(
                        PhotoUserState.foldedKeyword(keyword)
                    )
                }
                if let transformed = try validated.transformedPath(
                    keyword
                ) {
                    mapped.append(transformed)
                }
            }
            let normalized = PhotoUserState.normalizedKeywords(mapped)
            guard normalized != record.state.keywords else { continue }
            var state = record.state
            state.keywords = normalized
            updatedStates[record.id] = state
            affectedAssignments += matchedAssignments
            if record.isMissing {
                missingPhotoCount += 1
            }
            if !validated.deletesBranch {
                mergedAssignments += max(
                    0,
                    mapped.count - normalized.count
                )
            }
        }

        let existingCollections = try loadSavedSmartCollections()
        var allCollections: [SavedSmartCollection] = []
        var updatedCollections: [SavedSmartCollection] = []
        allCollections.reserveCapacity(existingCollections.count)
        for existing in existingCollections {
            var collection = existing
            if let keyword = collection.filter.keyword,
               PhotoUserState.keywordPath(
                   keyword,
                   isEqualToOrDescendantOf: validated.sourcePath
               ) {
                collection.filter.keyword = try validated.transformedPath(
                    keyword
                )
            }
            allCollections.append(collection)
            if collection != existing {
                updatedCollections.append(collection)
            }
        }

        let definitions = try loadKeywordDefinitions()
        let affectedDefinitions = definitions.filter {
            PhotoUserState.keywordPath(
                $0.value.path,
                isEqualToOrDescendantOf: validated.sourcePath
            )
        }
        var finalDefinitions = definitions
        for key in affectedDefinitions.keys {
            finalDefinitions.removeValue(forKey: key)
        }
        var transformedDefinitionKeys: Set<String> = []
        for definition in affectedDefinitions.values {
            guard let transformedPath =
                    try validated.transformedPath(
                        definition.path
                    ) else {
                continue
            }
            let transformed = CatalogKeywordDefinition(
                path: transformedPath,
                synonyms: definition.synonyms,
                includeOnExport: definition.includeOnExport,
                exportSynonyms: definition.exportSynonyms,
                exportContainingKeywords:
                    definition.exportContainingKeywords
            )
            let key = PhotoUserState.foldedKeyword(
                transformed.path
            )
            transformedDefinitionKeys.insert(key)
            if let existing = finalDefinitions[key] {
                finalDefinitions[key] = mergeKeywordDefinitions(
                    existing,
                    transformed,
                    path: existing.path
                )
            } else {
                finalDefinitions[key] = transformed
            }
        }
        let definitionsToUpsert = transformedDefinitionKeys
            .compactMap { finalDefinitions[$0] }
            .sorted {
                $0.path.localizedCaseInsensitiveCompare($1.path)
                    == .orderedAscending
            }

        let preview = CatalogKeywordChangePreview(
            sourcePath: validated.sourcePath,
            destinationPath: validated.destinationPath,
            affectedPhotoCount: updatedStates.count,
            affectedKeywordAssignmentCount: affectedAssignments,
            affectedKeywordPathCount: affectedPaths.count,
            missingPhotoCount: missingPhotoCount,
            mergedAssignmentCount: mergedAssignments,
            affectedSmartCollectionCount: updatedCollections.count,
            affectedDefinitionCount: affectedDefinitions.count
        )
        return KeywordMutationPlan(
            preview: preview,
            updatedStates: updatedStates,
            updatedSmartCollections: updatedCollections,
            allSmartCollections: allCollections,
            definitionKeysToDelete:
                affectedDefinitions.keys.sorted(),
            definitionsToUpsert: definitionsToUpsert
        )
    }

    private func validateKeywordChange(
        _ change: CatalogKeywordChange
    ) throws -> ValidatedKeywordChange {
        let sourceSegments = managementKeywordSegments(
            in: change.sourcePath
        )
        guard !sourceSegments.isEmpty,
              sourceSegments.allSatisfy({ $0.count <= 64 }) else {
            throw CatalogStoreError.invalidKeywordPath
        }
        guard sourceSegments.count <= 16 else {
            throw CatalogStoreError.keywordHierarchyTooDeep
        }
        let sourcePath = sourceSegments.joined(
            separator: PhotoUserState.keywordPathSeparator
        )
        let destinationPath: String?
        let deletesBranch: Bool

        switch change {
        case let .rename(_, newName):
            let nameSegments = managementKeywordSegments(in: newName)
            guard nameSegments.count == 1,
                  nameSegments[0].count <= 64 else {
                throw CatalogStoreError.invalidKeywordName
            }
            destinationPath = (
                Array(sourceSegments.dropLast()) + nameSegments
            ).joined(separator: PhotoUserState.keywordPathSeparator)
            deletesBranch = false
        case let .moveOrMerge(_, requestedDestination):
            let requestedSegments = managementKeywordSegments(
                in: requestedDestination
            )
            guard !requestedSegments.isEmpty,
                  requestedSegments.allSatisfy({ $0.count <= 64 }) else {
                throw CatalogStoreError.invalidKeywordPath
            }
            guard requestedSegments.count <= 16 else {
                throw CatalogStoreError.keywordHierarchyTooDeep
            }
            destinationPath = requestedSegments.joined(
                separator: PhotoUserState.keywordPathSeparator
            )
            deletesBranch = false
        case .delete:
            destinationPath = nil
            deletesBranch = true
        }

        let destinationSegments = destinationPath.map {
            PhotoUserState.keywordSegments(in: $0)
        } ?? []
        if let destinationPath {
            let sourceFolded = PhotoUserState.foldedKeyword(sourcePath)
            let destinationFolded = PhotoUserState.foldedKeyword(
                destinationPath
            )
            if destinationFolded.hasPrefix(
                sourceFolded + PhotoUserState.keywordPathSeparator
            ) {
                throw CatalogStoreError.keywordDestinationInsideSource
            }
            if destinationPath == sourcePath {
                throw CatalogStoreError.keywordChangeNoEffect
            }
        }
        return ValidatedKeywordChange(
            sourcePath: sourcePath,
            sourceSegments: sourceSegments,
            destinationPath: destinationPath,
            destinationSegments: destinationSegments,
            deletesBranch: deletesBranch
        )
    }

    private func managementKeywordSegments(
        in value: String
    ) -> [String] {
        value
            .replacingOccurrences(
                of: "›",
                with: PhotoUserState.keywordPathSeparator
            )
            .replacingOccurrences(
                of: ">",
                with: PhotoUserState.keywordPathSeparator
            )
            .replacingOccurrences(
                of: "＞",
                with: PhotoUserState.keywordPathSeparator
            )
            .components(
                separatedBy: PhotoUserState.keywordPathSeparator
            )
            .compactMap { rawSegment in
                let collapsed = rawSegment
                    .split(whereSeparator: \.isWhitespace)
                    .joined(separator: " ")
                    .precomposedStringWithCanonicalMapping
                return collapsed.isEmpty ? nil : collapsed
            }
    }

    private func keywordStateRecords(
        matching sourcePath: String
    ) throws -> [KeywordStateRecord] {
        let sourceFolded = PhotoUserState.foldedKeyword(sourcePath)
        let statement = try prepare(
            """
            SELECT photos.id, photos.state_json, photos.missing
            FROM catalog_photos AS photos
            WHERE EXISTS (
                SELECT 1
                FROM catalog_photo_keywords AS keywords
                WHERE keywords.photo_id = photos.id
                  AND (
                    keywords.keyword_folded = ?
                    OR substr(
                        keywords.keyword_folded,
                        1,
                        length(?) + 1
                    ) = ? || '|'
                  )
            )
            ORDER BY photos.id ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(sourceFolded, at: 1, in: statement)
        bind(sourceFolded, at: 2, in: statement)
        bind(sourceFolded, at: 3, in: statement)

        var records: [KeywordStateRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(at: 0, in: statement),
                  let encoded = data(at: 1, in: statement) else {
                throw CatalogStoreError.queryFailed(
                    "A matching catalog record contains unreadable state."
                )
            }
            let state: PhotoUserState
            do {
                state = try JSONDecoder().decode(
                    PhotoUserState.self,
                    from: encoded
                )
            } catch {
                throw CatalogStoreError.queryFailed(
                    "A matching catalog record contains unreadable state."
                )
            }
            records.append(KeywordStateRecord(
                id: id,
                state: state,
                isMissing: sqlite3_column_int(statement, 2) != 0
            ))
        }
        try ensureNoStepError(statement)
        return records
    }

    private func loadCollectionSets() throws
        -> [CatalogCollectionSet] {
        let statement = try prepare(
            """
            SELECT id, name, parent_set_id, created_at
            FROM catalog_collection_sets
            ORDER BY name COLLATE NOCASE ASC, created_at ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        var result: [CatalogCollectionSet] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = text(at: 0, in: statement),
                  let id = UUID(uuidString: idText),
                  let name = text(at: 1, in: statement) else {
                throw CatalogStoreError.queryFailed(
                    "A collection set contains unreadable data."
                )
            }
            result.append(CatalogCollectionSet(
                id: id,
                name: name,
                parentSetID: text(at: 2, in: statement).flatMap(
                    UUID.init(uuidString:)
                ),
                createdAt: date(at: 3, in: statement)
                    ?? .distantPast
            ))
        }
        try ensureNoStepError(statement)
        return result
    }

    private func loadPhotoCollections() throws
        -> [CatalogPhotoCollection] {
        let statement = try prepare(
            """
            SELECT
                collections.id,
                collections.name,
                collections.parent_set_id,
                collections.created_at,
                collections.is_target,
                COUNT(members.photo_id)
            FROM catalog_collections AS collections
            LEFT JOIN catalog_collection_members AS members
                ON members.collection_id = collections.id
            GROUP BY collections.id
            ORDER BY
                collections.name COLLATE NOCASE ASC,
                collections.created_at ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        var result: [CatalogPhotoCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = text(at: 0, in: statement),
                  let id = UUID(uuidString: idText),
                  let name = text(at: 1, in: statement) else {
                throw CatalogStoreError.queryFailed(
                    "A collection contains unreadable data."
                )
            }
            result.append(CatalogPhotoCollection(
                id: id,
                name: name,
                parentSetID: text(at: 2, in: statement).flatMap(
                    UUID.init(uuidString:)
                ),
                createdAt: date(at: 3, in: statement)
                    ?? .distantPast,
                isTarget:
                    sqlite3_column_int(statement, 4) != 0,
                photoCount: Int(
                    sqlite3_column_int64(statement, 5)
                )
            ))
        }
        try ensureNoStepError(statement)
        return result
    }

    private func loadPhotoCollectionPhotoIDs(
        collectionID: UUID
    ) throws -> [String] {
        let statement = try prepare(
            """
            SELECT photo_id
            FROM catalog_collection_members
            WHERE collection_id = ?
            ORDER BY position ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(collectionID.uuidString, at: 1, in: statement)
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = text(at: 0, in: statement) {
                result.append(id)
            }
        }
        try ensureNoStepError(statement)
        return result
    }

    private func photoCollectionExists(_ id: UUID) throws -> Bool {
        let statement = try prepare(
            "SELECT 1 FROM catalog_collections WHERE id = ? LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, in: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return true
        }
        try ensureNoStepError(statement)
        return false
    }

    private func validateCollectionSetExists(
        _ id: UUID?
    ) throws {
        guard let id else { return }
        let statement = try prepare(
            "SELECT 1 FROM catalog_collection_sets WHERE id = ? LIMIT 1"
        )
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, in: statement)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW {
            return
        }
        try ensureNoStepError(statement)
        throw CatalogStoreError.collectionSetNotFound
    }

    private func validateCollectionSetParent(
        id: UUID,
        parentSetID: UUID?
    ) throws {
        guard let parentSetID else { return }
        if parentSetID == id {
            throw CatalogStoreError
                .collectionSetDestinationInsideSource
        }
        let sets = try loadCollectionSets()
        let byID = Dictionary(
            uniqueKeysWithValues: sets.map { ($0.id, $0) }
        )
        guard byID[parentSetID] != nil else {
            throw CatalogStoreError.collectionSetNotFound
        }
        var current: UUID? = parentSetID
        var visited: Set<UUID> = [id]
        var depth = 1
        while let currentID = current {
            guard visited.insert(currentID).inserted else {
                throw CatalogStoreError
                    .collectionSetDestinationInsideSource
            }
            depth += 1
            if depth > 16 {
                throw CatalogStoreError
                    .collectionSetHierarchyTooDeep
            }
            current = byID[currentID]?.parentSetID
        }
        let children = Dictionary(
            grouping: sets,
            by: \.parentSetID
        )
        func subtreeDepth(
            _ currentID: UUID,
            visited: Set<UUID>
        ) -> Int {
            guard !visited.contains(currentID) else {
                return 1
            }
            var nextVisited = visited
            nextVisited.insert(currentID)
            let childDepth = (
                children[Optional(currentID)] ?? []
            ).map {
                subtreeDepth(
                    $0.id,
                    visited: nextVisited
                )
            }.max() ?? 0
            return 1 + childDepth
        }
        if depth + subtreeDepth(id, visited: []) - 1 > 16 {
            throw CatalogStoreError
                .collectionSetHierarchyTooDeep
        }
    }

    private func collectionSetDescendantIDs(
        including id: UUID
    ) throws -> [UUID] {
        let sets = try loadCollectionSets()
        guard sets.contains(where: { $0.id == id }) else {
            return []
        }
        let children = Dictionary(
            grouping: sets,
            by: \.parentSetID
        )
        var result: [UUID] = []
        var pending: [UUID] = [id]
        var visited: Set<UUID> = []
        while let current = pending.popLast() {
            guard visited.insert(current).inserted else {
                continue
            }
            result.append(current)
            pending.append(
                contentsOf:
                    (children[current] ?? []).map(\.id)
            )
        }
        return result
    }

    private func loadSavedSmartCollections() throws
        -> [SavedSmartCollection] {
        let statement = try prepare(
            """
            SELECT id, name, filter_json, created_at, parent_set_id
            FROM catalog_smart_collections
            ORDER BY created_at ASC, name COLLATE NOCASE ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        var result: [SavedSmartCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idText = text(at: 0, in: statement),
                  let id = UUID(uuidString: idText),
                  let name = text(at: 1, in: statement),
                  let filterData = data(at: 2, in: statement) else {
                throw CatalogStoreError.queryFailed(
                    "A saved smart collection contains unreadable data."
                )
            }
            let filter: FilterState
            do {
                filter = try JSONDecoder().decode(
                    FilterState.self,
                    from: filterData
                )
            } catch {
                throw CatalogStoreError.queryFailed(
                    "A saved smart collection contains unreadable data."
                )
            }
            result.append(SavedSmartCollection(
                id: id,
                name: name,
                filter: filter,
                createdAt: date(at: 3, in: statement) ?? .distantPast,
                parentSetID: text(at: 4, in: statement).flatMap(
                    UUID.init(uuidString:)
                )
            ))
        }
        try ensureNoStepError(statement)
        return result
    }

    private func loadKeywordDefinitions() throws
        -> [String: CatalogKeywordDefinition] {
        let statement = try prepare(
            """
            SELECT
                keyword_folded, keyword, synonyms_json,
                include_on_export, export_synonyms,
                export_containing
            FROM catalog_keyword_definitions
            ORDER BY keyword COLLATE NOCASE ASC
            """
        )
        defer { sqlite3_finalize(statement) }
        var result: [String: CatalogKeywordDefinition] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let folded = text(at: 0, in: statement),
                  let keyword = text(at: 1, in: statement),
                  let synonymsData = data(at: 2, in: statement) else {
                throw CatalogStoreError.queryFailed(
                    "A keyword definition contains unreadable data."
                )
            }
            let synonyms: [String]
            do {
                synonyms = try JSONDecoder().decode(
                    [String].self,
                    from: synonymsData
                )
            } catch {
                throw CatalogStoreError.queryFailed(
                    "A keyword definition contains unreadable synonyms."
                )
            }
            result[folded] = CatalogKeywordDefinition(
                path: keyword,
                synonyms: synonyms,
                includeOnExport:
                    sqlite3_column_int(statement, 3) != 0,
                exportSynonyms:
                    sqlite3_column_int(statement, 4) != 0,
                exportContainingKeywords:
                    sqlite3_column_int(statement, 5) != 0
            )
        }
        try ensureNoStepError(statement)
        return result
    }

    private func upsertKeywordDefinition(
        _ definition: CatalogKeywordDefinition
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO catalog_keyword_definitions(
                keyword_folded, keyword, synonyms_json,
                include_on_export, export_synonyms,
                export_containing
            ) VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(keyword_folded) DO UPDATE SET
                keyword = excluded.keyword,
                synonyms_json = excluded.synonyms_json,
                include_on_export = excluded.include_on_export,
                export_synonyms = excluded.export_synonyms,
                export_containing = excluded.export_containing
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(
            PhotoUserState.foldedKeyword(definition.path),
            at: 1,
            in: statement
        )
        bind(definition.path, at: 2, in: statement)
        bind(try encode(definition.synonyms), at: 3, in: statement)
        bind(definition.includeOnExport ? 1 : 0, at: 4, in: statement)
        bind(definition.exportSynonyms ? 1 : 0, at: 5, in: statement)
        bind(
            definition.exportContainingKeywords ? 1 : 0,
            at: 6,
            in: statement
        )
        try stepDone(statement)
    }

    private func mergeKeywordDefinitions(
        _ existing: CatalogKeywordDefinition,
        _ incoming: CatalogKeywordDefinition,
        path: String
    ) -> CatalogKeywordDefinition {
        CatalogKeywordDefinition(
            path: path,
            synonyms: existing.synonyms + incoming.synonyms,
            includeOnExport:
                existing.includeOnExport
                    && incoming.includeOnExport,
            exportSynonyms:
                existing.exportSynonyms
                    && incoming.exportSynonyms,
            exportContainingKeywords:
                existing.exportContainingKeywords
                    || incoming.exportContainingKeywords
        )
    }

    // MARK: - Queries

    private func count(for collection: CatalogSmartCollection) throws -> Int {
        let duplicateKey = Self.duplicateKeySQL()
        let condition: String
        var threshold: Double?
        switch collection {
        case .allPhotos:
            condition = "missing = 0"
        case .recentlyAdded:
            condition = "missing = 0 AND indexed_at >= ?"
            threshold = Date()
                .addingTimeInterval(-30 * 24 * 60 * 60)
                .timeIntervalSince1970
        case .quickCollection:
            condition = """
                id IN (
                    SELECT photo_id
                    FROM catalog_quick_collection
                )
                """
        case .edited:
            condition = "missing = 0 AND edited = 1"
        case .fiveStars:
            condition = "missing = 0 AND rating >= 5"
        case .picked:
            condition = "missing = 0 AND pick_status = 1"
        case .rejected:
            condition = "missing = 0 AND pick_status = -1"
        case .withKeywords:
            condition = "missing = 0 AND keyword_count > 0"
        case .withLocation:
            condition = """
                missing = 0
                AND latitude IS NOT NULL
                AND longitude IS NOT NULL
                """
        case .withoutLocation:
            condition = """
                missing = 0
                AND (latitude IS NULL OR longitude IS NULL)
                """
        case .assistedCulling:
            condition = "missing = 0"
        case .exactDuplicates:
            condition = """
                missing = 0
                AND \(duplicateKey) IN (
                    SELECT duplicate_key
                    FROM (
                        SELECT
                            \(duplicateKey) AS duplicate_key
                        FROM catalog_photos
                        WHERE missing = 0
                    )
                    WHERE duplicate_key IS NOT NULL
                    GROUP BY duplicate_key
                    HAVING COUNT(*) > 1
                )
                """
        case .missingFiles:
            condition = "missing = 1"
        }
        let statement = try prepare(
            "SELECT COUNT(*) FROM catalog_photos WHERE \(condition)"
        )
        defer { sqlite3_finalize(statement) }
        if let threshold {
            bind(threshold, at: 1, in: statement)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            try ensureNoStepError(statement)
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func scalarInt64(_ sql: String) throws -> Int64 {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            try ensureNoStepError(statement)
            return 0
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            try ensureNoStepError(statement)
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func databaseByteCount() -> Int64 {
        guard databaseURL.path != ":memory:",
              let values = try? databaseURL.resourceValues(
                  forKeys: [.fileSizeKey]
              ) else {
            return 0
        }
        return Int64(values.fileSize ?? 0)
    }

    private func foldedKeyword(_ keyword: String) -> String {
        keyword.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    // MARK: - SQLite helpers

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func requireDatabase() throws -> OpaquePointer {
        guard let database else {
            throw CatalogStoreError.unavailable(
                startupWarning ?? "SQLite did not open."
            )
        }
        return database
    }

    private func execute(_ sql: String) throws {
        let database = try requireDatabase()
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(
            database,
            sql,
            nil,
            nil,
            &errorMessage
        )
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SQLiteFailure(code: result, message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        let database = try requireDatabase()
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        )
        guard result == SQLITE_OK, let statement else {
            throw SQLiteFailure(
                code: result,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            let database = try requireDatabase()
            throw SQLiteFailure(
                code: result,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
    }

    private func ensureNoStepError(_ statement: OpaquePointer) throws {
        let result = sqlite3_errcode(try requireDatabase())
        guard result == SQLITE_OK || result == SQLITE_DONE else {
            throw SQLiteFailure(
                code: result,
                message: String(cString: sqlite3_errmsg(try requireDatabase()))
            )
        }
    }

    private func bind(
        _ value: String?,
        at index: Int32,
        in statement: OpaquePointer
    ) {
        guard let value else {
            bindNull(at: index, in: statement)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func bind(
        _ value: Data,
        at index: Int32,
        in statement: OpaquePointer
    ) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                index,
                bytes.baseAddress,
                Int32(value.count),
                transient
            )
        }
    }

    private func bind(
        _ value: Int,
        at index: Int32,
        in statement: OpaquePointer
    ) {
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    }

    private func bind(
        _ value: Int64,
        at index: Int32,
        in statement: OpaquePointer
    ) {
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    }

    private func bind(
        _ value: Double,
        at index: Int32,
        in statement: OpaquePointer
    ) {
        sqlite3_bind_double(statement, index, value)
    }

    private func bind(
        _ value: Double?,
        at index: Int32,
        in statement: OpaquePointer
    ) {
        guard let value else {
            bindNull(at: index, in: statement)
            return
        }
        bind(value, at: index, in: statement)
    }

    private func bind(
        _ value: Date?,
        at index: Int32,
        in statement: OpaquePointer
    ) {
        guard let value else {
            bindNull(at: index, in: statement)
            return
        }
        bind(value.timeIntervalSince1970, at: index, in: statement)
    }

    private func bindNull(
        at index: Int32,
        in statement: OpaquePointer
    ) {
        sqlite3_bind_null(statement, index)
    }

    private func text(
        at index: Int32,
        in statement: OpaquePointer
    ) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func data(
        at index: Int32,
        in statement: OpaquePointer
    ) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        guard count > 0,
              let bytes = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        return Data(bytes: bytes, count: count)
    }

    private func date(
        at index: Int32,
        in statement: OpaquePointer
    ) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Date(
            timeIntervalSince1970: sqlite3_column_double(statement, index)
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else {
            throw CatalogStoreError.encodingFailed
        }
        return data
    }
}

private struct SQLiteFailure: LocalizedError {
    var code: Int32
    var message: String

    var errorDescription: String? {
        "SQLite \(code): \(message)"
    }
}
