import XCTest
import AppKit
import ImageIO
import SQLite3
import Vision
@testable import RAWDesk

final class PeopleCatalogTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-people-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeAsset(
        id: String,
        url: URL,
        modificationDate: Date? = Date(
            timeIntervalSince1970: 1_700_000_000
        )
    ) -> PhotoAsset {
        PhotoAsset(
            id: id,
            url: url,
            path: url.path,
            filename: url.lastPathComponent,
            fileExtension: "jpg",
            fileSize: 4,
            creationDate: modificationDate,
            modificationDate: modificationDate,
            format: .jpeg
        )
    }

    private func detection(
        x: Double,
        feature: UInt8
    ) -> PeopleFaceDetection {
        PeopleFaceDetection(
            boundingBox: CGRect(
                x: x,
                y: 0.25,
                width: 0.24,
                height: 0.42
            ),
            confidence: 0.92,
            captureQuality: 0.81,
            featurePrintData: Data([feature])
        )
    }

    func testSchemaEightMigratesPeopleTablesToCurrentSchema() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var initial: CatalogStore? = CatalogStore(
            directory: directory
        )
        let databaseURL = try XCTUnwrap(initial?.databaseURL)
        initial = nil

        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open(databaseURL.path, &database),
            SQLITE_OK
        )
        guard let database else {
            return XCTFail("Could not open catalog")
        }
        XCTAssertEqual(
            sqlite3_exec(
                database,
                """
                DROP TABLE catalog_faces;
                DROP TABLE catalog_face_analysis;
                DROP TABLE catalog_people;
                PRAGMA user_version = 8;
                """,
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        sqlite3_close(database)

        let migrated = CatalogStore(directory: directory)
        XCTAssertTrue(try migrated.integrityCheck())
        XCTAssertEqual(try migrated.catalogPeople(), [])
        XCTAssertEqual(try migrated.catalogFaces(), [])

        var reopened: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open(databaseURL.path, &reopened),
            SQLITE_OK
        )
        guard let reopened else {
            return XCTFail("Could not reopen catalog")
        }
        defer { sqlite3_close(reopened) }
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                reopened,
                "PRAGMA user_version",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 12)
        sqlite3_finalize(statement)
    }

    func testZeroFaceAnalysisIsCachedAndPersists() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("empty.jpg")
        try Data([1, 2, 3, 4]).write(to: photoURL)
        let asset = makeAsset(id: "empty", url: photoURL)
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [asset],
            rootURL: directory,
            recursive: false
        )

        XCTAssertTrue(
            try store.recordPeopleFaceAnalysis(
                [],
                id: asset.id,
                engineVersion: PeopleAnalyzer.currentEngineVersion,
                expectedFileSize: asset.fileSize,
                expectedModificationDate: asset.modificationDate
            )
        )
        let candidate = try XCTUnwrap(
            store.peopleAnalysisCandidates(
                engineVersion:
                    PeopleAnalyzer.currentEngineVersion
            ).first
        )
        XCTAssertEqual(candidate.cachedFaces, [])

        let reopened = CatalogStore(directory: directory)
        let persisted = try XCTUnwrap(
            reopened.peopleAnalysisCandidates(
                engineVersion:
                    PeopleAnalyzer.currentEngineVersion
            ).first
        )
        XCTAssertEqual(persisted.cachedFaces, [])
    }

    func testReviewedIdentitySurvivesOverlappingReanalysis()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("portrait.jpg")
        try Data([1, 2, 3, 4]).write(to: photoURL)
        let asset = makeAsset(id: "portrait", url: photoURL)
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [asset],
            rootURL: directory,
            recursive: false
        )
        XCTAssertTrue(
            try store.recordPeopleFaceAnalysis(
                [detection(x: 0.2, feature: 1)],
                id: asset.id,
                engineVersion: 1,
                expectedFileSize: asset.fileSize,
                expectedModificationDate: asset.modificationDate
            )
        )
        let original = try XCTUnwrap(
            store.catalogFaces().first
        )
        let person = try store.createPerson(
            name: "  Ada   Lovelace ",
            faceIDs: [original.id]
        )
        XCTAssertEqual(person.name, "Ada Lovelace")

        XCTAssertTrue(
            try store.recordPeopleFaceAnalysis(
                [detection(x: 0.215, feature: 2)],
                id: asset.id,
                engineVersion: 1,
                expectedFileSize: asset.fileSize,
                expectedModificationDate: asset.modificationDate
            )
        )
        let refreshed = try XCTUnwrap(
            store.catalogFaces().first
        )
        XCTAssertEqual(refreshed.id, original.id)
        XCTAssertEqual(refreshed.personID, person.id)
        XCTAssertEqual(refreshed.featurePrintData, Data([2]))
    }

    func testPeopleReviewActionsArePersistentAndReversible()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("group.jpg")
        try Data([1, 2, 3, 4]).write(to: photoURL)
        let asset = makeAsset(id: "group", url: photoURL)
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [asset],
            rootURL: directory,
            recursive: false
        )
        XCTAssertTrue(
            try store.recordPeopleFaceAnalysis(
                [
                    detection(x: 0.1, feature: 1),
                    detection(x: 0.6, feature: 2),
                ],
                id: asset.id,
                engineVersion: 1,
                expectedFileSize: asset.fileSize,
                expectedModificationDate: asset.modificationDate
            )
        )
        let faces = try store.catalogFaces()
        XCTAssertEqual(faces.count, 2)
        let first = try XCTUnwrap(faces.first)
        let second = try XCTUnwrap(faces.last)
        let ada = try store.createPerson(
            name: "Ada",
            faceIDs: [first.id]
        )
        let grace = try store.createPerson(
            name: "Grace",
            faceIDs: [second.id]
        )

        try store.renamePerson(id: ada.id, name: "Ada L.")
        try store.mergePeople(
            sourceID: grace.id,
            destinationID: ada.id
        )
        XCTAssertEqual(try store.catalogPeople().count, 1)
        XCTAssertTrue(
            try store.catalogFaces().allSatisfy {
                $0.personID == ada.id
            }
        )

        try store.unassignFaces([second.id])
        XCTAssertNil(
            try store.catalogFaces().first {
                $0.id == second.id
            }?.personID
        )
        try store.ignoreFaces([second.id])
        XCTAssertEqual(
            try store.catalogFaces().first {
                $0.id == second.id
            }?.disposition,
            .ignored
        )
        try store.restoreIgnoredFaces([second.id])
        XCTAssertEqual(
            try store.catalogFaces().first {
                $0.id == second.id
            }?.disposition,
            .candidate
        )

        try store.deletePerson(id: ada.id)
        XCTAssertEqual(try store.catalogPeople(), [])
        XCTAssertTrue(
            try store.catalogFaces().allSatisfy {
                $0.personID == nil
            }
        )
        XCTAssertTrue(try store.integrityCheck())
    }
}

final class PeopleAnalyzerTests: XCTestCase {
    private actor InvocationCounter {
        private(set) var value = 0

        func increment() {
            value += 1
        }
    }

    private actor InvocationRecorder {
        private(set) var ids: [PhotoAsset.ID] = []

        func record(_ id: PhotoAsset.ID) {
            ids.append(id)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-people-analyzer-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeFeaturePrint(
        gray: CGFloat
    ) throws -> Data {
        let width = 40
        let height = 40
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(
            NSColor(
                calibratedWhite: gray,
                alpha: 1
            ).cgColor
        )
        context.fill(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        let image = try XCTUnwrap(context.makeImage())
        let request = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(
            cgImage: image,
            orientation: .up
        ).perform([request])
        let observation = try XCTUnwrap(request.results?.first)
        return try NSKeyedArchiver.archivedData(
            withRootObject: observation,
            requiringSecureCoding: true
        )
    }

    func testAnalyzerUsesGuardedNegativeCacheAndForceReruns()
        async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("plain.jpg")
        try Data([1, 2, 3, 4]).write(to: photoURL)
        let facts = try photoURL.resourceValues(
            forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
            ]
        )
        let asset = PhotoAsset(
            id: "plain",
            url: photoURL,
            path: photoURL.path,
            filename: photoURL.lastPathComponent,
            fileExtension: "jpg",
            fileSize: Int64(try XCTUnwrap(facts.fileSize)),
            creationDate: nil,
            modificationDate: facts.contentModificationDate,
            format: .jpeg
        )
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [asset],
            rootURL: directory,
            recursive: false
        )
        let counter = InvocationCounter()
        let analyzer = PeopleAnalyzer(
            catalogStore: store
        ) { _ in
            await counter.increment()
            return []
        }

        let first = try await analyzer.scan()
        XCTAssertEqual(first.analyzedCount, 1)
        XCTAssertEqual(first.cachedCount, 0)

        let second = try await analyzer.scan()
        XCTAssertEqual(second.analyzedCount, 0)
        XCTAssertEqual(second.cachedCount, 1)

        let forced = try await analyzer.scan(
            forceReanalysis: true
        )
        XCTAssertEqual(forced.analyzedCount, 1)
        let invocationCount = await counter.value
        XCTAssertEqual(invocationCount, 2)
    }

    func testScopedScanOnlyAnalyzesRequestedImportedPhotos()
        async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent(
            "first.jpg"
        )
        let secondURL = directory.appendingPathComponent(
            "second.jpg"
        )
        try Data([1, 2, 3, 4]).write(to: firstURL)
        try Data([5, 6, 7, 8]).write(to: secondURL)

        func asset(
            id: String,
            url: URL
        ) throws -> PhotoAsset {
            let facts = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
            ])
            return PhotoAsset(
                id: id,
                url: url,
                path: url.path,
                filename: url.lastPathComponent,
                fileExtension: "jpg",
                fileSize: Int64(try XCTUnwrap(facts.fileSize)),
                creationDate: nil,
                modificationDate:
                    facts.contentModificationDate,
                format: .jpeg
            )
        }

        let first = try asset(id: "first", url: firstURL)
        let second = try asset(id: "second", url: secondURL)
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [first, second],
            rootURL: directory,
            recursive: false
        )
        let recorder = InvocationRecorder()
        let analyzer = PeopleAnalyzer(
            catalogStore: store
        ) { asset in
            await recorder.record(asset.id)
            return []
        }

        let firstScan = try await analyzer.scan(
            photoIDs: [first.id]
        )
        XCTAssertEqual(firstScan.candidateCount, 1)
        XCTAssertEqual(firstScan.analyzedCount, 1)
        let recordedAfterFirst = await recorder.ids
        XCTAssertEqual(recordedAfterFirst, [first.id])

        let candidates = try store.peopleAnalysisCandidates(
            engineVersion: PeopleAnalyzer.currentEngineVersion
        )
        let byID = Dictionary(
            uniqueKeysWithValues:
                candidates.map {
                    ($0.entry.id, $0.cachedFaces)
                }
        )
        XCTAssertEqual(byID[first.id]!, [])
        XCTAssertNil(byID[second.id]!)

        let cachedFirst = try await analyzer.scan(
            photoIDs: [first.id]
        )
        XCTAssertEqual(cachedFirst.cachedCount, 1)
        let recordedAfterCache = await recorder.ids
        XCTAssertEqual(recordedAfterCache, [first.id])

        let secondScan = try await analyzer.scan(
            photoIDs: [second.id]
        )
        XCTAssertEqual(secondScan.candidateCount, 1)
        XCTAssertEqual(secondScan.analyzedCount, 1)
        let recordedAfterSecond = await recorder.ids
        XCTAssertEqual(
            recordedAfterSecond,
            [first.id, second.id]
        )
    }

    func testIdenticalDescriptorsCreateSuggestionWithoutIdentity()
        throws {
        let descriptor = try makeFeaturePrint(gray: 0.45)
        let personID = UUID()
        let namedFace = CatalogFace(
            id: "named",
            photoID: "p0",
            boundingBox: CGRect(
                x: 0.1,
                y: 0.1,
                width: 0.3,
                height: 0.4
            ),
            confidence: 1,
            captureQuality: 0.9,
            featurePrintData: descriptor,
            personID: personID
        )
        let first = CatalogFace(
            id: "a",
            photoID: "p1",
            boundingBox: CGRect(
                x: 0.1,
                y: 0.1,
                width: 0.3,
                height: 0.4
            ),
            confidence: 1,
            captureQuality: 0.8,
            featurePrintData: descriptor
        )
        let second = CatalogFace(
            id: "b",
            photoID: "p2",
            boundingBox: CGRect(
                x: 0.2,
                y: 0.2,
                width: 0.3,
                height: 0.4
            ),
            confidence: 1,
            captureQuality: 0.7,
            featurePrintData: descriptor
        )
        let invalid = CatalogFace(
            id: "c",
            photoID: "p3",
            boundingBox: CGRect(
                x: 0.3,
                y: 0.2,
                width: 0.2,
                height: 0.3
            ),
            confidence: 0.8,
            captureQuality: nil,
            featurePrintData: Data([1, 2, 3])
        )

        let snapshot = PeopleAnalyzer.makeSnapshot(
            people: [
                CatalogPerson(id: personID, name: "Named")
            ],
            faces: [namedFace, first, second, invalid],
            similarityThreshold: 0.01
        )
        XCTAssertEqual(snapshot.namedGroups.count, 1)
        XCTAssertEqual(snapshot.namedGroups.first?.faces, [namedFace])
        XCTAssertEqual(snapshot.suggestedGroups.count, 1)
        XCTAssertEqual(
            Set(
                snapshot.suggestedGroups[0].faces.map(\.id)
            ),
            Set(["a", "b"])
        )
        XCTAssertTrue(
            snapshot.suggestedGroups[0].faces.allSatisfy {
                $0.personID == nil
            }
        )
        XCTAssertEqual(snapshot.singleFaces, [invalid])
    }
}

@MainActor
final class PeopleBackgroundAnalysisTests: XCTestCase {
    private actor InvocationRecorder {
        private(set) var ids: [PhotoAsset.ID] = []

        func record(_ id: PhotoAsset.ID) {
            ids.append(id)
        }
    }

    private actor BlockingDetection {
        private(set) var started = false

        func run() async throws -> [PeopleFaceDetection] {
            started = true
            try await Task.sleep(
                nanoseconds: 5_000_000_000
            )
            return []
        }
    }

    private enum TestFailure: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Synthetic background failure"
        }
    }

    private enum WaitFailure: Error {
        case timedOut
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-people-background-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makeAsset(
        id: String,
        in directory: URL,
        bytes: [UInt8]
    ) throws -> PhotoAsset {
        let url = directory.appendingPathComponent(
            "\(id).jpg"
        )
        try Data(bytes).write(to: url)
        let facts = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        return PhotoAsset(
            id: id,
            url: url,
            path: url.path,
            filename: url.lastPathComponent,
            fileExtension: "jpg",
            fileSize: Int64(try XCTUnwrap(facts.fileSize)),
            creationDate: nil,
            modificationDate:
                facts.contentModificationDate,
            format: .jpeg
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                throw WaitFailure.timedOut
            }
            try await Task.sleep(
                nanoseconds: 10_000_000
            )
        }
    }

    private func waitUntilAsync(
        timeout: TimeInterval = 2,
        _ condition: () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            guard Date() < deadline else {
                throw WaitFailure.timedOut
            }
            try await Task.sleep(
                nanoseconds: 10_000_000
            )
        }
    }

    func testPreferencesDefaultOffRoundTripAndRecoverFromCorruption()
        throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }
        let store = PeopleAnalysisPreferencesStore(
            directory: directory
        )
        XCTAssertFalse(
            store.load().automaticAnalysisEnabled
        )

        store.save(PeopleAnalysisPreferences(
            automaticAnalysisEnabled: true
        ))
        XCTAssertTrue(
            PeopleAnalysisPreferencesStore(
                directory: directory
            ).load().automaticAnalysisEnabled
        )

        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent(
                "people_analysis_settings.json"
            )
        )
        XCTAssertFalse(
            PeopleAnalysisPreferencesStore(
                directory: directory
            ).load().automaticAnalysisEnabled
        )
        let backups = try FileManager.default
            .contentsOfDirectory(
                atPath: directory.path
            )
            .filter {
                $0.hasPrefix(
                    "people_analysis_settings.json.corrupt."
                )
            }
        XCTAssertEqual(backups.count, 1)
    }

    func testAutomaticAnalysisIsOptInPersistsAndUsesCache()
        async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }
        let asset = try makeAsset(
            id: "portrait",
            in: directory,
            bytes: [1, 2, 3, 4]
        )
        let catalog = CatalogStore(directory: directory)
        try catalog.upsert(
            assets: [asset],
            rootURL: directory,
            recursive: false
        )
        let recorder = InvocationRecorder()
        let analyzer = PeopleAnalyzer(
            catalogStore: catalog
        ) { asset in
            await recorder.record(asset.id)
            return []
        }
        let preferences =
            PeopleAnalysisPreferencesStore(
                directory: directory
            )
        let first = PeopleViewModel(
            catalogStore: catalog,
            analyzer: analyzer,
            preferencesStore: preferences
        )

        first.startAutomaticAnalysisIfNeeded()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(first.isScanning)
        let idsBeforeOptIn = await recorder.ids
        XCTAssertEqual(idsBeforeOptIn, [])

        first.setAutomaticAnalysisEnabled(true)
        try await waitUntil {
            !first.isScanning
                && first.lastScanResult != nil
        }
        XCTAssertEqual(
            first.lastScanResult?.analyzedCount,
            1
        )
        let idsAfterOptIn = await recorder.ids
        XCTAssertEqual(idsAfterOptIn, [asset.id])
        XCTAssertTrue(
            preferences.load().automaticAnalysisEnabled
        )

        let reopened = PeopleViewModel(
            catalogStore: catalog,
            analyzer: analyzer,
            preferencesStore:
                PeopleAnalysisPreferencesStore(
                    directory: directory
                )
        )
        XCTAssertTrue(reopened.automaticAnalysisEnabled)
        reopened.startAutomaticAnalysisIfNeeded()
        try await waitUntil {
            !reopened.isScanning
                && reopened.lastScanResult != nil
        }
        XCTAssertEqual(
            reopened.lastScanResult?.cachedCount,
            1
        )
        let idsAfterReopen = await recorder.ids
        XCTAssertEqual(idsAfterReopen, [asset.id])
    }

    func testCatalogChangeAnalyzesOnlyNewPhoto()
        async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }
        let firstAsset = try makeAsset(
            id: "first",
            in: directory,
            bytes: [1, 2, 3, 4]
        )
        let catalog = CatalogStore(directory: directory)
        try catalog.upsert(
            assets: [firstAsset],
            rootURL: directory,
            recursive: false
        )
        let recorder = InvocationRecorder()
        let analyzer = PeopleAnalyzer(
            catalogStore: catalog
        ) { asset in
            await recorder.record(asset.id)
            return []
        }
        let preferences =
            PeopleAnalysisPreferencesStore(
                directory: directory
            )
        preferences.save(PeopleAnalysisPreferences(
            automaticAnalysisEnabled: true
        ))
        let model = PeopleViewModel(
            catalogStore: catalog,
            analyzer: analyzer,
            preferencesStore: preferences
        )
        model.startAutomaticAnalysisIfNeeded()
        try await waitUntil {
            !model.isScanning
                && model.lastScanResult != nil
        }

        let secondAsset = try makeAsset(
            id: "second",
            in: directory,
            bytes: [5, 6, 7, 8]
        )
        try catalog.upsert(
            assets: [secondAsset],
            rootURL: directory,
            recursive: false
        )
        model.catalogDidChange()
        try await waitUntil {
            !model.isScanning
                && model.lastScanResult?.candidateCount == 2
                && model.lastScanResult?.analyzedCount == 1
        }
        XCTAssertEqual(
            model.lastScanResult?.cachedCount,
            1
        )
        let analyzedIDs = await recorder.ids
        XCTAssertEqual(
            analyzedIDs,
            [firstAsset.id, secondAsset.id]
        )
    }

    func testDisablingPausesAutomaticScanAndFailureIsNonModal()
        async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }
        let asset = try makeAsset(
            id: "slow",
            in: directory,
            bytes: [1, 2, 3, 4]
        )
        let catalog = CatalogStore(directory: directory)
        try catalog.upsert(
            assets: [asset],
            rootURL: directory,
            recursive: false
        )
        let preferences =
            PeopleAnalysisPreferencesStore(
                directory: directory
            )
        let blocker = BlockingDetection()
        let blockingAnalyzer = PeopleAnalyzer(
            catalogStore: catalog
        ) { _ in
            try await blocker.run()
        }
        let model = PeopleViewModel(
            catalogStore: catalog,
            analyzer: blockingAnalyzer,
            preferencesStore: preferences
        )
        model.setAutomaticAnalysisEnabled(true)
        try await waitUntil {
            model.isAutomaticScan
        }
        try await waitUntilAsync {
            await blocker.started
        }
        model.applicationDidBecomeInactive()
        XCTAssertFalse(model.isScanning)
        XCTAssertTrue(model.automaticAnalysisEnabled)
        model.applicationDidBecomeActive()
        try await waitUntil {
            model.isAutomaticScan
        }
        model.setAutomaticAnalysisEnabled(false)
        XCTAssertFalse(model.isScanning)
        XCTAssertFalse(
            preferences.load().automaticAnalysisEnabled
        )

        let failurePreferences =
            PeopleAnalysisPreferencesStore(
                directory: directory.appendingPathComponent(
                    "failure",
                    isDirectory: true
                )
            )
        failurePreferences.save(
            PeopleAnalysisPreferences(
                automaticAnalysisEnabled: true
            )
        )
        let failureAnalyzer = PeopleAnalyzer(
            catalogStore: catalog
        ) { _ in
            throw TestFailure.unavailable
        }
        let failing = PeopleViewModel(
            catalogStore: catalog,
            analyzer: failureAnalyzer,
            preferencesStore: failurePreferences
        )
        failing.startAutomaticAnalysisIfNeeded()
        try await waitUntil {
            !failing.isScanning
                && failing.backgroundStatusMessage != nil
        }
        XCTAssertNil(failing.errorMessage)
        XCTAssertTrue(failing.automaticAnalysisEnabled)
        XCTAssertTrue(
            failing.backgroundStatusMessage?
                .contains("retry later") == true
        )
    }
}
