import XCTest
import AppKit
import AVFoundation
import CoreVideo
import ImageIO
import SQLite3
import UniformTypeIdentifiers
@testable import RAWDesk

private enum ExactImageDuplicateTestFixture {
    private enum FixtureError: Error {
        case imageCreationFailed
        case imageWriteFailed
    }

    static func image(variant: UInt8) throws -> CGImage {
        let width = 24
        let height = 18
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](
            repeating: 0,
            count: bytesPerRow * height
        )
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let accent = x >= width / 2 && y < height / 2
                pixels[offset] = accent
                    ? 240
                    : UInt8(35 + Int(variant) * 17)
                pixels[offset + 1] = accent
                    ? UInt8(70 + Int(variant) * 19)
                    : 135
                pixels[offset + 2] = UInt8(
                    45 + ((x + y + Int(variant)) % 5) * 28
                )
                pixels[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(
            data: Data(pixels) as CFData
        ),
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.noneSkipLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw FixtureError.imageCreationFailed
        }
        return image
    }

    static func writeJPEG(
        _ image: CGImage,
        to url: URL,
        description: String
    ) throws {
        guard let destination =
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
            throw FixtureError.imageWriteFailed
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFImageDescription: description,
                kCGImagePropertyTIFFSoftware:
                    "RAWDesk exact-image-data tests",
            ],
        ]
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.imageWriteFailed
        }
    }

    static func asset(
        id: String,
        url: URL
    ) throws -> PhotoAsset {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
        ])
        return PhotoAsset(
            id: id,
            url: url,
            path: url.path,
            filename: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSize: Int64(values.fileSize ?? 0),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            format: .jpeg
        )
    }
}

final class FileTypeDetectorTests: XCTestCase {
    func testFormatDetection() {
        XCTAssertEqual(FileTypeDetector.format(forExtension: "jpg"), .jpeg)
        XCTAssertEqual(FileTypeDetector.format(forExtension: "JPG"), .jpeg)
        XCTAssertEqual(FileTypeDetector.format(forExtension: "ARW"), .sonyARW)
        XCTAssertEqual(FileTypeDetector.format(forExtension: "arw"), .sonyARW)
        XCTAssertEqual(FileTypeDetector.format(forExtension: "CR2"), .canonCR2)
        XCTAssertEqual(FileTypeDetector.format(forExtension: "cr2"), .canonCR2)
        XCTAssertEqual(FileTypeDetector.format(forExtension: "dng"), .dng)
        XCTAssertEqual(FileTypeDetector.format(forExtension: "xyz"), .unsupported)
    }

    func testRawDetection() {
        XCTAssertTrue(FileFormat.sonyARW.isRaw)
        XCTAssertTrue(FileFormat.canonCR2.isRaw)
        XCTAssertTrue(FileFormat.dng.isRaw)
        XCTAssertFalse(FileFormat.jpeg.isRaw)
        XCTAssertFalse(FileFormat.png.isRaw)
    }

    func testIsSupported() {
        XCTAssertTrue(FileTypeDetector.isSupported(url: URL(fileURLWithPath: "/tmp/x.ARW")))
        XCTAssertTrue(FileTypeDetector.isSupported(url: URL(fileURLWithPath: "/tmp/x.cr2")))
        XCTAssertFalse(FileTypeDetector.isSupported(url: URL(fileURLWithPath: "/tmp/x.txt")))
    }
}

final class RAWDeskStorageDirectoryTests: XCTestCase {
    func testTestProcessDetectionCoversSwiftPMAndXcodeHosts() {
        XCTAssertTrue(
            RAWDeskStorageDirectory.isTestProcess(
                processName: "RAWDeskPackageTests",
                arguments: [
                    "/tmp/RAWDeskPackageTests.xctest/Contents/MacOS/RAWDeskPackageTests",
                ],
                environment: [:]
            )
        )
        XCTAssertTrue(
            RAWDeskStorageDirectory.isTestProcess(
                processName: "RAWDesk",
                arguments: ["/tmp/RAWDesk.app/Contents/MacOS/RAWDesk"],
                environment: [
                    "XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration",
                ]
            )
        )
        XCTAssertFalse(
            RAWDeskStorageDirectory.isTestProcess(
                processName: "RAWDesk",
                arguments: ["/Applications/RAWDesk.app/Contents/MacOS/RAWDesk"],
                environment: [:]
            )
        )
    }

    func testDefaultTestResolutionNeverUsesApplicationSupport() {
        let directory = RAWDeskStorageDirectory.resolve(nil)
        XCTAssertTrue(
            RAWDeskStorageDirectory.isTestProcess()
        )
        if let overridePath =
            ProcessInfo.processInfo.environment[
                RAWDeskStorageDirectory
                    .overrideEnvironmentKey
            ] {
            XCTAssertEqual(
                directory,
                URL(
                    fileURLWithPath: overridePath,
                    isDirectory: true
                ).standardizedFileURL
            )
        } else {
            XCTAssertTrue(
                directory.lastPathComponent.hasPrefix(
                    "RAWDesk-Tests-"
                )
            )
        }
        XCTAssertFalse(
            directory.path.contains(
                "/Library/Application Support/RAWDesk"
            )
        )
    }
}

final class PhotoComparePlannerTests: XCTestCase {
    func testStartUsesPrimaryAsSelectAndAnotherSelectedPhotoAsCandidate() {
        let state = PhotoComparePlanner.start(
            primaryID: "c",
            selectedIDs: ["a", "c"],
            visibleIDs: ["a", "b", "c", "d"]
        )

        XCTAssertEqual(
            state,
            PhotoCompareState(
                selectID: "c",
                candidateID: "a"
            )
        )
    }

    func testStartWithOneSelectionWrapsToVisibleNeighbor() {
        let state = PhotoComparePlanner.start(
            primaryID: "c",
            selectedIDs: ["c"],
            visibleIDs: ["a", "b", "c"]
        )

        XCTAssertEqual(
            state,
            PhotoCompareState(
                selectID: "c",
                candidateID: "a"
            )
        )
    }

    func testCandidateNavigationSkipsSelectAndWraps() {
        let start = PhotoCompareState(
            selectID: "b",
            candidateID: "c"
        )

        let next = PhotoComparePlanner.movingCandidate(
            in: start,
            direction: 1,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(next?.candidateID, "d")

        let wrapped = PhotoComparePlanner.movingCandidate(
            in: try! XCTUnwrap(next),
            direction: 1,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(wrapped?.candidateID, "a")

        let previous = PhotoComparePlanner.movingCandidate(
            in: try! XCTUnwrap(wrapped),
            direction: -1,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(previous?.candidateID, "d")
    }

    func testPromotingCandidateAdvancesToNextCandidate() {
        let promoted = PhotoComparePlanner.promotingCandidate(
            in: PhotoCompareState(
                selectID: "a",
                candidateID: "b"
            ),
            visibleIDs: ["a", "b", "c"]
        )

        XCTAssertEqual(
            promoted,
            PhotoCompareState(
                selectID: "b",
                candidateID: "c"
            )
        )
    }

    func testPromotingWithTwoPhotosKeepsFormerSelectAsCandidate() {
        let promoted = PhotoComparePlanner.promotingCandidate(
            in: PhotoCompareState(
                selectID: "a",
                candidateID: "b"
            ),
            visibleIDs: ["a", "b"]
        )

        XCTAssertEqual(
            promoted,
            PhotoCompareState(
                selectID: "b",
                candidateID: "a"
            )
        )
    }

    func testSwapExchangesRoles() {
        let swapped = PhotoComparePlanner.swapping(
            PhotoCompareState(
                selectID: "a",
                candidateID: "c"
            ),
            visibleIDs: ["a", "b", "c"]
        )

        XCTAssertEqual(
            swapped,
            PhotoCompareState(
                selectID: "c",
                candidateID: "a"
            )
        )
    }

    func testReconcileRepairsRemovedPhotosAndStopsBelowTwo() {
        let repaired = PhotoComparePlanner.reconcile(
            PhotoCompareState(
                selectID: "missing-select",
                candidateID: "b"
            ),
            visibleIDs: ["a", "b", "c"]
        )
        XCTAssertEqual(
            repaired,
            PhotoCompareState(
                selectID: "b",
                candidateID: "c"
            )
        )

        XCTAssertNil(
            PhotoComparePlanner.reconcile(
                PhotoCompareState(
                    selectID: "a",
                    candidateID: "b"
                ),
                visibleIDs: ["a"]
            )
        )
    }
}

final class PhotoSurveyPlannerTests: XCTestCase {
    func testStartUsesVisibleSelectionOrderAndPrimary() {
        let state = PhotoSurveyPlanner.start(
            primaryID: "d",
            selectedIDs: ["a", "c", "d", "missing"],
            visibleIDs: ["a", "b", "c", "d"]
        )

        XCTAssertEqual(
            state,
            PhotoSurveyState(
                photoIDs: ["a", "c", "d"],
                activeID: "d"
            )
        )
    }

    func testStartRequiresTwoVisibleSelectedPhotos() {
        XCTAssertNil(
            PhotoSurveyPlanner.start(
                primaryID: "a",
                selectedIDs: ["a", "missing"],
                visibleIDs: ["a", "b"]
            )
        )
    }

    func testAddingPhotoOrdersByVisibleListAndMakesItActive() {
        let state = PhotoSurveyPlanner.adding(
            "b",
            to: PhotoSurveyState(
                photoIDs: ["a", "d"],
                activeID: "d"
            ),
            visibleIDs: ["a", "b", "c", "d"]
        )

        XCTAssertEqual(
            state,
            PhotoSurveyState(
                photoIDs: ["a", "b", "d"],
                activeID: "b"
            )
        )
    }

    func testActivatingAndNavigationWrapWithinSurvey() {
        let start = PhotoSurveyState(
            photoIDs: ["a", "c", "d"],
            activeID: "c"
        )
        let activated = PhotoSurveyPlanner.activating(
            "a",
            in: start,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(activated?.activeID, "a")

        let previous = PhotoSurveyPlanner.movingActive(
            in: try! XCTUnwrap(activated),
            direction: -1,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(previous?.activeID, "d")

        let next = PhotoSurveyPlanner.movingActive(
            in: try! XCTUnwrap(previous),
            direction: 1,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(next?.activeID, "a")
    }

    func testRemovingActiveChoosesNeighborAndStopsBelowTwo() {
        let start = PhotoSurveyState(
            photoIDs: ["a", "b", "c"],
            activeID: "b"
        )
        let removed = PhotoSurveyPlanner.removing(
            "b",
            from: start,
            visibleIDs: ["a", "b", "c"]
        )
        XCTAssertEqual(
            removed,
            PhotoSurveyState(
                photoIDs: ["a", "c"],
                activeID: "c"
            )
        )

        XCTAssertNil(
            PhotoSurveyPlanner.removing(
                "a",
                from: try! XCTUnwrap(removed),
                visibleIDs: ["a", "c"]
            )
        )
    }

    func testReconcileRemovesHiddenPhotosAndRepairsActive() {
        let reconciled = PhotoSurveyPlanner.reconcile(
            PhotoSurveyState(
                photoIDs: ["a", "b", "c", "missing"],
                activeID: "b"
            ),
            visibleIDs: ["c", "a", "d"]
        )

        XCTAssertEqual(
            reconciled,
            PhotoSurveyState(
                photoIDs: ["c", "a"],
                activeID: "c"
            )
        )
        XCTAssertNil(
            PhotoSurveyPlanner.reconcile(
                PhotoSurveyState(
                    photoIDs: ["a", "b"],
                    activeID: "a"
                ),
                visibleIDs: ["a"]
            )
        )
    }
}

final class PhotoSurveyLayoutPlannerTests: XCTestCase {
    func testLayoutUsesBalancedRowsAtTypicalWidth() {
        let four = PhotoSurveyLayoutPlanner.metrics(
            photoCount: 4,
            width: 900,
            height: 520
        )
        XCTAssertEqual(four.columns, 2)
        XCTAssertEqual(four.rows, 2)
        XCTAssertGreaterThan(four.cellWidth, 400)
        XCTAssertGreaterThan(four.cellHeight, 200)

        let nine = PhotoSurveyLayoutPlanner.metrics(
            photoCount: 9,
            width: 1_000,
            height: 600
        )
        XCTAssertEqual(nine.columns, 3)
        XCTAssertEqual(nine.rows, 3)
        XCTAssertGreaterThanOrEqual(
            nine.cellHeight,
            PhotoSurveyLayoutPlanner.minimumCellHeight
        )
    }

    func testLayoutNarrowsColumnsAndHandlesEmptySurvey() {
        let narrow = PhotoSurveyLayoutPlanner.metrics(
            photoCount: 4,
            width: 400,
            height: 500
        )
        XCTAssertEqual(narrow.columns, 1)
        XCTAssertEqual(narrow.rows, 4)

        let empty = PhotoSurveyLayoutPlanner.metrics(
            photoCount: 0,
            width: 500,
            height: 400
        )
        XCTAssertEqual(empty.columns, 1)
        XCTAssertEqual(empty.rows, 0)
        XCTAssertEqual(empty.cellHeight, 0)
    }
}

final class PhotoReferencePlannerTests: XCTestCase {
    func testStartUsesActiveAndAnotherSelectedPhoto() {
        let state = PhotoReferencePlanner.start(
            activeID: "c",
            selectedIDs: ["a", "c"],
            visibleIDs: ["a", "b", "c", "d"],
            availableIDs: ["a", "b", "c", "d"]
        )

        XCTAssertEqual(
            state,
            PhotoReferenceState(
                referenceID: "a",
                activeID: "c"
            )
        )
    }

    func testStartCanOpenWithoutReferenceAndRequiresActivePhoto() {
        XCTAssertEqual(
            PhotoReferencePlanner.start(
                activeID: "b",
                selectedIDs: ["b"],
                visibleIDs: ["a", "b"],
                availableIDs: ["a", "b"]
            ),
            PhotoReferenceState(
                referenceID: nil,
                activeID: "b"
            )
        )
        XCTAssertNil(
            PhotoReferencePlanner.start(
                activeID: nil,
                selectedIDs: [],
                visibleIDs: [],
                availableIDs: []
            )
        )
    }

    func testLockedReferenceTakesPriorityAndMayBeFilteredOut() {
        let state = PhotoReferencePlanner.start(
            activeID: "c",
            selectedIDs: ["a", "c"],
            visibleIDs: ["a", "c"],
            availableIDs: ["a", "c", "hidden"],
            lockedReferenceID: "hidden",
            layout: .topBottom
        )

        XCTAssertEqual(
            state,
            PhotoReferenceState(
                referenceID: "hidden",
                activeID: "c",
                layout: .topBottom,
                isReferenceLocked: true
            )
        )

        XCTAssertEqual(
            PhotoReferencePlanner.start(
                activeID: nil,
                selectedIDs: [],
                visibleIDs: ["hidden", "c"],
                availableIDs: ["hidden", "c"],
                lockedReferenceID: "hidden"
            ),
            PhotoReferenceState(
                referenceID: "hidden",
                activeID: "c",
                isReferenceLocked: true
            )
        )
    }

    func testChoosingReferenceAsActiveSwapsRoles() {
        let state = PhotoReferenceState(
            referenceID: "a",
            activeID: "c"
        )

        XCTAssertEqual(
            PhotoReferencePlanner.settingActive(
                "a",
                in: state,
                visibleIDs: ["a", "b", "c"]
            ),
            PhotoReferenceState(
                referenceID: "c",
                activeID: "a"
            )
        )
        XCTAssertEqual(
            PhotoReferencePlanner.settingReference(
                "b",
                in: state,
                availableIDs: ["a", "b", "c"]
            ).referenceID,
            "b"
        )
    }

    func testActiveNavigationSkipsReferenceAndWraps() {
        let state = PhotoReferenceState(
            referenceID: "b",
            activeID: "c"
        )
        let next = PhotoReferencePlanner.movingActive(
            in: state,
            direction: 1,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(next.activeID, "d")

        let wrapped = PhotoReferencePlanner.movingActive(
            in: next,
            direction: 1,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(wrapped.activeID, "a")

        let previous = PhotoReferencePlanner.movingActive(
            in: wrapped,
            direction: -1,
            visibleIDs: ["a", "b", "c", "d"]
        )
        XCTAssertEqual(previous.activeID, "d")
    }

    func testSwapAndReconcilePreserveAvailableHiddenReference() {
        let swapped = PhotoReferencePlanner.swapping(
            PhotoReferenceState(
                referenceID: "a",
                activeID: "c"
            )
        )
        XCTAssertEqual(
            swapped,
            PhotoReferenceState(
                referenceID: "c",
                activeID: "a"
            )
        )

        let repaired = PhotoReferencePlanner.reconcile(
            PhotoReferenceState(
                referenceID: "hidden",
                activeID: "missing",
                isReferenceLocked: true
            ),
            visibleIDs: ["c", "d"],
            availableIDs: ["hidden", "c", "d"]
        )
        XCTAssertEqual(
            repaired,
            PhotoReferenceState(
                referenceID: "hidden",
                activeID: "c",
                isReferenceLocked: true
            )
        )

        let missingReference = PhotoReferencePlanner.reconcile(
            try! XCTUnwrap(repaired),
            visibleIDs: ["c", "d"],
            availableIDs: ["c", "d"]
        )
        XCTAssertEqual(missingReference?.activeID, "c")
        XCTAssertNil(missingReference?.referenceID)
        XCTAssertFalse(
            try! XCTUnwrap(missingReference)
                .isReferenceLocked
        )
        XCTAssertNil(
            PhotoReferencePlanner.reconcile(
                swapped,
                visibleIDs: [],
                availableIDs: []
            )
        )
    }
}

final class ReferenceToneDeltaTests: XCTestCase {
    func testCalculatesActiveMinusReferenceCenters() throws {
        let reference = HistogramData(
            red: [1, 0, 0],
            green: [0, 1, 0],
            blue: [0, 0, 1]
        )
        let active = HistogramData(
            red: [0, 1, 0],
            green: [0, 0, 1],
            blue: [1, 0, 0]
        )

        let delta = try XCTUnwrap(
            ReferenceToneDelta.calculate(
                reference: reference,
                active: active
            )
        )
        XCTAssertEqual(delta.red, 50, accuracy: 0.000_1)
        XCTAssertEqual(delta.green, 50, accuracy: 0.000_1)
        XCTAssertEqual(delta.blue, -100, accuracy: 0.000_1)
    }

    func testRequiresPopulatedHistograms() {
        XCTAssertNil(
            ReferenceToneDelta.calculate(
                reference: .empty,
                active: HistogramData(
                    red: [1, 0],
                    green: [1, 0],
                    blue: [1, 0]
                )
            )
        )
    }
}

final class ImagePixelSampleTests: XCTestCase {
    func testConvertsSRGBPrimaryToD65Lab() {
        let lab = ImagePixelSample(
            red: 1,
            green: 0,
            blue: 0
        ).lab

        XCTAssertEqual(
            lab.lightness,
            53.2408,
            accuracy: 0.001
        )
        XCTAssertEqual(lab.a, 80.0925, accuracy: 0.001)
        XCTAssertEqual(lab.b, 67.2032, accuracy: 0.001)
    }

    func testClampsChannelsAndKeepsWhiteNeutral() {
        let sample = ImagePixelSample(
            red: 2,
            green: 1,
            blue: .infinity
        )
        XCTAssertEqual(sample.red, 1)
        XCTAssertEqual(sample.green, 1)
        XCTAssertEqual(sample.blue, 0)

        let whiteLab = ImagePixelSample(
            red: 1,
            green: 1,
            blue: 1
        ).lab
        XCTAssertEqual(
            whiteLab.lightness,
            100,
            accuracy: 0.000_1
        )
        XCTAssertEqual(whiteLab.a, 0, accuracy: 0.000_1)
        XCTAssertEqual(whiteLab.b, 0, accuracy: 0.000_1)
    }
}

final class ImageViewportMapperTests: XCTestCase {
    func testFitMappingRejectsLetterboxAndReturnsImagePoint()
        throws
    {
        let point = try XCTUnwrap(
            ImageViewportMapper.normalizedPoint(
                location: CGPoint(x: 50, y: 100),
                containerSize: CGSize(
                    width: 200,
                    height: 200
                ),
                imageSize: CGSize(
                    width: 100,
                    height: 50
                ),
                transform: .identity
            )
        )
        XCTAssertEqual(point.x, 0.25, accuracy: 0.000_1)
        XCTAssertEqual(point.y, 0.5, accuracy: 0.000_1)

        XCTAssertNil(
            ImageViewportMapper.normalizedPoint(
                location: CGPoint(x: 100, y: 25),
                containerSize: CGSize(
                    width: 200,
                    height: 200
                ),
                imageSize: CGSize(
                    width: 100,
                    height: 50
                ),
                transform: .identity
            )
        )
    }

    func testMappingInvertsQuarterTurn() throws {
        let point = try XCTUnwrap(
            ImageViewportMapper.normalizedPoint(
                location: CGPoint(x: 100, y: 0),
                containerSize: CGSize(
                    width: 100,
                    height: 200
                ),
                imageSize: CGSize(
                    width: 100,
                    height: 50
                ),
                transform: ImageTransformState(
                    rotationDegrees: 90
                )
            )
        )
        XCTAssertEqual(point.x, 0, accuracy: 0.000_1)
        XCTAssertEqual(point.y, 0, accuracy: 0.000_1)
    }

    func testMappingInvertsFlips() throws {
        let point = try XCTUnwrap(
            ImageViewportMapper.normalizedPoint(
                location: CGPoint(x: 25, y: 75),
                containerSize: CGSize(
                    width: 100,
                    height: 100
                ),
                imageSize: CGSize(
                    width: 100,
                    height: 100
                ),
                transform: ImageTransformState(
                    flipHorizontal: true,
                    flipVertical: true
                )
            )
        )
        XCTAssertEqual(point.x, 0.75, accuracy: 0.000_1)
        XCTAssertEqual(point.y, 0.25, accuracy: 0.000_1)
    }

    func testMappingAccountsForZoomAndPan() throws {
        let point = try XCTUnwrap(
            ImageViewportMapper.normalizedPoint(
                location: CGPoint(x: 70, y: 140),
                containerSize: CGSize(
                    width: 200,
                    height: 200
                ),
                imageSize: CGSize(
                    width: 100,
                    height: 100
                ),
                transform: ImageTransformState(
                    zoom: 2,
                    fitToWindow: false
                ),
                panOffset: CGSize(
                    width: 20,
                    height: -10
                )
            )
        )
        XCTAssertEqual(point.x, 0.25, accuracy: 0.000_1)
        XCTAssertEqual(point.y, 0.75, accuracy: 0.000_1)
    }
}

final class PhotoAdjustmentSyncPlannerTests: XCTestCase {
    func testMixedValuePlannerKeepsMatchingSliderValuesConcrete() {
        XCTAssertFalse(
            PhotoAdjustmentMixedValuePlanner.doublesAreMixed(
                [42, 42, 42]
            )
        )
        XCTAssertFalse(
            PhotoAdjustmentMixedValuePlanner.doublesAreMixed(
                [42, 42.000_000_5]
            )
        )
    }

    func testMixedValuePlannerFindsDifferentSliderValues() {
        XCTAssertTrue(
            PhotoAdjustmentMixedValuePlanner.doublesAreMixed(
                [42, 43]
            )
        )
    }

    func testMixedValuePlannerTreatsPartiallyMissingNestedControlAsMixed() {
        XCTAssertTrue(
            PhotoAdjustmentMixedValuePlanner.doublesAreMixed(
                [42, nil]
            )
        )
        XCTAssertFalse(
            PhotoAdjustmentMixedValuePlanner.doublesAreMixed(
                [nil, nil]
            )
        )
    }

    func testMixedValuePlannerSupportsWholeAdjustmentValues() {
        XCTAssertFalse(
            PhotoAdjustmentMixedValuePlanner.valuesAreMixed(
                [ToneCurve.neutral, ToneCurve.neutral]
            )
        )
        var changed = ToneCurve.neutral
        changed.midtones = 0.65
        XCTAssertTrue(
            PhotoAdjustmentMixedValuePlanner.valuesAreMixed(
                [ToneCurve.neutral, changed]
            )
        )
    }

    func testSelectiveMergeCopiesOnlyChosenPanels() {
        let source = PhotoAdjustments(
            exposure: 1.4,
            contrast: 32,
            temperature: 28,
            sharpening: 75
        )
        let target = PhotoAdjustments(
            exposure: -0.7,
            contrast: -18,
            temperature: -42,
            sharpening: 12
        )

        let merged =
            PhotoAdjustmentSyncPlanner.merging(
                source: source,
                into: target,
                groups: [.light]
            )

        XCTAssertEqual(merged.exposure, 1.4)
        XCTAssertEqual(merged.contrast, 32)
        XCTAssertEqual(merged.temperature, -42)
        XCTAssertEqual(merged.sharpening, 12)
    }

    func testModifiedPresetFindsNonDefaultPanels() {
        let source = PhotoAdjustments(
            developmentProfile:
                DevelopmentProfileSettings(
                    profile: .vivid,
                    amount: 130
                ),
            shadows: 24,
            temperature: 18,
            grainAmount: 35
        )

        XCTAssertEqual(
            PhotoAdjustmentSyncPlanner.modifiedGroups(
                in: source
            ),
            [
                .profile,
                .light,
                .color,
                .effects,
            ]
        )
    }

    func testEffectsEnablementPersistsAndParticipatesInSync() throws {
        let disabled = PhotoAdjustments(
            effectsEnabled: false,
            texture: 24,
            grainAmount: 35
        )
        let roundTripped = try JSONDecoder().decode(
            PhotoAdjustments.self,
            from: JSONEncoder().encode(disabled)
        )
        XCTAssertFalse(roundTripped.effectsEnabled)
        XCTAssertTrue(
            PhotoAdjustmentSyncPlanner
                .modifiedGroups(in: disabled)
                .contains(.effects)
        )

        let manuallyMerged =
            PhotoAdjustmentSyncPlanner.merging(
                source: disabled,
                into: .neutral,
                groups: [.effects]
            )
        XCTAssertFalse(manuallyMerged.effectsEnabled)
        XCTAssertEqual(manuallyMerged.texture, 24)

        let automaticallyMerged =
            PhotoAdjustmentSyncPlanner
                .applyingAutomaticChanges(
                    from: .neutral,
                    to: disabled,
                    onto: PhotoAdjustments(
                        effectsEnabled: true,
                        clarity: 18
                    )
                )
        XCTAssertFalse(automaticallyMerged.effectsEnabled)
        XCTAssertEqual(automaticallyMerged.texture, 24)
        XCTAssertEqual(automaticallyMerged.clarity, 18)

        let legacy = try JSONDecoder().decode(
            PhotoAdjustments.self,
            from: Data(#"{"texture":12}"#.utf8)
        )
        XCTAssertTrue(legacy.effectsEnabled)
    }

    func testAutomaticPatchPreservesUnchangedSiblingValues() {
        var before = PhotoAdjustments(
            exposure: 0,
            contrast: 22
        )
        var sourceBlue = before.colorMixer[.blue]
        sourceBlue.hue = 8
        sourceBlue.saturation = 12
        sourceBlue.luminance = 4
        before.colorMixer[.blue] = sourceBlue

        var after = before
        after.exposure = 1.25
        sourceBlue.saturation = 46
        after.colorMixer[.blue] = sourceBlue

        var target = PhotoAdjustments(
            exposure: -1,
            contrast: -65
        )
        var targetBlue = target.colorMixer[.blue]
        targetBlue.hue = -24
        targetBlue.saturation = -18
        targetBlue.luminance = 31
        target.colorMixer[.blue] = targetBlue

        let patched =
            PhotoAdjustmentSyncPlanner
                .applyingAutomaticChanges(
                    from: before,
                    to: after,
                    onto: target
                )

        XCTAssertEqual(patched.exposure, 1.25)
        XCTAssertEqual(patched.contrast, -65)
        XCTAssertEqual(
            patched.colorMixer[.blue].hue,
            -24
        )
        XCTAssertEqual(
            patched.colorMixer[.blue].saturation,
            46
        )
        XCTAssertEqual(
            patched.colorMixer[.blue].luminance,
            31
        )
    }

    func testAutomaticPatchAppliesNestedSliderChangesToTarget() {
        let point = PointColorAdjustment(
            sample: PointColorSample(
                hue: 215,
                saturation: 70,
                luminance: 45
            )
        )
        let mask = LocalAdjustmentMask(
            name: "Subject",
            kind: .radial,
            adjustments: .neutral
        )
        let spot = SpotRemoval(
            name: "Dust"
        )
        let before = PhotoAdjustments(
            pointColors: [point],
            localMasks: [mask],
            spotRemovals: [spot]
        )

        var after = before
        after.pointColors[0].hueShift = 28
        after.localMasks[0].feather = 0.22
        after.localMasks[0].adjustments.exposure =
            1.35
        after.spotRemovals[0].radius = 0.12
        after.toneCurve.midtones = 0.68
        after.crop = NormalizedCrop(
            x: 0.1,
            y: 0.05,
            width: 0.8,
            height: 0.9
        )

        var target = before
        target.contrast = 37
        target.toneCurve.black = 0.08
        let patched =
            PhotoAdjustmentSyncPlanner
                .applyingAutomaticChanges(
                    from: before,
                    to: after,
                    onto: target
                )

        XCTAssertEqual(
            patched.pointColors,
            after.pointColors
        )
        XCTAssertEqual(
            patched.localMasks,
            after.localMasks
        )
        XCTAssertEqual(
            patched.spotRemovals,
            after.spotRemovals
        )
        XCTAssertEqual(patched.crop, after.crop)
        XCTAssertEqual(
            patched.toneCurve.midtones,
            0.68
        )
        XCTAssertEqual(
            patched.toneCurve.black,
            0.08
        )
        XCTAssertEqual(patched.contrast, 37)
    }

    func testAutomaticPatchCopiesGuidedUprightWithoutReplacingFraming() {
        let guides = [
            GuidedUprightGuide(
                orientation: .vertical,
                startX: 0.2,
                startY: 0.1,
                endX: 0.16,
                endY: 0.9
            ),
            GuidedUprightGuide(
                orientation: .vertical,
                startX: 0.8,
                startY: 0.1,
                endX: 0.84,
                endY: 0.9
            ),
        ]
        let before = PhotoAdjustments.neutral
        let after = GuidedUprightSolver.applying(
            guides,
            to: before
        )
        var target = PhotoAdjustments.neutral
        target.geometry.scale = 128
        target.geometry.offsetX = 17

        let patched =
            PhotoAdjustmentSyncPlanner
                .applyingAutomaticChanges(
                    from: before,
                    to: after,
                    onto: target
                )

        XCTAssertEqual(
            patched.geometry.guidedUprightGuides,
            guides
        )
        XCTAssertEqual(
            patched.geometry.vertical,
            after.geometry.vertical
        )
        XCTAssertEqual(patched.geometry.scale, 128)
        XCTAssertEqual(patched.geometry.offsetX, 17)
    }

    func testAutomaticPatchCopiesAutoChromaticAnalysisWithoutReplacingManualOptics()
    {
        let before = PhotoAdjustments.neutral
        var after = before
        after.optics.automaticChromaticAberration =
            AutomaticChromaticAberrationCorrection(
                redCyanShift: 18,
                blueYellowShift: -12,
                purpleDefringe: 24,
                confidence: 0.72,
                sampledEdgeCount: 340
            )
        var target = PhotoAdjustments.neutral
        target.optics.distortion = 31
        target.optics.vignette = -14
        target.optics.redCyanShift = 7

        let patched =
            PhotoAdjustmentSyncPlanner
                .applyingAutomaticChanges(
                    from: before,
                    to: after,
                    onto: target
                )

        XCTAssertEqual(
            patched.optics
                .automaticChromaticAberration,
            after.optics
                .automaticChromaticAberration
        )
        XCTAssertEqual(patched.optics.distortion, 31)
        XCTAssertEqual(patched.optics.vignette, -14)
        XCTAssertEqual(
            patched.optics.redCyanShift,
            7
        )
    }
}

final class FilterStateTests: XCTestCase {
    private func makeAsset(format: FileFormat, name: String = "x.jpg",
                           rating: Int = 0, fav: Bool = false, flagged: Bool = false,
                           colorLabel: PhotoColorLabel = .none,
                           load: ImageLoadState = .idle) -> PhotoAsset {
        PhotoAsset(
            id: name, url: URL(fileURLWithPath: "/tmp/\(name)"),
            path: "/tmp/\(name)", filename: name, fileExtension: "x",
            fileSize: 1, creationDate: nil, modificationDate: nil,
            format: format, loadState: load, metadata: nil,
            userState: PhotoUserState(
                rating: rating,
                flagged: flagged,
                favorite: fav,
                colorLabel: colorLabel
            )
        )
    }

    func testAllPasses() {
        let s = FilterState()
        XCTAssertTrue(s.matches(makeAsset(format: .jpeg)))
        XCTAssertFalse(s.isActive)
    }

    func testRawOnly() {
        let s = FilterState(primary: .rawOnly)
        XCTAssertTrue(s.matches(makeAsset(format: .sonyARW)))
        XCTAssertFalse(s.matches(makeAsset(format: .jpeg)))
    }

    func testARWOnly() {
        let s = FilterState(primary: .sonyARWOnly)
        XCTAssertTrue(s.matches(makeAsset(format: .sonyARW)))
        XCTAssertFalse(s.matches(makeAsset(format: .canonCR2)))
    }

    func testCR2Only() {
        let s = FilterState(primary: .canonCR2Only)
        XCTAssertTrue(s.matches(makeAsset(format: .canonCR2)))
        XCTAssertFalse(s.matches(makeAsset(format: .dng)))
    }

    func testFavorites() {
        let s = FilterState(primary: .favoritesOnly)
        XCTAssertTrue(s.matches(makeAsset(format: .jpeg, fav: true)))
        XCTAssertFalse(s.matches(makeAsset(format: .jpeg, fav: false)))
    }

    func testRejected() {
        let rejected = PhotoAsset(
            id: "rejected",
            url: URL(fileURLWithPath: "/tmp/rejected.jpg"),
            path: "/tmp/rejected.jpg",
            filename: "rejected.jpg",
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg,
            userState: PhotoUserState(rejected: true)
        )
        let picked = PhotoAsset(
            id: "picked",
            url: URL(fileURLWithPath: "/tmp/picked.jpg"),
            path: "/tmp/picked.jpg",
            filename: "picked.jpg",
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg,
            userState: PhotoUserState(flagged: true)
        )
        let filter = FilterState(primary: .rejectedOnly)
        XCTAssertTrue(filter.matches(rejected))
        XCTAssertFalse(filter.matches(picked))
    }

    func testRating() {
        let s = FilterState(minimumRating: 3)
        XCTAssertTrue(s.matches(makeAsset(format: .jpeg, rating: 4)))
        XCTAssertFalse(s.matches(makeAsset(format: .jpeg, rating: 2)))
    }

    func testErrorsOnly() {
        let s = FilterState(primary: .errorsOnly)
        XCTAssertTrue(s.matches(makeAsset(format: .sonyARW, load: .unsupported(reason: "x"))))
        XCTAssertTrue(s.matches(makeAsset(format: .sonyARW, load: .failed(reason: "x"))))
        XCTAssertFalse(s.matches(makeAsset(format: .jpeg, load: .loaded)))
    }

    func testSearch() {
        let s = FilterState(searchText: "BEACH")
        XCTAssertTrue(s.matches(makeAsset(format: .jpeg, name: "beach-01.jpg")))
        XCTAssertFalse(s.matches(makeAsset(format: .jpeg, name: "city.jpg")))
    }

    func testSearchIncludesKeywordsNotesAndCameraMetadata() {
        let asset = PhotoAsset(
            id: "metadata-search",
            url: URL(fileURLWithPath: "/tmp/plain.jpg"),
            path: "/tmp/plain.jpg",
            filename: "plain.jpg",
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg,
            metadata: PhotoMetadata(
                cameraModel: "Leica Q3",
                lensModel: "Summilux 28"
            ),
            userState: PhotoUserState(
                note: "Client selects",
                keywords: ["Tokyo", "Night Street"]
            )
        )

        XCTAssertTrue(FilterState(searchText: "tokyo").matches(asset))
        XCTAssertTrue(FilterState(searchText: "CLIENT").matches(asset))
        XCTAssertTrue(FilterState(searchText: "leica").matches(asset))
        XCTAssertTrue(FilterState(searchText: "summilux").matches(asset))
        XCTAssertFalse(FilterState(searchText: "beach").matches(asset))
    }

    func testKeywordFilterIsCaseAndDiacriticInsensitive() {
        let asset = PhotoAsset(
            id: "keyword-filter",
            url: URL(fileURLWithPath: "/tmp/plain.jpg"),
            path: "/tmp/plain.jpg",
            filename: "plain.jpg",
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg,
            userState: PhotoUserState(keywords: ["Café"])
        )
        XCTAssertTrue(FilterState(keyword: "CAFE").matches(asset))
        XCTAssertFalse(FilterState(keyword: "Tokyo").matches(asset))
    }

    func testHierarchicalKeywordSearchAndParentFilter() {
        let asset = PhotoAsset(
            id: "hierarchical-keyword",
            url: URL(fileURLWithPath: "/tmp/plain.jpg"),
            path: "/tmp/plain.jpg",
            filename: "plain.jpg",
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg,
            userState: PhotoUserState(
                keywords: ["Places > Japan > Tokyo"]
            )
        )

        XCTAssertEqual(
            asset.userState.keywords,
            ["Places|Japan|Tokyo"]
        )
        XCTAssertTrue(FilterState(searchText: "japan").matches(asset))
        XCTAssertTrue(
            FilterState(keyword: "Places|Japan").matches(asset)
        )
        XCTAssertTrue(FilterState(keyword: "TOKYO").matches(asset))
        XCTAssertFalse(
            FilterState(keyword: "Places|France").matches(asset)
        )
    }

    func testColorLabelFilterCombinesMultipleLabelsAndOtherCriteria()
        throws
    {
        let red = makeAsset(
            format: .jpeg,
            name: "red.jpg",
            rating: 4,
            colorLabel: .red
        )
        let green = makeAsset(
            format: .jpeg,
            name: "green.jpg",
            rating: 5,
            colorLabel: .green
        )
        let blue = makeAsset(
            format: .jpeg,
            name: "blue.jpg",
            rating: 5,
            colorLabel: .blue
        )
        let unlabeled = makeAsset(
            format: .jpeg,
            name: "plain.jpg",
            rating: 5
        )
        let filter = FilterState(
            searchText: ".jpg",
            minimumRating: 4,
            colorLabels: [.red, .green]
        )

        XCTAssertTrue(filter.isActive)
        XCTAssertTrue(filter.matches(red))
        XCTAssertTrue(filter.matches(green))
        XCTAssertFalse(filter.matches(blue))
        XCTAssertFalse(filter.matches(unlabeled))
        XCTAssertTrue(
            FilterState(colorLabels: [.none]).matches(unlabeled)
        )
        XCTAssertFalse(
            FilterState(colorLabels: [.none]).matches(red)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                FilterState.self,
                from: JSONEncoder().encode(filter)
            ),
            filter
        )
    }

    func testLegacyFilterAndPhotoStateDefaultToNoColorConstraint()
        throws
    {
        let filterJSON = """
        {
          "searchText": "",
          "primary": "all",
          "minimumRating": 0
        }
        """
        let stateJSON = """
        {
          "rating": 3,
          "flagged": false,
          "favorite": false,
          "note": ""
        }
        """

        let filter = try JSONDecoder().decode(
            FilterState.self,
            from: Data(filterJSON.utf8)
        )
        let state = try JSONDecoder().decode(
            PhotoUserState.self,
            from: Data(stateJSON.utf8)
        )
        XCTAssertTrue(filter.colorLabels.isEmpty)
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(state.colorLabel, .none)
    }
}

final class ImageTransformStateTests: XCTestCase {
    func testRotateRightWraps() {
        var t = ImageTransformState()
        t.rotateRight(); XCTAssertEqual(t.rotationDegrees, 90)
        t.rotateRight(); XCTAssertEqual(t.rotationDegrees, 180)
        t.rotateRight(); XCTAssertEqual(t.rotationDegrees, 270)
        t.rotateRight(); XCTAssertEqual(t.rotationDegrees, 0)
    }

    func testRotateLeftWraps() {
        var t = ImageTransformState()
        t.rotateLeft(); XCTAssertEqual(t.rotationDegrees, 270)
        t.rotateLeft(); XCTAssertEqual(t.rotationDegrees, 180)
    }

    func testZoom() {
        var t = ImageTransformState()
        t.zoomIn()
        XCTAssertFalse(t.fitToWindow)
        XCTAssertGreaterThan(t.zoom, 1.0)
        t.fit()
        XCTAssertTrue(t.fitToWindow)
        XCTAssertEqual(t.zoom, 1.0)
    }
}

final class PhotoColorLabelSetTests: XCTestCase {
    func testCustomSetMatchesMetadataNamesAndValidatesUniqueness() {
        var set = PhotoColorLabelSet(
            name: "Client Delivery",
            red: "Needs Retouch",
            yellow: "Hold",
            green: "Deliver",
            blue: "Portfolio",
            purple: "Archive"
        )

        XCTAssertNil(set.validationMessage)
        XCTAssertEqual(
            set.color(matchingMetadataValue: "  DÉLIVER "),
            .green
        )
        XCTAssertEqual(set[.red], "Needs Retouch")
        XCTAssertEqual(set[.none], "Unlabeled")

        set.blue = "deliver"
        XCTAssertEqual(
            set.validationMessage,
            "Each color needs a unique label name."
        )
        set.blue = "   "
        XCTAssertEqual(
            set.validationMessage,
            "Every color needs a label name."
        )
    }

    func testAssignedMetadataNamePersistsAndExplicitClearRemovesIt()
        throws
    {
        var state = PhotoUserState()
        state.assignColorLabel(
            .green,
            metadataValue: "Client Select"
        )
        XCTAssertEqual(state.colorLabel, .green)
        XCTAssertEqual(
            state.colorLabelMetadataValue,
            "Client Select"
        )

        let roundTrip = try JSONDecoder().decode(
            PhotoUserState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(roundTrip, state)

        state.assignColorLabel(.none)
        XCTAssertEqual(state.colorLabel, .none)
        XCTAssertNil(state.colorLabelMetadataValue)

        let legacy = try JSONDecoder().decode(
            PhotoUserState.self,
            from: Data(
                """
                {
                  "rating": 0,
                  "flagged": false,
                  "rejected": false,
                  "favorite": false,
                  "colorLabel": "purple",
                  "note": "",
                  "keywords": [],
                  "adjustments": {},
                  "versions": []
                }
                """.utf8
            )
        )
        XCTAssertEqual(legacy.colorLabel, .purple)
        XCTAssertEqual(
            legacy.colorLabelMetadataValue,
            "Purple"
        )
    }

    func testPresetLibraryPersistsActiveSet() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-label-sets-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let custom = PhotoColorLabelSet(
            name: "Wedding",
            red: "Remove",
            yellow: "Maybe",
            green: "Album",
            blue: "Vendor",
            purple: "Personal"
        )
        let first = PhotoColorLabelSetStore(directory: directory)
        first.save(
            PhotoColorLabelSetLibrary(
                activeSetID: custom.id,
                sets: [.standard, custom]
            )
        )

        let reopened = PhotoColorLabelSetStore(
            directory: directory
        ).load()
        XCTAssertEqual(reopened.activeSetID, custom.id)
        XCTAssertEqual(reopened.sets, [.standard, custom])
        XCTAssertEqual(reopened.activeSet.green, "Album")
    }
}

@MainActor
final class KeyboardHandlerTests: XCTestCase {
    func testSpaceReturnAndKeypadEnterToggleLibraryLoupe() {
        XCTAssertTrue(
            KeyboardHandler.MonitorView
                .isLoupeToggleKeyCode(49)
        )
        XCTAssertTrue(
            KeyboardHandler.MonitorView
                .isLoupeToggleKeyCode(36)
        )
        XCTAssertTrue(
            KeyboardHandler.MonitorView
                .isLoupeToggleKeyCode(76)
        )
        XCTAssertFalse(
            KeyboardHandler.MonitorView
                .isLoupeToggleKeyCode(48)
        )
        XCTAssertTrue(
            KeyboardHandler.MonitorView
                .shouldHandleLoupeToggle(
                    keyCode: 49,
                    canToggleLoupe: true
                )
        )
        XCTAssertFalse(
            KeyboardHandler.MonitorView
                .shouldHandleLoupeToggle(
                    keyCode: 49,
                    canToggleLoupe: false
                )
        )

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 320,
                height: 120
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let button = NSButton(
            title: "Done",
            target: nil,
            action: nil
        )
        window.contentView = button
        XCTAssertTrue(
            window.makeFirstResponder(button)
        )
        XCTAssertTrue(
            KeyboardHandler.MonitorView
                .isActivatingControl(in: window)
        )
    }

    func testPhotoShortcutsYieldToTextEditingInAnotherWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let content = NSView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 120)
        )
        let field = NSTextField(
            frame: NSRect(x: 20, y: 40, width: 220, height: 24)
        )
        content.addSubview(field)
        window.contentView = content

        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(
            KeyboardHandler.MonitorView.isEditingText(in: window)
        )

        XCTAssertTrue(window.makeFirstResponder(content))
        XCTAssertFalse(
            KeyboardHandler.MonitorView.isEditingText(in: window)
        )
    }

    func testPhotoNavigationYieldsToFocusedSlider() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 320,
                height: 120
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let slider = NSSlider(
            value: 0.5,
            minValue: 0,
            maxValue: 1,
            target: nil,
            action: nil
        )
        window.contentView = slider

        XCTAssertTrue(window.makeFirstResponder(slider))
        XCTAssertTrue(
            KeyboardHandler.MonitorView
                .isAdjustingValue(in: window)
        )
    }
}

final class UserStateStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let storeA = UserStateStore(directory: tmp)
        storeA.set(
            id: "abc",
            state: PhotoUserState(
                rating: 4,
                flagged: true,
                favorite: true,
                note: "ok",
                adjustments: PhotoAdjustments(exposure: 1.25, shadows: 35, vibrance: 12),
                versions: [
                    EditVersion(
                        name: "Warm",
                        adjustments: PhotoAdjustments(temperature: 12),
                        softProofSettings:
                            SoftProofSettings(
                                isEnabled: true,
                                profile: .genericCMYK,
                                renderingIntent:
                                    .relativeColorimetric,
                                showDestinationGamutWarning:
                                    true,
                                showMonitorGamutWarning:
                                    true,
                                simulatePaperAndInk:
                                    true
                            )
                    )
                ]
            )
        )

        let storeB = UserStateStore(directory: tmp)
        let s = storeB.get(id: "abc")
        XCTAssertEqual(s.rating, 4)
        XCTAssertTrue(s.flagged)
        XCTAssertTrue(s.favorite)
        XCTAssertEqual(s.note, "ok")
        XCTAssertEqual(s.adjustments.exposure, 1.25)
        XCTAssertEqual(s.adjustments.shadows, 35)
        XCTAssertEqual(s.adjustments.vibrance, 12)
        XCTAssertEqual(s.versions.count, 1)
        XCTAssertEqual(s.versions.first?.name, "Warm")
        XCTAssertEqual(s.versions.first?.adjustments.temperature, 12)
        XCTAssertEqual(
            s.versions.first?.softProofSettings,
            SoftProofSettings(
                isEnabled: true,
                profile: .genericCMYK,
                renderingIntent:
                    .relativeColorimetric,
                showDestinationGamutWarning: true,
                showMonitorGamutWarning: true,
                simulatePaperAndInk: true
            )
        )
    }

    func testCorruptJSONFallsBack() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try Data("not json".utf8).write(to: tmp.appendingPathComponent("user_state.json"))
        let store = UserStateStore(directory: tmp)
        let all = store.loadAll()
        XCTAssertTrue(all.isEmpty)
    }

    func testBatchSetPersistsAllStatesInOneMirrorUpdate() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-batch-state-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: tmp,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = UserStateStore(directory: tmp)
        store.set(
            id: "unchanged",
            state: PhotoUserState(note: "preserve")
        )
        store.set(statesByID: [
            "first": PhotoUserState(
                rating: 5,
                keywords: ["Places > Japan"]
            ),
            "second": PhotoUserState(
                flagged: true,
                keywords: ["People > Family"]
            ),
        ])

        let reopened = UserStateStore(directory: tmp).loadAll()
        XCTAssertEqual(reopened["unchanged"]?.note, "preserve")
        XCTAssertEqual(reopened["first"]?.rating, 5)
        XCTAssertEqual(
            reopened["first"]?.keywords,
            ["Places|Japan"]
        )
        XCTAssertEqual(reopened["second"]?.pickStatus, .picked)
    }
}

final class PhotoLocationTests: XCTestCase {
    func testValidationAndEffectiveLocationPrecedence() throws {
        XCTAssertNil(
            PhotoLocation(latitude: 91, longitude: 0)
        )
        XCTAssertNil(
            PhotoLocation(latitude: 0, longitude: -181)
        )
        XCTAssertNil(
            PhotoLocation(
                latitude: .infinity,
                longitude: 0
            )
        )

        let embedded = try XCTUnwrap(
            PhotoLocation(
                latitude: 35.681236,
                longitude: 139.767125,
                altitude: 12
            )
        )
        let manual = try XCTUnwrap(
            PhotoLocation(
                latitude: 34.693725,
                longitude: 135.502254
            )
        )
        var state = PhotoUserState()
        XCTAssertEqual(
            state.effectiveLocation(embedded: embedded),
            embedded
        )
        XCTAssertEqual(
            state.locationSource(embedded: embedded),
            .embedded
        )

        state.setLocation(manual)
        XCTAssertEqual(
            state.effectiveLocation(embedded: embedded),
            manual
        )
        XCTAssertEqual(
            state.locationSource(embedded: embedded),
            .manual
        )

        state.removeLocation()
        XCTAssertNil(state.effectiveLocation(embedded: embedded))
        XCTAssertEqual(
            state.locationSource(embedded: embedded),
            .removed
        )

        state.useEmbeddedLocation()
        XCTAssertEqual(
            state.effectiveLocation(embedded: embedded),
            embedded
        )
    }

    func testLocationStateRoundTripsAndLegacyStateDefaultsToInherit()
        throws
    {
        let location = try XCTUnwrap(
            PhotoLocation(
                latitude: -33.86882,
                longitude: 151.209296,
                altitude: 58.5
            )
        )
        let state = PhotoUserState(
            rating: 4,
            locationOverride: location
        )
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(
            try JSONDecoder().decode(
                PhotoUserState.self,
                from: data
            ),
            state
        )

        let legacy = try JSONDecoder().decode(
            PhotoUserState.self,
            from: Data(
                """
                {
                  "rating": 2,
                  "flagged": false,
                  "favorite": false,
                  "note": "",
                  "versions": []
                }
                """.utf8
            )
        )
        XCTAssertNil(legacy.locationOverride)
        XCTAssertFalse(legacy.locationIsRemoved)
    }
}

final class SavedMapLocationTests: XCTestCase {
    func testContainmentPrivacyAndStoreRoundTrip() throws {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-saved-map-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let center = try XCTUnwrap(
            PhotoLocation(
                latitude: 35.681236,
                longitude: 139.767125
            )
        )
        let nearby = try XCTUnwrap(
            PhotoLocation(
                latitude: 35.682,
                longitude: 139.767
            )
        )
        let distant = try XCTUnwrap(
            PhotoLocation(
                latitude: 35.71,
                longitude: 139.81
            )
        )
        let location = SavedMapLocation(
            name: "  Client   Studio  ",
            folder: " Work ",
            center: center,
            radiusMeters: 500,
            isPrivate: true
        )
        XCTAssertEqual(location.name, "Client Studio")
        XCTAssertEqual(location.folder, "Work")
        XCTAssertTrue(location.contains(nearby))
        XCTAssertFalse(location.contains(distant))
        XCTAssertTrue(location.isPrivate)

        SavedMapLocationStore(directory: directory).save(
            SavedMapLocationLibrary(
                locations: [location]
            )
        )
        let restored = SavedMapLocationStore(
            directory: directory
        ).load()
        XCTAssertEqual(restored.locations, [location])
    }
}

final class GPXTracklogTests: XCTestCase {
    func testParserReadsSortsAndValidatesTimedTrackPoints()
        throws
    {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="RAWDesk Test"
             xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>Route</name><trkseg>
            <trkpt lat="35.2" lon="139.2">
              <ele>20.5</ele>
              <time>2026-07-26T00:00:10Z</time>
            </trkpt>
            <trkpt lat="35.0" lon="139.0">
              <ele>10</ele>
              <time>2026-07-26T00:00:00.500Z</time>
            </trkpt>
            <trkpt lat="999" lon="0">
              <time>2026-07-26T00:00:05Z</time>
            </trkpt>
            <trkpt lat="35.1" lon="139.1"/>
          </trkseg></trk>
        </gpx>
        """
        let tracklog = try GPXTracklogParser.parse(
            data: Data(xml.utf8),
            name: "Morning Route"
        )
        XCTAssertEqual(tracklog.name, "Morning Route")
        XCTAssertEqual(tracklog.points.count, 2)
        XCTAssertLessThan(
            tracklog.points[0].timestamp,
            tracklog.points[1].timestamp
        )
        XCTAssertEqual(
            tracklog.points[0].location.altitude,
            10
        )
        XCTAssertEqual(
            tracklog.points[1].location.latitude,
            35.2
        )
    }

    func testInterpolationHandlesOffsetAltitudeAndDateline()
        throws
    {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = GPXTrackPoint(
            timestamp: start,
            location: try XCTUnwrap(
                PhotoLocation(
                    latitude: 10,
                    longitude: 179,
                    altitude: 100
                )
            )
        )
        let second = GPXTrackPoint(
            timestamp: start.addingTimeInterval(10),
            location: try XCTUnwrap(
                PhotoLocation(
                    latitude: 20,
                    longitude: -179,
                    altitude: 200
                )
            )
        )
        let tracklog = GPXTracklog(
            name: "Dateline",
            points: [first, second]
        )
        let location = try XCTUnwrap(
            tracklog.location(
                atCameraTime:
                    start.addingTimeInterval(3_605),
                settings: GPXMatchSettings(
                    tracklogOffset: 3_600,
                    maximumPointGap: 60
                )
            )
        )
        XCTAssertEqual(location.latitude, 15, accuracy: 0.000_001)
        XCTAssertEqual(abs(location.longitude), 180, accuracy: 0.000_001)
        XCTAssertEqual(
            try XCTUnwrap(location.altitude),
            150,
            accuracy: 0.000_001
        )
    }

    func testAutoTagPreviewExplainsSkippedPhotos() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let tracklog = GPXTracklog(
            name: "Preview",
            points: [
                GPXTrackPoint(
                    timestamp: start,
                    location: try XCTUnwrap(
                        PhotoLocation(
                            latitude: 35,
                            longitude: 139
                        )
                    )
                ),
                GPXTrackPoint(
                    timestamp:
                        start.addingTimeInterval(60),
                    location: try XCTUnwrap(
                        PhotoLocation(
                            latitude: 35.01,
                            longitude: 139.01
                        )
                    )
                ),
            ]
        )
        func asset(
            _ id: String,
            date: Date?,
            hasLocation: Bool = false
        ) -> PhotoAsset {
            PhotoAsset(
                id: id,
                url: URL(fileURLWithPath: "/tmp/\(id).jpg"),
                path: "/tmp/\(id).jpg",
                filename: "\(id).jpg",
                fileExtension: "jpg",
                fileSize: 1,
                creationDate: nil,
                modificationDate: nil,
                format: .jpeg,
                metadata: PhotoMetadata(captureDate: date),
                userState: PhotoUserState(
                    locationOverride:
                        hasLocation
                        ? PhotoLocation(
                            latitude: 1,
                            longitude: 1
                        )
                        : nil
                )
            )
        }
        let preview = GPXAutoTagPreview.make(
            tracklog: tracklog,
            assets: [
                asset(
                    "match",
                    date: start.addingTimeInterval(30)
                ),
                asset("existing", date: start, hasLocation: true),
                asset("no-date", date: nil),
                asset(
                    "outside",
                    date: start.addingTimeInterval(10_000)
                ),
            ],
            settings: GPXMatchSettings(
                maximumPointGap: 120
            )
        )
        XCTAssertEqual(preview.matchedCount, 1)
        XCTAssertEqual(preview.skippedExistingCount, 1)
        XCTAssertEqual(preview.missingCaptureDateCount, 1)
        XCTAssertEqual(preview.outsideTrackCount, 1)
        XCTAssertNotNil(
            preview.locationsByPhotoID["match"]
        )
    }
}

final class CatalogStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-catalog-\(UUID().uuidString)",
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
        state: PhotoUserState,
        metadata: PhotoMetadata? = nil
    ) -> PhotoAsset {
        PhotoAsset(
            id: id,
            url: url,
            path: url.path,
            filename: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSize: 4,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            modificationDate: Date(timeIntervalSince1970: 1_700_000_100),
            format: .jpeg,
            metadata: metadata,
            userState: state
        )
    }

    func testCatalogPersistsExactStateMetadataAndSmartCollections() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let firstURL = root.appendingPathComponent("first.jpg")
        let secondURL = root.appendingPathComponent("second.jpg")
        let thirdURL = root.appendingPathComponent("third.jpg")
        for url in [firstURL, secondURL, thirdURL] {
            try Data([1, 2, 3, 4]).write(to: url)
        }

        let firstState = PhotoUserState(
            rating: 5,
            flagged: true,
            colorLabel: .green,
            note: "hero",
            keywords: ["Tokyo", "Night"],
            adjustments: PhotoAdjustments(exposure: 1.25)
        )
        let secondState = PhotoUserState(
            rejected: true,
            colorLabel: .red
        )
        let thirdState = PhotoUserState(keywords: ["Portrait"])
        let firstMetadata = PhotoMetadata(
            pixelWidth: 6_000,
            pixelHeight: 4_000,
            cameraMake: "Canon",
            cameraModel: "Canon EOS R5",
            lensModel: "RF50mm F1.2 L USM",
            captureDate: Date(timeIntervalSince1970: 1_699_999_000)
        )
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [
                makeAsset(
                    id: "first",
                    url: firstURL,
                    state: firstState,
                    metadata: firstMetadata
                ),
                makeAsset(
                    id: "second",
                    url: secondURL,
                    state: secondState
                ),
                makeAsset(
                    id: "third",
                    url: thirdURL,
                    state: thirdState
                ),
            ],
            rootURL: root,
            recursive: true
        )

        let summary = try store.summary()
        XCTAssertEqual(summary[.allPhotos], 3)
        XCTAssertEqual(summary[.recentlyAdded], 3)
        XCTAssertEqual(summary[.edited], 1)
        XCTAssertEqual(summary[.fiveStars], 1)
        XCTAssertEqual(summary[.picked], 1)
        XCTAssertEqual(summary[.rejected], 1)
        XCTAssertEqual(summary[.withKeywords], 2)
        XCTAssertEqual(summary[.missingFiles], 0)
        XCTAssertEqual(summary.keywordCounts["Tokyo"], 1)
        XCTAssertEqual(summary.keywordCounts["Night"], 1)
        XCTAssertEqual(summary.keywordCounts["Portrait"], 1)
        XCTAssertEqual(summary.colorLabelCounts[.green], 1)
        XCTAssertEqual(summary.colorLabelCounts[.red], 1)
        XCTAssertEqual(summary.colorLabelCounts[.none], 1)
        XCTAssertEqual(summary.rootCount, 1)
        XCTAssertTrue(try store.integrityCheck())

        let reopened = CatalogStore(directory: directory)
        let entries = try reopened.entries(for: .allPhotos)
        let first = try XCTUnwrap(entries.first(where: { $0.id == "first" }))
        XCTAssertEqual(first.userState, firstState)
        XCTAssertEqual(first.metadata, firstMetadata)
        XCTAssertEqual(first.asset.userState.keywords, ["Tokyo", "Night"])
        XCTAssertFalse(first.isMissing)
        XCTAssertEqual(
            try reopened.userStates(rootPath: root.path)["first"],
            firstState
        )
    }

    func testLocationCollectionsFollowEmbeddedManualAndRemovedGPS()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let embedded = try XCTUnwrap(
            PhotoLocation(
                latitude: 35.681236,
                longitude: 139.767125,
                altitude: 10
            )
        )
        let manual = try XCTUnwrap(
            PhotoLocation(
                latitude: 34.693725,
                longitude: 135.502254
            )
        )
        let urls = (0..<4).map {
            root.appendingPathComponent("\($0).jpg")
        }
        for url in urls {
            try Data([1, 2, 3, 4]).write(to: url)
        }
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [
                makeAsset(
                    id: "embedded",
                    url: urls[0],
                    state: .empty,
                    metadata: PhotoMetadata(
                        readerVersion:
                            MetadataReader.currentReaderVersion,
                        location: embedded
                    )
                ),
                makeAsset(
                    id: "manual",
                    url: urls[1],
                    state: PhotoUserState(
                        locationOverride: manual
                    ),
                    metadata: PhotoMetadata(location: embedded)
                ),
                makeAsset(
                    id: "removed",
                    url: urls[2],
                    state: PhotoUserState(
                        locationIsRemoved: true
                    ),
                    metadata: PhotoMetadata(location: embedded)
                ),
                makeAsset(
                    id: "none",
                    url: urls[3],
                    state: .empty
                ),
            ],
            rootURL: root,
            recursive: false
        )

        XCTAssertEqual(try store.summary()[.withLocation], 2)
        XCTAssertEqual(try store.summary()[.withoutLocation], 2)
        XCTAssertEqual(
            Set(try store.entries(for: .withLocation).map(\.id)),
            ["embedded", "manual"]
        )
        XCTAssertEqual(
            Set(try store.entries(for: .withoutLocation).map(\.id)),
            ["removed", "none"]
        )

        try store.updateUserState(
            id: "embedded",
            state: PhotoUserState(locationIsRemoved: true)
        )
        XCTAssertEqual(try store.summary()[.withLocation], 1)

        try store.updateMetadata(
            id: "none",
            metadata: PhotoMetadata(
                readerVersion:
                    MetadataReader.currentReaderVersion,
                location: embedded
            )
        )
        XCTAssertEqual(try store.summary()[.withLocation], 2)

        let reopened = CatalogStore(directory: directory)
        XCTAssertEqual(try reopened.summary()[.withLocation], 2)
        XCTAssertEqual(try reopened.summary()[.withoutLocation], 2)
    }

    func testSchemaSevenMigratesAndBackfillsLocationIndex()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("legacy-location.jpg")
        try Data([1, 2, 3, 4]).write(to: url)
        let location = try XCTUnwrap(
            PhotoLocation(
                latitude: 51.507222,
                longitude: -0.1275
            )
        )

        var initialStore: CatalogStore? = CatalogStore(
            directory: directory
        )
        try initialStore?.upsert(
            assets: [
                makeAsset(
                    id: "legacy-location",
                    url: url,
                    state: PhotoUserState(
                        locationOverride: location
                    )
                ),
            ],
            rootURL: root,
            recursive: false
        )
        initialStore = nil

        let databaseURL = directory.appendingPathComponent(
            "catalog.sqlite"
        )
        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READWRITE,
                nil
            ),
            SQLITE_OK
        )
        func execute(_ sql: String) throws {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(
                database,
                sql,
                nil,
                nil,
                &errorMessage
            )
            defer {
                if let errorMessage {
                    sqlite3_free(errorMessage)
                }
            }
            guard result == SQLITE_OK else {
                throw NSError(
                    domain: "CatalogLocationMigrationTest",
                    code: Int(result),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            errorMessage.map {
                                String(cString: $0)
                            } ?? "SQLite error",
                    ]
                )
            }
        }
        try execute(
            "DROP INDEX IF EXISTS catalog_photos_location"
        )
        try execute(
            "ALTER TABLE catalog_photos DROP COLUMN latitude"
        )
        try execute(
            "ALTER TABLE catalog_photos DROP COLUMN longitude"
        )
        try execute(
            "ALTER TABLE catalog_photos DROP COLUMN altitude"
        )
        try execute(
            "ALTER TABLE catalog_photos DROP COLUMN location_source"
        )
        try execute("PRAGMA user_version = 7")
        sqlite3_close_v2(database)
        database = nil

        let migrated = CatalogStore(directory: directory)
        XCTAssertTrue(try migrated.integrityCheck())
        XCTAssertEqual(try migrated.summary()[.withLocation], 1)
        XCTAssertEqual(
            try migrated.entries(for: .withLocation).first?.id,
            "legacy-location"
        )

        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READONLY,
                nil
            ),
            SQLITE_OK
        )
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
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
        statement = nil
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT COUNT(*)
                FROM pragma_table_info('catalog_photos')
                WHERE name = 'image_content_hash'
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
        sqlite3_finalize(statement)
        statement = nil
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'table'
                    AND name = 'catalog_quick_collection'
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
        sqlite3_finalize(statement)
        statement = nil
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'table'
                    AND name IN (
                        'catalog_collection_sets',
                        'catalog_collections',
                        'catalog_collection_members'
                    )
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 3)
        sqlite3_finalize(statement)
        statement = nil
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT COUNT(*)
                FROM pragma_table_info(
                    'catalog_smart_collections'
                )
                WHERE name = 'parent_set_id'
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
        sqlite3_finalize(statement)
        sqlite3_close_v2(database)
    }

    func testSchemaSixMigratesColorLabelIndexAndBackfillsState()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("legacy.jpg")
        try Data([1, 2, 3, 4]).write(to: url)

        var initialStore: CatalogStore? = CatalogStore(
            directory: directory
        )
        try initialStore?.upsert(
            assets: [
                makeAsset(
                    id: "legacy",
                    url: url,
                    state: PhotoUserState(colorLabel: .purple)
                ),
            ],
            rootURL: root,
            recursive: false
        )
        initialStore = nil

        let databaseURL = directory.appendingPathComponent(
            "catalog.sqlite"
        )
        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READWRITE,
                nil
            ),
            SQLITE_OK
        )
        func execute(_ sql: String) throws {
            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(
                database,
                sql,
                nil,
                nil,
                &errorMessage
            )
            defer {
                if let errorMessage {
                    sqlite3_free(errorMessage)
                }
            }
            guard result == SQLITE_OK else {
                throw NSError(
                    domain: "CatalogMigrationTest",
                    code: Int(result),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            errorMessage.map {
                                String(cString: $0)
                            } ?? "SQLite error",
                    ]
                )
            }
        }
        try execute(
            "DROP INDEX IF EXISTS catalog_photos_color_label"
        )
        try execute(
            "ALTER TABLE catalog_photos DROP COLUMN color_label"
        )
        try execute("PRAGMA user_version = 6")
        sqlite3_close_v2(database)
        database = nil

        let migrated = CatalogStore(directory: directory)
        XCTAssertTrue(try migrated.integrityCheck())
        XCTAssertEqual(
            try migrated.entries(for: .allPhotos)
                .first?.userState.colorLabel,
            .purple
        )
        XCTAssertEqual(
            try migrated.summary().colorLabelCounts[.purple],
            1
        )

        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READONLY,
                nil
            ),
            SQLITE_OK
        )
        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
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

        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT color_label
                FROM catalog_photos
                WHERE id = 'legacy'
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(
            sqlite3_column_text(statement, 0).map {
                String(cString: $0)
            },
            "purple"
        )
        sqlite3_finalize(statement)

        XCTAssertEqual(
            sqlite3_prepare_v2(
                database,
                """
                SELECT COUNT(*)
                FROM sqlite_master
                WHERE type = 'index'
                    AND name = 'catalog_photos_color_label'
                """,
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
        sqlite3_finalize(statement)
        sqlite3_close_v2(database)
    }

    func testCatalogUpdatesKeywordsAndTracksMissingFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("photo.jpg")
        try Data([1]).write(to: url)
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [
                makeAsset(
                    id: "photo",
                    url: url,
                    state: .empty
                ),
            ],
            rootURL: root,
            recursive: true
        )

        var state = PhotoUserState(
            rating: 5,
            keywords: ["Café", "Tokyo"],
            adjustments: PhotoAdjustments(contrast: 12)
        )
        try store.updateUserState(id: "photo", state: state)
        var summary = try store.summary()
        XCTAssertEqual(summary[.fiveStars], 1)
        XCTAssertEqual(summary[.edited], 1)
        XCTAssertEqual(summary[.withKeywords], 1)
        XCTAssertEqual(summary.keywordCounts["Café"], 1)

        state.keywords = ["Tokyo"]
        try store.updateUserState(id: "photo", state: state)
        summary = try store.summary()
        XCTAssertNil(summary.keywordCounts["Café"])
        XCTAssertEqual(summary.keywordCounts["Tokyo"], 1)

        try FileManager.default.removeItem(at: url)
        try store.refreshMissingStatus()
        summary = try store.summary()
        XCTAssertEqual(summary[.allPhotos], 0)
        XCTAssertEqual(summary[.missingFiles], 1)
        XCTAssertEqual(summary.keywordCounts["Tokyo"], 1)
        let missing = try XCTUnwrap(
            store.entries(for: .missingFiles).first
        )
        XCTAssertTrue(missing.isMissing)
        if case .failed = missing.asset.loadState {
            // Expected.
        } else {
            XCTFail("Missing catalog entries must expose a failed load state.")
        }
    }

    func testCorruptCatalogIsBackedUpAndRecreated() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a sqlite database".utf8).write(
            to: directory.appendingPathComponent("catalog.sqlite")
        )

        let store = CatalogStore(directory: directory)
        XCTAssertNotNil(store.startupWarning)
        XCTAssertTrue(try store.integrityCheck())
        let backups = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.contains("catalog.sqlite.corrupt.")
        }
        XCTAssertEqual(backups.count, 1)
    }

    func testSavedSmartCollectionsPersistAndDelete() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CatalogStore(directory: directory)
        let collection = SavedSmartCollection(
            name: "Tokyo picks",
            filter: FilterState(
                searchText: "night",
                primary: .rawOnly,
                minimumRating: 3,
                keyword: "Tokyo"
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.saveSmartCollection(collection)

        let reopened = CatalogStore(directory: directory)
        XCTAssertEqual(
            try reopened.savedSmartCollections(),
            [collection]
        )
        try reopened.deleteSmartCollection(id: collection.id)
        XCTAssertTrue(try reopened.savedSmartCollections().isEmpty)
    }

    func testQuickCollectionPersistsOrderRelinkAndCatalogRemoval()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let firstURL = root.appendingPathComponent("first.jpg")
        let secondURL = root.appendingPathComponent("second.jpg")
        let thirdURL = root.appendingPathComponent("third.jpg")
        try Data([1, 2, 3, 4]).write(to: firstURL)
        try Data([5, 6, 7, 8]).write(to: secondURL)
        try Data([9, 10, 11, 12]).write(to: thirdURL)
        let assets = [
            makeAsset(
                id: "quick-first",
                url: firstURL,
                state: .empty
            ),
            makeAsset(
                id: "quick-second",
                url: secondURL,
                state: .empty
            ),
            makeAsset(
                id: "quick-third",
                url: thirdURL,
                state: .empty
            ),
        ]

        var store = CatalogStore(directory: directory)
        try store.upsert(
            assets: assets,
            rootURL: root,
            recursive: false
        )
        XCTAssertEqual(
            try store.setQuickCollectionMembership(
                photoIDs: [
                    assets[1].id,
                    assets[0].id,
                    assets[1].id,
                    "not-in-catalog",
                ],
                included: true
            ),
            2
        )
        XCTAssertEqual(
            try store.entries(for: .quickCollection).map(\.id),
            [assets[1].id, assets[0].id]
        )
        XCTAssertEqual(try store.summary()[.quickCollection], 2)
        XCTAssertEqual(
            try store.setQuickCollectionMembership(
                photoIDs: [assets[0].id],
                included: true
            ),
            0
        )

        let replacementURL = root.appendingPathComponent(
            "second-relocated.jpg"
        )
        try FileManager.default.moveItem(
            at: secondURL,
            to: replacementURL
        )
        try store.refreshMissingStatus()
        XCTAssertTrue(
            try XCTUnwrap(
                store.entries(for: .quickCollection).first
            ).isMissing
        )
        XCTAssertEqual(try store.summary()[.quickCollection], 2)
        let relink = try store.relinkPhoto(
            id: assets[1].id,
            to: replacementURL
        )
        XCTAssertNotEqual(relink.entry.id, assets[1].id)
        XCTAssertEqual(
            try store.entries(for: .quickCollection).map(\.id),
            [relink.entry.id, assets[0].id]
        )
        XCTAssertEqual(
            try store.quickCollectionPhotoIDs(),
            [relink.entry.id, assets[0].id]
        )
        XCTAssertEqual(
            try Data(contentsOf: replacementURL),
            Data([5, 6, 7, 8])
        )

        try store.removePhoto(id: relink.entry.id)
        XCTAssertEqual(
            try store.quickCollectionPhotoIDs(),
            [assets[0].id]
        )
        XCTAssertEqual(try store.summary()[.quickCollection], 1)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: replacementURL.path
            )
        )

        store = CatalogStore(directory: directory)
        XCTAssertEqual(
            try store.entries(for: .quickCollection).map(\.id),
            [assets[0].id]
        )
        XCTAssertEqual(try store.clearQuickCollection(), 1)
        XCTAssertTrue(try store.quickCollectionPhotoIDs().isEmpty)
        XCTAssertEqual(try store.summary()[.quickCollection], 0)
        XCTAssertEqual(
            try Data(contentsOf: firstURL),
            Data([1, 2, 3, 4])
        )
        XCTAssertTrue(try store.integrityCheck())
    }

    func testRegularCollectionsPersistHierarchyTargetOrderAndNeverDeleteFiles()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let firstURL = root.appendingPathComponent("first.jpg")
        let secondURL = root.appendingPathComponent("second.jpg")
        let thirdURL = root.appendingPathComponent("third.jpg")
        let fourthURL = root.appendingPathComponent("fourth.jpg")
        let fixtures: [(String, URL, Data)] = [
            ("collection-first", firstURL, Data([1, 2, 3, 4])),
            ("collection-second", secondURL, Data([5, 6, 7, 8])),
            ("collection-third", thirdURL, Data([9, 10, 11, 12])),
            ("collection-fourth", fourthURL, Data([13, 14, 15, 16])),
        ]
        for (_, url, bytes) in fixtures {
            try bytes.write(to: url)
        }
        let assets = fixtures.map {
            makeAsset(id: $0.0, url: $0.1, state: .empty)
        }

        var store = CatalogStore(directory: directory)
        try store.upsert(
            assets: assets,
            rootURL: root,
            recursive: false
        )

        let rootSet = CatalogCollectionSet(
            name: "Portfolio"
        )
        let childSet = CatalogCollectionSet(
            name: "2026",
            parentSetID: rootSet.id
        )
        try store.saveCollectionSet(rootSet)
        try store.saveCollectionSet(childSet)
        var invalidRoot = rootSet
        invalidRoot.parentSetID = childSet.id
        XCTAssertThrowsError(
            try store.saveCollectionSet(invalidRoot)
        ) {
            XCTAssertEqual(
                $0 as? CatalogStoreError,
                .collectionSetDestinationInsideSource
            )
        }

        let selects = CatalogPhotoCollection(
            name: "Selects",
            parentSetID: childSet.id
        )
        let outtakes = CatalogPhotoCollection(
            name: "Outtakes",
            parentSetID: rootSet.id
        )
        try store.savePhotoCollection(selects)
        try store.savePhotoCollection(outtakes)
        let smart = SavedSmartCollection(
            name: "Five Star Selects",
            filter: FilterState(minimumRating: 5),
            parentSetID: childSet.id
        )
        try store.saveSmartCollection(smart)
        try store.setTargetPhotoCollection(id: selects.id)

        XCTAssertEqual(
            try store.setPhotoCollectionMembership(
                collectionID: selects.id,
                photoIDs: [
                    assets[1].id,
                    assets[0].id,
                    assets[1].id,
                    "not-in-catalog",
                ],
                included: true
            ),
            2
        )
        XCTAssertEqual(
            try store.entries(
                forPhotoCollection: selects.id
            ).map(\.id),
            [assets[1].id, assets[0].id]
        )
        XCTAssertEqual(
            try XCTUnwrap(
                store.photoCollections().first {
                    $0.id == selects.id
                }
            ).photoCount,
            2
        )
        XCTAssertEqual(
            try store.photoCollectionMemberships()[
                assets[0].id
            ],
            [selects.id]
        )

        try store.reorderPhotoCollection(
            collectionID: selects.id,
            photoIDs: [assets[0].id, assets[1].id]
        )
        XCTAssertEqual(
            try store.photoCollectionPhotoIDs(
                collectionID: selects.id
            ),
            [assets[0].id, assets[1].id]
        )
        let duplicate = try store.duplicatePhotoCollection(
            id: selects.id
        )
        XCTAssertFalse(duplicate.isTarget)
        XCTAssertEqual(duplicate.photoCount, 2)
        XCTAssertEqual(
            try store.photoCollectionPhotoIDs(
                collectionID: duplicate.id
            ),
            [assets[0].id, assets[1].id]
        )
        let duplicateSet = try store.duplicateCollectionSet(
            id: rootSet.id
        )
        XCTAssertEqual(duplicateSet.name, "Portfolio Copy")
        XCTAssertEqual(try store.collectionSets().count, 4)
        XCTAssertEqual(
            try store.savedSmartCollections().count,
            2
        )
        let duplicateChild = try XCTUnwrap(
            store.collectionSets().first {
                $0.parentSetID == duplicateSet.id
                    && $0.name == childSet.name
            }
        )
        XCTAssertEqual(
            try store.photoCollections().filter {
                $0.parentSetID == duplicateChild.id
            }.map(\.photoCount).sorted(),
            [2, 2]
        )
        try store.deleteCollectionSet(id: duplicateSet.id)
        XCTAssertEqual(try store.collectionSets().count, 2)
        XCTAssertEqual(
            try store.savedSmartCollections(),
            [smart]
        )

        try store.setQuickCollectionMembership(
            photoIDs: [assets[2].id, assets[1].id],
            included: true
        )
        let savedQuick = CatalogPhotoCollection(
            name: "Saved Quick"
        )
        XCTAssertEqual(
            try store.saveQuickCollection(
                as: savedQuick,
                clearQuickCollection: true
            ),
            2
        )
        XCTAssertEqual(
            try store.photoCollectionPhotoIDs(
                collectionID: savedQuick.id
            ),
            [assets[2].id, assets[1].id]
        )
        XCTAssertTrue(try store.quickCollectionPhotoIDs().isEmpty)

        let relocatedURL = root.appendingPathComponent(
            "second-relocated.jpg"
        )
        try FileManager.default.moveItem(
            at: secondURL,
            to: relocatedURL
        )
        try store.refreshMissingStatus()
        XCTAssertTrue(
            try XCTUnwrap(
                store.entries(
                    forPhotoCollection: selects.id
                ).last
            ).isMissing
        )
        let relink = try store.relinkPhoto(
            id: assets[1].id,
            to: relocatedURL
        )
        XCTAssertEqual(
            try store.photoCollectionPhotoIDs(
                collectionID: selects.id
            ),
            [assets[0].id, relink.entry.id]
        )
        XCTAssertEqual(
            try store.photoCollectionPhotoIDs(
                collectionID: savedQuick.id
            ),
            [assets[2].id, relink.entry.id]
        )

        try store.removePhoto(id: assets[0].id)
        XCTAssertEqual(
            try store.photoCollectionPhotoIDs(
                collectionID: selects.id
            ),
            [relink.entry.id]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: firstURL.path)
        )

        store = CatalogStore(directory: directory)
        XCTAssertEqual(try store.collectionSets().count, 2)
        XCTAssertEqual(
            try store.savedSmartCollections(),
            [smart]
        )
        XCTAssertEqual(
            try store.photoCollections().first {
                $0.id == selects.id
            }?.isTarget,
            true
        )
        XCTAssertEqual(
            try store.photoCollectionPhotoIDs(
                collectionID: selects.id
            ),
            [relink.entry.id]
        )

        try store.deleteCollectionSet(id: rootSet.id)
        XCTAssertTrue(try store.collectionSets().isEmpty)
        XCTAssertTrue(try store.savedSmartCollections().isEmpty)
        XCTAssertEqual(
            try store.photoCollections().map(\.id),
            [savedQuick.id]
        )
        XCTAssertEqual(
            try store.entries(for: .allPhotos).count,
            3
        )
        XCTAssertEqual(
            try Data(contentsOf: firstURL),
            fixtures[0].2
        )
        XCTAssertEqual(
            try Data(contentsOf: relocatedURL),
            fixtures[1].2
        )
        XCTAssertEqual(
            try Data(contentsOf: thirdURL),
            fixtures[2].2
        )
        XCTAssertEqual(
            try Data(contentsOf: fourthURL),
            fixtures[3].2
        )
        XCTAssertTrue(try store.integrityCheck())
    }

    func testKeywordNormalizationTrimsDeduplicatesAndLimits() {
        let values = ["  Tokyo  ", "TOKYO", "Café", "cafe\u{301}", "", "a   b"]
        XCTAssertEqual(
            PhotoUserState.normalizedKeywords(values),
            ["Tokyo", "Café", "a b"]
        )
        XCTAssertEqual(
            PhotoUserState(keywords: values).keywords,
            ["Tokyo", "Café", "a b"]
        )
    }

    func testHierarchicalKeywordNormalizationAndSummaryTree() throws {
        let values = [
            " Places > Japan > Tokyo ",
            "places|japan|TOKYO",
            "Places › Japan › Kyoto",
            "People > Family",
        ]
        let normalized = PhotoUserState.normalizedKeywords(values)
        XCTAssertEqual(
            normalized,
            [
                "Places|Japan|Tokyo",
                "Places|Japan|Kyoto",
                "People|Family",
            ]
        )
        XCTAssertEqual(
            PhotoUserState.flatKeywords(from: normalized),
            ["Tokyo", "Kyoto", "Family"]
        )

        let tree = KeywordSummaryNode.makeTree(
            from: [
                "Places|Japan|Tokyo": 2,
                "Places|Japan|Kyoto": 1,
                "People|Family": 4,
            ]
        )
        XCTAssertEqual(tree.map(\.name), ["People", "Places"])
        XCTAssertEqual(tree.map(\.count), [4, 3])
        let places = try XCTUnwrap(
            tree.first(where: { $0.path == "Places" })
        )
        XCTAssertEqual(places.children.first?.path, "Places|Japan")
        XCTAssertEqual(places.children.first?.count, 3)
    }

    func testMissingPhotoRelinkPreservesStateAndCanBeRemoved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "originals",
            isDirectory: true
        )
        let relocated = directory.appendingPathComponent(
            "relocated",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: relocated,
            withIntermediateDirectories: true
        )
        let original = root.appendingPathComponent("hero.jpg")
        let replacement = relocated.appendingPathComponent("hero.jpg")
        try Data([1, 2, 3, 4]).write(to: original)

        let state = PhotoUserState(
            rating: 5,
            flagged: true,
            note: "Keep",
            keywords: ["Places > Japan > Tokyo"],
            adjustments: PhotoAdjustments(exposure: 0.8)
        )
        let metadata = PhotoMetadata(
            cameraMake: "Canon",
            cameraModel: "EOS R5"
        )
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [
                makeAsset(
                    id: "missing-original",
                    url: original,
                    state: state,
                    metadata: metadata
                ),
            ],
            rootURL: root,
            recursive: true
        )

        try FileManager.default.removeItem(at: original)
        try store.refreshMissingStatus()
        XCTAssertEqual(try store.summary()[.missingFiles], 1)

        try Data([1, 2, 3, 4]).write(to: replacement)
        let result = try store.relinkPhoto(
            id: "missing-original",
            to: replacement
        )
        XCTAssertEqual(result.previousID, "missing-original")
        XCTAssertEqual(result.entry.path, replacement.path)
        XCTAssertEqual(result.entry.userState, state)
        XCTAssertEqual(result.entry.metadata, metadata)
        XCTAssertFalse(result.entry.isMissing)
        XCTAssertEqual(try store.summary()[.allPhotos], 1)
        XCTAssertEqual(try store.summary()[.missingFiles], 0)
        XCTAssertEqual(
            try store.userStates()[result.entry.id],
            state
        )

        try store.removePhoto(id: result.entry.id)
        XCTAssertEqual(try store.summary()[.allPhotos], 0)
        XCTAssertEqual(try store.summary().rootCount, 0)
    }

    func testRelinkRejectsDifferentImageFormat() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let original = root.appendingPathComponent("photo.jpg")
        let replacement = root.appendingPathComponent("photo.png")
        try Data([1, 2, 3, 4]).write(to: original)
        try Data([1, 2, 3, 4]).write(to: replacement)
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [
                makeAsset(id: "photo", url: original, state: .empty),
            ],
            rootURL: root,
            recursive: false
        )

        XCTAssertThrowsError(
            try store.relinkPhoto(id: "photo", to: replacement)
        ) { error in
            XCTAssertEqual(
                error as? CatalogStoreError,
                .replacementFormatMismatch(
                    expected: FileFormat.jpeg.displayName,
                    actual: FileFormat.png.displayName
                )
            )
        }
    }

    func testContentHashPersistsOnlyWhileFileFactsMatch() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("photo.jpg")
        try Data([1, 2, 3, 4]).write(to: url)
        let store = CatalogStore(directory: directory)
        let original = makeAsset(
            id: "photo",
            url: url,
            state: .empty
        )
        let hash = String(repeating: "a", count: 64)
        try store.upsert(
            assets: [original],
            rootURL: root,
            recursive: false,
            contentHashes: [original.id: hash]
        )
        XCTAssertEqual(try store.contentHash(id: original.id), hash)
        let imageHash = String(repeating: "b", count: 64)
        XCTAssertTrue(
            try store.recordImageContentHash(
                imageHash,
                id: original.id,
                expectedFileSize: original.fileSize,
                expectedModificationDate:
                    original.modificationDate
            )
        )
        XCTAssertEqual(
            try store.imageContentHash(id: original.id),
            imageHash
        )
        XCTAssertEqual(
            try store.duplicateCandidates(fileSize: 4).first?.contentHash,
            hash
        )
        XCTAssertEqual(
            try store.duplicateCandidates(fileSize: 4)
                .first?.imageContentHash,
            imageHash
        )

        try store.upsert(
            assets: [original],
            rootURL: root,
            recursive: false
        )
        XCTAssertEqual(try store.contentHash(id: original.id), hash)
        XCTAssertEqual(
            try store.imageContentHash(id: original.id),
            imageHash
        )

        let changed = PhotoAsset(
            id: original.id,
            url: url,
            path: url.path,
            filename: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSize: 5,
            creationDate: original.creationDate,
            modificationDate: Date(
                timeIntervalSince1970: 1_700_000_200
            ),
            format: .jpeg
        )
        try store.upsert(
            assets: [changed],
            rootURL: root,
            recursive: false
        )
        XCTAssertNil(try store.contentHash(id: original.id))
        XCTAssertNil(try store.imageContentHash(id: original.id))
    }

    func testCatalogGroupsEveryKnownExactDuplicateAndSummarizesWaste()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let urls = (1...5).map {
            root.appendingPathComponent("photo-\($0).jpg")
        }
        for url in urls {
            try Data([1, 2, 3, 4]).write(to: url)
        }
        let assets = urls.enumerated().map {
            makeAsset(
                id: "photo-\($0.offset + 1)",
                url: $0.element,
                state: .empty
            )
        }
        let firstHash = String(repeating: "a", count: 64)
        let secondHash = String(repeating: "b", count: 64)
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: assets,
            rootURL: root,
            recursive: false,
            contentHashes: [
                assets[0].id: firstHash,
                assets[1].id: firstHash,
                assets[2].id: firstHash,
                assets[3].id: secondHash,
                assets[4].id: secondHash,
            ]
        )

        let groups = try store.exactDuplicateGroups()
        XCTAssertEqual(groups.map(\.contentHash), [
            firstHash,
            secondHash,
        ])
        XCTAssertEqual(groups.map(\.members.count), [3, 2])
        XCTAssertEqual(groups.map(\.duplicateCopyCount), [2, 1])
        XCTAssertEqual(groups.map(\.reclaimableBytes), [8, 4])
        XCTAssertEqual(groups[0].anchorID, assets[0].id)

        var summary = try store.summary()
        XCTAssertEqual(summary[.exactDuplicates], 5)
        XCTAssertEqual(summary.exactDuplicateGroupCount, 2)
        XCTAssertEqual(summary.duplicateReclaimableBytes, 12)
        XCTAssertEqual(summary.hashedPhotoCount, 5)
        XCTAssertEqual(
            Set(try store.entries(for: .exactDuplicates).map(\.id)),
            Set(assets.map(\.id))
        )

        try store.clearContentHash(id: assets[4].id)
        summary = try store.summary()
        XCTAssertEqual(summary[.exactDuplicates], 3)
        XCTAssertEqual(summary.exactDuplicateGroupCount, 1)
        XCTAssertEqual(summary.duplicateReclaimableBytes, 8)
        XCTAssertEqual(summary.hashedPhotoCount, 4)
    }

    func testCatalogDuplicateScannerUsesCompleteHashesAndRejectsStaleFacts()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let firstURL = root.appendingPathComponent("first.jpg")
        let secondURL = root.appendingPathComponent("second.jpg")
        let sameSizeUniqueURL = root.appendingPathComponent("unique.jpg")
        let singletonURL = root.appendingPathComponent("singleton.jpg")
        try Data([1, 2, 3, 4]).write(to: firstURL)
        try Data([1, 2, 3, 4]).write(to: secondURL)
        try Data([4, 3, 2, 1]).write(to: sameSizeUniqueURL)
        try Data([9, 8, 7]).write(to: singletonURL)

        func asset(id: String, url: URL) throws -> PhotoAsset {
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
            ])
            return PhotoAsset(
                id: id,
                url: url,
                path: url.path,
                filename: url.lastPathComponent,
                fileExtension: url.pathExtension,
                fileSize: Int64(values.fileSize ?? 0),
                creationDate: values.creationDate,
                modificationDate: values.contentModificationDate,
                format: .jpeg
            )
        }

        let assets = [
            try asset(id: "first", url: firstURL),
            try asset(id: "second", url: secondURL),
            try asset(id: "unique", url: sameSizeUniqueURL),
            try asset(id: "singleton", url: singletonURL),
        ]
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: assets,
            rootURL: root,
            recursive: false
        )
        let scanner = CatalogDuplicateScanner(catalogStore: store)

        let firstResult = try await scanner.scan()
        XCTAssertEqual(firstResult.candidateCount, 4)
        XCTAssertEqual(firstResult.newlyHashedCount, 3)
        XCTAssertEqual(firstResult.cachedHashCount, 0)
        XCTAssertEqual(
            firstResult.unavailablePaths,
            [singletonURL.path]
        )
        XCTAssertEqual(firstResult.groups.count, 1)
        XCTAssertEqual(firstResult.groups[0].matchBasis, .wholeFile)
        XCTAssertEqual(firstResult.groups[0].members.count, 2)
        XCTAssertEqual(firstResult.duplicateCopyCount, 1)
        XCTAssertEqual(firstResult.reclaimableBytes, 4)
        XCTAssertNil(try store.contentHash(id: "singleton"))

        let cachedResult = try await scanner.scan()
        XCTAssertEqual(cachedResult.newlyHashedCount, 0)
        XCTAssertEqual(cachedResult.cachedHashCount, 3)
        XCTAssertEqual(
            cachedResult.unavailablePaths,
            [singletonURL.path]
        )
        XCTAssertEqual(cachedResult.groups, firstResult.groups)

        try Data([5, 6, 7, 8]).write(to: secondURL)
        let changedDate = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: changedDate],
            ofItemAtPath: secondURL.path
        )

        let staleResult = try await scanner.scan()
        XCTAssertEqual(
            staleResult.unavailablePaths,
            [singletonURL.path, secondURL.path]
        )
        XCTAssertTrue(staleResult.groups.isEmpty)
        XCTAssertNil(try store.contentHash(id: "second"))
        XCTAssertEqual(try store.summary()[.exactDuplicates], 0)
    }

    func testCatalogDuplicateScannerGroupsMetadataOnlyCopiesByImageData()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let originalURL = root.appendingPathComponent("original.jpg")
        let metadataCopyURL = root.appendingPathComponent(
            "renamed-metadata-copy.jpg"
        )
        let differentURL = root.appendingPathComponent("different.jpg")
        let matchingImage = try ExactImageDuplicateTestFixture.image(
            variant: 0
        )
        try ExactImageDuplicateTestFixture.writeJPEG(
            matchingImage,
            to: originalURL,
            description: "Original"
        )
        try ExactImageDuplicateTestFixture.writeJPEG(
            matchingImage,
            to: metadataCopyURL,
            description:
                "A much longer metadata-only description for the renamed copy"
        )
        try ExactImageDuplicateTestFixture.writeJPEG(
            ExactImageDuplicateTestFixture.image(variant: 1),
            to: differentURL,
            description: "Different pixels"
        )
        let sourceBytes = try Dictionary(
            uniqueKeysWithValues: [
                originalURL,
                metadataCopyURL,
                differentURL,
            ].map {
                ($0, try Data(contentsOf: $0))
            }
        )
        let assets = try [
            ("original", originalURL),
            ("metadata-copy", metadataCopyURL),
            ("different", differentURL),
        ].map {
            try ExactImageDuplicateTestFixture.asset(
                id: $0.0,
                url: $0.1
            )
        }
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: assets,
            rootURL: root,
            recursive: false
        )

        let result = try await CatalogDuplicateScanner(
            catalogStore: store
        ).scan()
        XCTAssertEqual(result.candidateCount, 3)
        XCTAssertEqual(result.newlyHashedCount, 3)
        XCTAssertEqual(result.cachedHashCount, 0)
        XCTAssertTrue(result.unavailablePaths.isEmpty)
        XCTAssertEqual(result.groups.count, 1)
        let group = try XCTUnwrap(result.groups.first)
        XCTAssertEqual(group.matchBasis, .imageData)
        XCTAssertEqual(
            Set(group.members.map(\.id)),
            ["original", "metadata-copy"]
        )
        XCTAssertEqual(result.imageDataGroupCount, 1)
        XCTAssertEqual(result.wholeFileFallbackGroupCount, 0)
        XCTAssertEqual(result.groupedPhotoCount, 2)
        XCTAssertEqual(result.duplicateCopyCount, 1)
        XCTAssertNotEqual(
            try FileContentHasher.sha256(for: originalURL),
            try FileContentHasher.sha256(for: metadataCopyURL)
        )
        XCTAssertEqual(
            try store.imageContentHash(id: "original"),
            try store.imageContentHash(id: "metadata-copy")
        )
        XCTAssertNotEqual(
            try store.imageContentHash(id: "original"),
            try store.imageContentHash(id: "different")
        )
        let expectedReclaimableBytes = try XCTUnwrap(
            assets.first { $0.id == group.members[1].id }
        ).fileSize
        XCTAssertEqual(
            result.reclaimableBytes,
            expectedReclaimableBytes
        )
        let summary = try store.summary()
        XCTAssertEqual(summary[.exactDuplicates], 2)
        XCTAssertEqual(summary.exactDuplicateGroupCount, 1)
        XCTAssertEqual(
            summary.duplicateReclaimableBytes,
            expectedReclaimableBytes
        )
        XCTAssertEqual(summary.hashedPhotoCount, 3)
        for (url, bytes) in sourceBytes {
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }

        let cached = try await CatalogDuplicateScanner(
            catalogStore: store
        ).scan()
        XCTAssertEqual(cached.newlyHashedCount, 0)
        XCTAssertEqual(cached.cachedHashCount, 3)
        XCTAssertEqual(cached.groups, result.groups)
    }

    func testCatalogWideKeywordRenameIncludesMissingPhotosAndCollections()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let firstURL = root.appendingPathComponent("first.jpg")
        let secondURL = root.appendingPathComponent("second.jpg")
        let thirdURL = root.appendingPathComponent("third.jpg")
        let fourthURL = root.appendingPathComponent("fourth.jpg")
        for url in [firstURL, secondURL, thirdURL, fourthURL] {
            try Data([1, 2, 3, 4]).write(to: url)
        }
        let firstState = PhotoUserState(
            rating: 5,
            note: "keep every other field",
            keywords: [
                "Places > Japan",
                "Places > Japan > Tokyo",
                "Keep",
            ],
            adjustments: PhotoAdjustments(exposure: 0.75)
        )
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [
                makeAsset(
                    id: "first",
                    url: firstURL,
                    state: firstState
                ),
                makeAsset(
                    id: "second",
                    url: secondURL,
                    state: PhotoUserState(
                        keywords: ["places > japan > Kyoto"]
                    )
                ),
                makeAsset(
                    id: "third",
                    url: thirdURL,
                    state: PhotoUserState(
                        keywords: [
                            "Places > Japan > Tokyo",
                            "Places > Nihon > Tokyo",
                        ]
                    )
                ),
                makeAsset(
                    id: "fourth",
                    url: fourthURL,
                    state: PhotoUserState(
                        keywords: ["Places > Japanology"]
                    )
                ),
            ],
            rootURL: root,
            recursive: false
        )
        let parentCollection = SavedSmartCollection(
            name: "Japan",
            filter: FilterState(keyword: "Places|Japan")
        )
        let childCollection = SavedSmartCollection(
            name: "Tokyo",
            filter: FilterState(keyword: "Places|Japan|Tokyo")
        )
        let unrelatedCollection = SavedSmartCollection(
            name: "People",
            filter: FilterState(keyword: "People")
        )
        for collection in [
            parentCollection,
            childCollection,
            unrelatedCollection,
        ] {
            try store.saveSmartCollection(collection)
        }
        try store.saveKeywordDefinition(CatalogKeywordDefinition(
            path: "Places|Japan",
            synonyms: ["Nippon"],
            includeOnExport: false,
            exportSynonyms: false,
            exportContainingKeywords: true
        ))
        try store.saveKeywordDefinition(CatalogKeywordDefinition(
            path: "Places|Japan|Tokyo",
            synonyms: ["Edo"],
            exportContainingKeywords: true
        ))
        try store.saveKeywordDefinition(CatalogKeywordDefinition(
            path: "Places|Nihon",
            synonyms: ["Japanese"],
            includeOnExport: true,
            exportSynonyms: true
        ))
        try FileManager.default.removeItem(at: secondURL)
        try store.refreshMissingStatus()

        let change = CatalogKeywordChange.rename(
            sourcePath: "Places > Japan",
            newName: "Nihon"
        )
        let preview = try store.previewKeywordChange(change)
        XCTAssertEqual(preview.sourcePath, "Places|Japan")
        XCTAssertEqual(preview.destinationPath, "Places|Nihon")
        XCTAssertEqual(preview.affectedPhotoCount, 3)
        XCTAssertEqual(preview.affectedKeywordAssignmentCount, 4)
        XCTAssertEqual(preview.affectedKeywordPathCount, 3)
        XCTAssertEqual(preview.missingPhotoCount, 1)
        XCTAssertEqual(preview.mergedAssignmentCount, 1)
        XCTAssertEqual(preview.affectedSmartCollectionCount, 2)
        XCTAssertEqual(preview.affectedDefinitionCount, 2)

        let result = try store.applyKeywordChange(change)
        XCTAssertEqual(result.preview, preview)
        let states = try store.userStates()
        XCTAssertEqual(
            states["first"]?.keywords,
            [
                "Places|Nihon",
                "Places|Nihon|Tokyo",
                "Keep",
            ]
        )
        XCTAssertEqual(states["first"]?.rating, firstState.rating)
        XCTAssertEqual(states["first"]?.note, firstState.note)
        XCTAssertEqual(
            states["first"]?.adjustments,
            firstState.adjustments
        )
        XCTAssertEqual(
            states["second"]?.keywords,
            ["Places|Nihon|Kyoto"]
        )
        XCTAssertEqual(
            states["third"]?.keywords,
            ["Places|Nihon|Tokyo"]
        )
        XCTAssertEqual(
            states["fourth"]?.keywords,
            ["Places|Japanology"]
        )
        let collections = try store.savedSmartCollections()
        XCTAssertEqual(
            collections.first(where: { $0.id == parentCollection.id })?
                .filter.keyword,
            "Places|Nihon"
        )
        XCTAssertEqual(
            collections.first(where: { $0.id == childCollection.id })?
                .filter.keyword,
            "Places|Nihon|Tokyo"
        )
        XCTAssertEqual(
            collections.first(where: { $0.id == unrelatedCollection.id })?
                .filter.keyword,
            "People"
        )
        let mergedDefinition = try store.keywordDefinition(
            for: "Places|Nihon"
        )
        XCTAssertEqual(
            Set(mergedDefinition.synonyms),
            ["Japanese", "Nippon"]
        )
        XCTAssertFalse(mergedDefinition.includeOnExport)
        XCTAssertFalse(mergedDefinition.exportSynonyms)
        XCTAssertTrue(
            mergedDefinition.exportContainingKeywords
        )
        XCTAssertEqual(
            try store.keywordDefinition(
                for: "Places|Nihon|Tokyo"
            ).synonyms,
            ["Edo"]
        )
        XCTAssertEqual(
            try store.exportKeywords(for: ["Places|Japan"]),
            ["Japan"]
        )
        XCTAssertTrue(try store.integrityCheck())

        let reopened = CatalogStore(directory: directory)
        XCTAssertEqual(
            try reopened.userStates()["second"]?.keywords,
            ["Places|Nihon|Kyoto"]
        )
        XCTAssertEqual(try reopened.summary()[.missingFiles], 1)
    }

    func testKeywordMoveMergeAndBranchDeletionPreserveFilesAndState()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("family.jpg")
        let originalBytes = Data([9, 8, 7, 6])
        try originalBytes.write(to: url)
        let originalState = PhotoUserState(
            rating: 4,
            flagged: true,
            favorite: true,
            note: "metadata survives",
            keywords: [
                "People > Family",
                "People > Family > Alice",
                "Archive > Family > Alice",
                "Unrelated",
            ],
            adjustments: PhotoAdjustments(contrast: 17)
        )
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [
                makeAsset(id: "family", url: url, state: originalState),
            ],
            rootURL: root,
            recursive: false
        )
        try store.saveKeywordDefinition(CatalogKeywordDefinition(
            path: "People|Family",
            synonyms: ["Kin"],
            includeOnExport: false
        ))

        let moveResult = try store.applyKeywordChange(
            .moveOrMerge(
                sourcePath: "People|Family",
                destinationPath: "Archive > Family"
            )
        )
        XCTAssertEqual(moveResult.preview.affectedPhotoCount, 1)
        XCTAssertEqual(moveResult.preview.mergedAssignmentCount, 1)
        XCTAssertEqual(moveResult.preview.affectedDefinitionCount, 1)
        XCTAssertFalse(
            try store.keywordDefinition(
                for: "Archive|Family"
            ).includeOnExport
        )
        var moved = try XCTUnwrap(store.userStates()["family"])
        XCTAssertEqual(
            moved.keywords,
            [
                "Archive|Family",
                "Archive|Family|Alice",
                "Unrelated",
            ]
        )

        let deletePreview = try store.previewKeywordChange(
            .delete(sourcePath: "Archive")
        )
        XCTAssertEqual(deletePreview.affectedKeywordAssignmentCount, 2)
        XCTAssertEqual(deletePreview.affectedKeywordPathCount, 2)
        XCTAssertEqual(deletePreview.affectedDefinitionCount, 1)
        _ = try store.applyKeywordChange(
            .delete(sourcePath: "Archive")
        )
        moved = try XCTUnwrap(store.userStates()["family"])
        XCTAssertEqual(moved.keywords, ["Unrelated"])
        XCTAssertEqual(moved.rating, originalState.rating)
        XCTAssertEqual(moved.pickStatus, originalState.pickStatus)
        XCTAssertEqual(moved.favorite, originalState.favorite)
        XCTAssertEqual(moved.note, originalState.note)
        XCTAssertEqual(moved.adjustments, originalState.adjustments)
        XCTAssertEqual(
            try store.exportKeywords(for: ["Archive|Family"]),
            ["Family"]
        )
        XCTAssertEqual(try Data(contentsOf: url), originalBytes)
        XCTAssertTrue(try store.integrityCheck())
    }

    func testInvalidKeywordMoveLeavesCatalogUnchanged() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("photo.jpg")
        try Data([1, 2, 3, 4]).write(to: url)
        let state = PhotoUserState(
            keywords: ["Places > Japan > Tokyo"]
        )
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [makeAsset(id: "photo", url: url, state: state)],
            rootURL: root,
            recursive: false
        )

        XCTAssertThrowsError(
            try store.applyKeywordChange(
                .moveOrMerge(
                    sourcePath: "Places",
                    destinationPath: "Places > Europe"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? CatalogStoreError,
                .keywordDestinationInsideSource
            )
        }
        XCTAssertEqual(try store.userStates()["photo"], state)
        XCTAssertTrue(try store.integrityCheck())
    }

    func testKeywordMoveRejectsHierarchyBeyondSixteenLevels() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("deep.jpg")
        try Data([1, 2, 3, 4]).write(to: url)
        let deepPath = (0..<16)
            .map { "Level\($0 + 1)" }
            .joined(separator: "|")
        let state = PhotoUserState(keywords: [deepPath])
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [makeAsset(id: "deep", url: url, state: state)],
            rootURL: root,
            recursive: false
        )

        XCTAssertThrowsError(
            try store.previewKeywordChange(
                .moveOrMerge(
                    sourcePath: "Level1",
                    destinationPath: "NewRoot|Level1"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? CatalogStoreError,
                .keywordHierarchyTooDeep
            )
        }
        XCTAssertEqual(try store.userStates()["deep"], state)
        XCTAssertTrue(try store.integrityCheck())
    }

    func testKeywordDefinitionsControlSynonymAndParentExport()
        throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CatalogStore(directory: directory)
        try store.saveKeywordDefinition(CatalogKeywordDefinition(
            path: "Places",
            synonyms: ["Location", "location"],
            includeOnExport: true,
            exportSynonyms: true
        ))
        try store.saveKeywordDefinition(CatalogKeywordDefinition(
            path: "Places|Japan",
            synonyms: ["Nippon"],
            includeOnExport: false
        ))
        try store.saveKeywordDefinition(CatalogKeywordDefinition(
            path: "Places|Japan|Tokyo",
            synonyms: ["Edo", "東京", "Tokyo"],
            includeOnExport: true,
            exportSynonyms: true,
            exportContainingKeywords: true
        ))

        XCTAssertEqual(
            try store.exportKeywords(
                for: [
                    "Places|Japan|Tokyo",
                    "People|Family",
                ]
            ),
            [
                "Tokyo",
                "Edo",
                "東京",
                "Places",
                "Location",
                "Family",
            ]
        )
        let tokyo = try store.keywordDefinition(
            for: "PLACES > JAPAN > TOKYO"
        )
        XCTAssertEqual(tokyo.path, "Places|Japan|Tokyo")
        XCTAssertEqual(tokyo.synonyms, ["Edo", "東京"])

        try store.saveKeywordDefinition(CatalogKeywordDefinition(
            path: tokyo.path,
            synonyms: tokyo.synonyms,
            includeOnExport: true,
            exportSynonyms: false,
            exportContainingKeywords: true
        ))
        XCTAssertEqual(
            try store.exportKeywords(
                for: ["Places|Japan|Tokyo"]
            ),
            ["Tokyo", "Places", "Location"]
        )

        let reopened = CatalogStore(directory: directory)
        XCTAssertFalse(
            try reopened.keywordDefinition(
                for: "Places|Japan|Tokyo"
            ).exportSynonyms
        )
        XCTAssertTrue(try reopened.integrityCheck())
    }

    func testPhotoStacksPersistOrderCollapseAndSummaryWithoutTouchingFiles()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let urls = ["first", "second", "third"].map {
            root.appendingPathComponent("\($0).jpg")
        }
        let bytes = [
            Data([1, 2, 3]),
            Data([4, 5, 6]),
            Data([7, 8, 9]),
        ]
        for (url, data) in zip(urls, bytes) {
            try data.write(to: url)
        }

        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: zip(["first", "second", "third"], urls).map {
                makeAsset(id: $0.0, url: $0.1, state: .empty)
            },
            rootURL: root,
            recursive: false
        )

        var stack = try store.createPhotoStack(
            photoIDs: ["second", "first", "third"]
        )
        XCTAssertEqual(
            stack.memberIDs,
            ["second", "first", "third"]
        )
        XCTAssertEqual(stack.topPhotoID, "second")
        XCTAssertTrue(stack.isCollapsed)
        XCTAssertEqual(stack.scopePath, root.standardizedFileURL.path)
        XCTAssertEqual(try store.summary().photoStackCount, 1)
        XCTAssertEqual(try store.summary().stackedPhotoCount, 3)

        try store.setPhotoStackCollapsed(
            id: stack.id,
            collapsed: false
        )
        stack = try store.movePhotoInStack(
            photoID: "third",
            .top
        )
        XCTAssertEqual(
            stack.memberIDs,
            ["third", "second", "first"]
        )
        XCTAssertFalse(stack.isCollapsed)

        let reopened = CatalogStore(directory: directory)
        let persisted = try XCTUnwrap(
            reopened.photoStacks().first
        )
        XCTAssertEqual(persisted.id, stack.id)
        XCTAssertEqual(
            persisted.memberIDs,
            ["third", "second", "first"]
        )
        XCTAssertFalse(persisted.isCollapsed)
        XCTAssertEqual(
            persisted.membership(for: "second"),
            CatalogPhotoStackMembership(
                stackID: stack.id,
                position: 2,
                photoCount: 3,
                isTop: false,
                isCollapsed: false
            )
        )
        for (url, data) in zip(urls, bytes) {
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
        XCTAssertTrue(try reopened.integrityCheck())
    }

    func testPhotoStackFolderAndSuggestionValidationAreAtomic()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        let firstFolder = root.appendingPathComponent("first")
        let secondFolder = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(
            at: firstFolder,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondFolder,
            withIntermediateDirectories: true
        )
        let records: [(String, URL)] = [
            ("a", firstFolder.appendingPathComponent("a.jpg")),
            ("b", secondFolder.appendingPathComponent("b.jpg")),
            ("c", firstFolder.appendingPathComponent("c.jpg")),
            ("d", firstFolder.appendingPathComponent("d.jpg")),
            ("e", firstFolder.appendingPathComponent("e.jpg")),
            ("f", firstFolder.appendingPathComponent("f.jpg")),
        ]
        for (_, url) in records {
            try Data([1]).write(to: url)
        }
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: records.map {
                makeAsset(id: $0.0, url: $0.1, state: .empty)
            },
            rootURL: root,
            recursive: true
        )

        XCTAssertThrowsError(
            try store.createPhotoStack(photoIDs: ["a", "b"])
        ) { error in
            XCTAssertEqual(
                error as? CatalogStoreError,
                .photoStackMembersMustShareFolder
            )
        }
        XCTAssertTrue(try store.photoStacks().isEmpty)

        _ = try store.createPhotoStack(photoIDs: ["a", "c"])
        XCTAssertThrowsError(
            try store.createSuggestedPhotoStacks([
                ["d", "e"],
                ["a", "f"],
            ])
        ) { error in
            XCTAssertEqual(
                error as? CatalogStoreError,
                .photoStackAlreadyContainsSelection
            )
        }
        let stacks = try store.photoStacks()
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].memberIDs, ["a", "c"])
        XCTAssertNil(try store.photoStack(containing: "d"))
        XCTAssertNil(try store.photoStack(containing: "e"))
        XCTAssertTrue(try store.integrityCheck())
    }

    func testPhotoStackRelinkRemovalAndSingletonCleanup()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        let other = directory.appendingPathComponent("other")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: other,
            withIntermediateDirectories: true
        )
        let oldURL = root.appendingPathComponent("old.jpg")
        let peerURL = root.appendingPathComponent("peer.jpg")
        let thirdURL = root.appendingPathComponent("third.jpg")
        for url in [oldURL, peerURL, thirdURL] {
            try Data([1, 2, 3, 4]).write(to: url)
        }
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [
                makeAsset(id: "old", url: oldURL, state: .empty),
                makeAsset(id: "peer", url: peerURL, state: .empty),
                makeAsset(id: "third", url: thirdURL, state: .empty),
            ],
            rootURL: root,
            recursive: false
        )
        _ = try store.createPhotoStack(
            photoIDs: ["old", "peer", "third"]
        )

        let sameFolderReplacement = root
            .appendingPathComponent("replacement.jpg")
        try Data([9, 8, 7, 6]).write(to: sameFolderReplacement)
        let relinked = try store.relinkPhoto(
            id: "old",
            to: sameFolderReplacement
        )
        var stack = try XCTUnwrap(
            store.photoStack(containing: relinked.entry.id)
        )
        XCTAssertEqual(stack.memberIDs.first, relinked.entry.id)
        XCTAssertFalse(stack.memberIDs.contains("old"))

        try store.removePhoto(id: "peer")
        stack = try XCTUnwrap(
            store.photoStack(containing: relinked.entry.id)
        )
        XCTAssertEqual(
            stack.memberIDs,
            [relinked.entry.id, "third"]
        )

        let otherReplacement = other
            .appendingPathComponent("moved.jpg")
        try Data([4, 3, 2, 1]).write(to: otherReplacement)
        _ = try store.relinkPhoto(
            id: relinked.entry.id,
            to: otherReplacement
        )
        XCTAssertTrue(try store.photoStacks().isEmpty)
        XCTAssertEqual(try store.summary().photoStackCount, 0)
        XCTAssertEqual(try store.summary().stackedPhotoCount, 0)
        XCTAssertTrue(try store.integrityCheck())
    }

    func testPhotoStackSplitPreservesOrderAndDissolvesSingletons()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let records = ["a", "b", "c", "d", "e"].map {
            (
                $0,
                root.appendingPathComponent("\($0).jpg")
            )
        }
        for (_, url) in records {
            try Data([1, 2, 3]).write(to: url)
        }
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: records.map {
                makeAsset(id: $0.0, url: $0.1, state: .empty)
            },
            rootURL: root,
            recursive: false
        )
        _ = try store.createPhotoStack(
            photoIDs: ["a", "b", "c", "d", "e"],
            collapsed: false
        )

        var stacks = try store.splitPhotoStack(
            photoIDs: ["b", "c"]
        )
        XCTAssertEqual(
            Set(stacks.map(\.memberIDs)),
            Set([
                ["a", "d", "e"],
                ["b", "c"],
            ])
        )
        XCTAssertTrue(stacks.allSatisfy { !$0.isCollapsed })

        let original = try XCTUnwrap(
            stacks.first { $0.memberIDs.contains("a") }
        )
        XCTAssertThrowsError(
            try store.splitPhotoStack(photoIDs: ["a"])
        ) { error in
            XCTAssertEqual(
                error as? CatalogStoreError,
                .photoStackSplitUnavailable
            )
        }
        XCTAssertEqual(
            try store.photoStack(containing: "a")?.id,
            original.id
        )

        stacks = try store.splitPhotoStack(
            photoIDs: ["d", "e"]
        )
        XCTAssertNil(try store.photoStack(containing: "a"))
        XCTAssertEqual(
            Set(stacks.map(\.memberIDs)),
            Set([
                ["b", "c"],
                ["d", "e"],
            ])
        )
        XCTAssertEqual(try store.summary().photoStackCount, 2)
        XCTAssertEqual(try store.summary().stackedPhotoCount, 4)
        XCTAssertTrue(try store.integrityCheck())
    }
}

final class AssistedCullingTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-culling-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func analysis(
        sharpness: Double = 0.9,
        meanLuminance: Double = 0.5,
        shadowClipping: Double = 0,
        highlightClipping: Double = 0,
        entropy: Double = 0.8,
        textCount: Int = 0,
        rectangleCoverage: Double = 0,
        eyeState: AssistedCullingEyeState = .open,
        fingerprint: [Float] = Array(
            repeating: 0.5,
            count: 64
        )
    ) -> AssistedCullingAnalysis {
        let faces: [AssistedCullingFaceAnalysis]
        if eyeState == .notDetected {
            faces = []
        } else {
            faces = [
                AssistedCullingFaceAnalysis(
                    id: 1,
                    boundingBox: CGRect(
                        x: 0.2,
                        y: 0.2,
                        width: 0.4,
                        height: 0.5
                    ),
                    eyeSharpness: sharpness,
                    eyeOpenness:
                        eyeState == .open
                            ? 0.9
                            : eyeState == .closed ? 0.1 : 0.45,
                    eyeState: eyeState
                ),
            ]
        }
        return AssistedCullingSignalInterpreter.analysis(
            from: AssistedCullingVisualSignals(
                subjectDetected: true,
                subjectSharpness: sharpness,
                globalSharpness: sharpness,
                faces: faces,
                meanLuminance: meanLuminance,
                shadowClipping: shadowClipping,
                highlightClipping: highlightClipping,
                entropy: entropy,
                textObservationCount: textCount,
                largestRectangleCoverage: rectangleCoverage,
                visualFingerprint: fingerprint
            ),
            analyzedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func asset(
        id: String,
        url: URL,
        captureDate: Date?
    ) throws -> PhotoAsset {
        let values = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return PhotoAsset(
            id: id,
            url: url,
            path: url.path,
            filename: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSize: (values[.size] as? NSNumber)?.int64Value ?? 0,
            creationDate: values[.creationDate] as? Date,
            modificationDate: values[.modificationDate] as? Date,
            format: .jpeg,
            metadata: PhotoMetadata(captureDate: captureDate)
        )
    }

    private func writeAnalysisJPEG(to url: URL) throws {
        let width = 256
        let height = 192
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.white.cgColor)
        context.fill(
            CGRect(x: 0, y: 0, width: width, height: height)
        )
        for row in 0..<8 {
            for column in 0..<10 where (row + column).isMultiple(of: 2) {
                context.setFillColor(NSColor.black.cgColor)
                context.fill(
                    CGRect(
                        x: column * 24,
                        y: row * 24,
                        width: 18,
                        height: 18
                    )
                )
            }
        }
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testSuggestedStacksStayWithinFolderAndRankBestPhotoOnTop()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstFolder = directory.appendingPathComponent("first")
        let secondFolder = directory.appendingPathComponent("second")
        for folder in [firstFolder, secondFolder] {
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true
            )
        }
        let weakerURL = firstFolder.appendingPathComponent("weaker.jpg")
        let bestURL = firstFolder.appendingPathComponent("best.jpg")
        let otherURL = secondFolder.appendingPathComponent("other.jpg")
        for url in [weakerURL, bestURL, otherURL] {
            try Data([1, 2, 3]).write(to: url)
        }
        let capture = Date(timeIntervalSince1970: 1_700_000_000)
        let assets = [
            try asset(
                id: "weaker",
                url: weakerURL,
                captureDate: capture
            ),
            try asset(
                id: "best",
                url: bestURL,
                captureDate: capture.addingTimeInterval(1)
            ),
            try asset(
                id: "other-folder",
                url: otherURL,
                captureDate: capture.addingTimeInterval(1)
            ),
        ]
        let analyses = [
            "weaker": analysis(sharpness: 0.55),
            "best": analysis(sharpness: 0.95),
            "other-folder": analysis(sharpness: 0.9),
        ]

        XCTAssertEqual(
            AssistedCullingAnalyzer.suggestedStacks(
                assets: assets,
                analysesByID: analyses,
                criteria: .default
            ),
            [["best", "weaker"]]
        )
    }

    func testSignalInterpretationProducesReviewableSelectAndRejectReasons() {
        let good = analysis()
        let goodEvaluation = good.evaluation(criteria: .default)
        XCTAssertEqual(goodEvaluation.decision, .select)
        XCTAssertTrue(
            goodEvaluation.reasons.contains {
                $0.contains("Subject focus")
            }
        )
        XCTAssertEqual(good.eyeState, .open)
        XCTAssertEqual(good.faces.count, 1)

        let exposure = analysis(
            meanLuminance: 0.01,
            shadowClipping: 0.85
        )
        let exposureEvaluation = exposure.evaluation(
            criteria: .default
        )
        XCTAssertEqual(exposureEvaluation.decision, .reject)
        XCTAssertTrue(
            exposureEvaluation.reasons.contains {
                $0.contains("Exposure issue")
            }
        )

        let document = analysis(
            textCount: 10,
            rectangleCoverage: 0.85
        )
        var criteria = AssistedCullingCriteria.default
        criteria.rejectDocuments = true
        XCTAssertEqual(
            document.evaluation(criteria: criteria).decision,
            .reject
        )

        var eyesCriteria = AssistedCullingCriteria.default
        eyesCriteria.useSubjectFocus = false
        eyesCriteria.useEyesOpen = true
        eyesCriteria.requireDetectedEyesForEyesOpen = true
        let closed = analysis(eyeState: .closed)
        XCTAssertEqual(
            closed.evaluation(criteria: eyesCriteria).decision,
            .review
        )
    }

    func testCatalogCullingCacheIsFactGuardedAndManualDecisionPersists()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("photo.jpg")
        try Data([1, 2, 3, 4]).write(to: url)
        let original = try asset(
            id: "photo",
            url: url,
            captureDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [original],
            rootURL: root,
            recursive: false
        )
        let value = analysis()
        XCTAssertTrue(try store.recordCullingAnalysis(
            value,
            id: original.id,
            expectedFileSize: original.fileSize,
            expectedModificationDate: original.modificationDate
        ))

        var candidates = try store.cullingAnalysisCandidates(
            engineVersion:
                AssistedCullingAnalysis.currentEngineVersion
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].cachedAnalysis, value)
        XCTAssertNil(candidates[0].manualDecision)

        try store.setCullingManualDecision(.reject, id: original.id)
        candidates = try store.cullingAnalysisCandidates(
            engineVersion:
                AssistedCullingAnalysis.currentEngineVersion
        )
        XCTAssertEqual(candidates[0].manualDecision, .reject)

        try Data([1, 2, 3, 4, 5]).write(to: url)
        let changed = try asset(
            id: original.id,
            url: url,
            captureDate: original.metadata?.captureDate
        )
        try store.upsert(
            assets: [changed],
            rootURL: root,
            recursive: false
        )
        candidates = try store.cullingAnalysisCandidates(
            engineVersion:
                AssistedCullingAnalysis.currentEngineVersion
        )
        XCTAssertEqual(changed.fileSize, 5)
        XCTAssertEqual(candidates[0].entry.fileSize, 5)
        XCTAssertNil(candidates[0].cachedAnalysis)
        XCTAssertEqual(candidates[0].manualDecision, .reject)
        XCTAssertTrue(try store.integrityCheck())
    }

    func testAnalyzerCachesResultsSuggestsStacksAndPreservesBytes()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let firstURL = root.appendingPathComponent("first.jpg")
        let secondURL = root.appendingPathComponent("second.jpg")
        try Data([1, 2, 3, 4]).write(to: firstURL)
        try Data([5, 6, 7, 8]).write(to: secondURL)
        let capture = Date(timeIntervalSince1970: 1_700_000_000)
        let assets = [
            try asset(
                id: "first",
                url: firstURL,
                captureDate: capture
            ),
            try asset(
                id: "second",
                url: secondURL,
                captureDate: capture.addingTimeInterval(2)
            ),
        ]
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: assets,
            rootURL: root,
            recursive: false
        )
        let provided = analysis()
        let analyzer = AssistedCullingAnalyzer(
            catalogStore: store,
            analysisProvider: { _ in provided }
        )

        let first = try await analyzer.scan()
        XCTAssertEqual(first.candidateCount, 2)
        XCTAssertEqual(first.analyzedCount, 2)
        XCTAssertEqual(first.cachedCount, 0)
        XCTAssertEqual(first.suggestedStacks, [["first", "second"]])
        XCTAssertTrue(first.unavailablePaths.isEmpty)

        let cached = try await analyzer.scan()
        XCTAssertEqual(cached.analyzedCount, 0)
        XCTAssertEqual(cached.cachedCount, 2)
        XCTAssertEqual(cached.suggestedStacks, first.suggestedStacks)

        let forced = try await analyzer.scan(forceReanalysis: true)
        XCTAssertEqual(forced.analyzedCount, 2)
        XCTAssertEqual(forced.cachedCount, 0)
        XCTAssertEqual(
            try Data(contentsOf: firstURL),
            Data([1, 2, 3, 4])
        )
        XCTAssertEqual(
            try Data(contentsOf: secondURL),
            Data([5, 6, 7, 8])
        )
    }

    func testDefaultOnDeviceAnalyzerProducesBoundedReviewableScores()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let url = root.appendingPathComponent("pattern.jpg")
        try writeAnalysisJPEG(to: url)
        let photo = try asset(
            id: "pattern",
            url: url,
            captureDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let store = CatalogStore(directory: directory)
        try store.upsert(
            assets: [photo],
            rootURL: root,
            recursive: false
        )
        let sourceBefore = try Data(contentsOf: url)
        let result = try await AssistedCullingAnalyzer(
            catalogStore: store
        ).scan()
        let value = try XCTUnwrap(result.analysesByID[photo.id])

        XCTAssertEqual(result.analyzedCount, 1)
        XCTAssertEqual(value.visualFingerprint.count, 64)
        for score in [
            value.subjectSharpness,
            value.globalSharpness,
            value.meanLuminance,
            value.shadowClipping,
            value.highlightClipping,
            value.exposureIssueScore,
            value.misfireScore,
            value.documentScore,
        ] {
            XCTAssertTrue((0...1).contains(score))
        }
        XCTAssertFalse(
            value.evaluation(criteria: .default).reasons.isEmpty
        )
        XCTAssertEqual(try Data(contentsOf: url), sourceBefore)
    }
}

final class FileContentHasherTests: XCTestCase {
    func testStreamingSHA256MatchesKnownDigest() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-hash-\(UUID().uuidString)"
            )
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(
            try FileContentHasher.sha256(for: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}

final class ImageContentHasherTests: XCTestCase {
    func testHashIgnoresContainerMetadataButDetectsPixelChanges()
        throws
    {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        ).appendingPathComponent(
            "rawdesk-image-data-hash-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("first.jpg")
        let secondURL = directory.appendingPathComponent("renamed.jpg")
        let differentURL = directory.appendingPathComponent(
            "different.jpg"
        )
        let matchingImage = try ExactImageDuplicateTestFixture.image(
            variant: 0
        )
        try ExactImageDuplicateTestFixture.writeJPEG(
            matchingImage,
            to: firstURL,
            description: "Short description"
        )
        try ExactImageDuplicateTestFixture.writeJPEG(
            matchingImage,
            to: secondURL,
            description:
                "Different and considerably longer embedded metadata"
        )
        try ExactImageDuplicateTestFixture.writeJPEG(
            ExactImageDuplicateTestFixture.image(variant: 1),
            to: differentURL,
            description: "Different pixels"
        )

        XCTAssertNotEqual(
            try FileContentHasher.sha256(for: firstURL),
            try FileContentHasher.sha256(for: secondURL)
        )
        let firstImageHash = try ImageContentHasher.sha256(
            for: firstURL
        )
        XCTAssertEqual(firstImageHash.count, 64)
        XCTAssertEqual(
            firstImageHash,
            try ImageContentHasher.sha256(for: secondURL)
        )
        XCTAssertNotEqual(
            firstImageHash,
            try ImageContentHasher.sha256(for: differentURL)
        )
    }
}

final class PhotoImportTemplateTests: XCTestCase {
    private func context() throws -> PhotoImportTemplateContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone =
            TimeZone(secondsFromGMT: 0) ?? .current
        let date = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 1,
                    day: 2,
                    hour: 3,
                    minute: 4,
                    second: 5
                )
            )
        )
        return PhotoImportTemplateContext(
            sourceURL: URL(
                fileURLWithPath:
                    "/Pictures/Studio/IMG_0001.CR2"
            ),
            captureDate: date,
            fallbackDate: date,
            cameraMake: "Canon",
            cameraModel: "EOS R5 / Studio",
            sequence: 42
        )
    }

    func testRendererExpandsDeterministicTokensAndEscapedBraces()
        throws {
        let context = try context()
        XCTAssertEqual(
            try PhotoImportTemplateRenderer
                .renderFilenameBase(
                    "{{proof}}-{date:yyyyMMdd}-{date:HHmmss}-{original}-{camera}-{sequence:0000}",
                    context: context
                ),
            "{proof}-20260102-030405-IMG_0001-EOS R5 - Studio-0042"
        )
        XCTAssertEqual(
            try PhotoImportTemplateRenderer
                .renderFolderComponents(
                    "{date:yyyy}/{date:yyyy-MM-dd}/{make}/{folder}",
                    context: context
                ),
            [
                "2026",
                "2026-01-02",
                "Canon",
                "Studio",
            ]
        )
    }

    func testRendererRejectsUnknownAndUnsafeTemplates()
        throws {
        let context = try context()

        XCTAssertThrowsError(
            try PhotoImportTemplateRenderer
                .renderFilenameBase(
                    "{unknown}",
                    context: context
                )
        ) { error in
            XCTAssertEqual(
                error as? PhotoImportTemplateError,
                .unsupportedToken("unknown")
            )
        }
        XCTAssertThrowsError(
            try PhotoImportTemplateRenderer
                .renderFilenameBase(
                    "folder/{original}",
                    context: context
                )
        ) { error in
            XCTAssertEqual(
                error as? PhotoImportTemplateError,
                .filenameContainsFolderSeparator
            )
        }
        XCTAssertThrowsError(
            try PhotoImportTemplateRenderer
                .renderFolderComponents(
                    "../Escape",
                    context: context
                )
        ) { error in
            XCTAssertEqual(
                error as? PhotoImportTemplateError,
                .unsafeFolderComponent("..")
            )
        }
        XCTAssertThrowsError(
            try PhotoImportTemplateRenderer
                .renderFilenameBase(
                    "{sequence:12}",
                    context: context
                )
        ) { error in
            XCTAssertEqual(
                error as? PhotoImportTemplateError,
                .invalidSequenceFormat("12")
            )
        }
    }
}

private enum PhotoImportRemovalTestError: LocalizedError {
    case blocked

    var errorDescription: String? {
        "simulated source-removal failure"
    }
}

private enum PhotoImportInspectionTestError: LocalizedError {
    case decodingFailed

    var errorDescription: String? {
        "simulated destination decoding failure"
    }
}

private final class SourceDispositionInvocationRecorder:
    @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func record(_ url: URL) {
        lock.lock()
        storage.append(url.standardizedFileURL)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        let result = storage
        lock.unlock()
        return result
    }
}

final class PhotoImportServiceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-import-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func testPreflightFindsCatalogAndSelectionDuplicatesByContent()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let existingRoot = base.appendingPathComponent("existing")
        let sources = base.appendingPathComponent("sources")
        let stores = base.appendingPathComponent("stores")
        for directory in [existingRoot, sources, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let existing = existingRoot.appendingPathComponent("a.jpg")
        let catalogDuplicate = sources.appendingPathComponent("b.jpg")
        let newPhoto = sources.appendingPathComponent("c.jpg")
        let selectionDuplicate = sources.appendingPathComponent("d.jpg")
        let unsupported = sources.appendingPathComponent("notes.txt")
        try Data([1, 2, 3, 4]).write(to: existing)
        try Data([1, 2, 3, 4]).write(to: catalogDuplicate)
        try Data([4, 3, 2, 1]).write(to: newPhoto)
        try Data([4, 3, 2, 1]).write(to: selectionDuplicate)
        try Data("not a photo".utf8).write(to: unsupported)

        let store = CatalogStore(directory: stores)
        let inspected = try PhotoLibraryScanner.inspectAsset(
            at: existing,
            userStates: [:]
        ).asset
        try store.upsert(
            assets: [inspected],
            rootURL: existingRoot,
            recursive: false
        )
        XCTAssertNil(try store.contentHash(id: inspected.id))

        let service = PhotoImportService(catalogStore: store)
        let request = PhotoImportRequest(
            sourceURLs: [
                catalogDuplicate,
                newPhoto,
                selectionDuplicate,
                unsupported,
            ],
            recursive: false,
            skipDuplicates: true,
            folderOrganization: .captureDate,
            fileNaming: .customSequence,
            customFilenamePrefix: "Ignored for Add"
        )
        let preflight = try await service.preflight(request)
        XCTAssertEqual(preflight.readyCount, 1)
        XCTAssertEqual(preflight.duplicateCount, 2)
        XCTAssertEqual(preflight.unsupportedCount, 1)
        XCTAssertEqual(preflight.importableCount, 1)
        XCTAssertEqual(preflight.duplicateMatches.count, 2)
        XCTAssertEqual(preflight.duplicateMatches.map(\.sourceURL), [
            catalogDuplicate,
            selectionDuplicate,
        ])
        XCTAssertNotNil(try store.contentHash(id: inspected.id))

        let byName = Dictionary(
            uniqueKeysWithValues: preflight.items.map {
                ($0.sourceURL.lastPathComponent, $0.status)
            }
        )
        guard case .duplicate(.catalog) = byName["b.jpg"] else {
            return XCTFail("Expected an exact catalog duplicate.")
        }
        XCTAssertEqual(byName["c.jpg"], .ready)
        guard case .duplicate(.selection) = byName["d.jpg"] else {
            return XCTFail("Expected an exact selection duplicate.")
        }
        XCTAssertEqual(byName["notes.txt"], .unsupported)

        let result = try await service.execute(preflight)
        XCTAssertEqual(result.importedAssets.map(\.filename), ["c.jpg"])
        XCTAssertEqual(result.skippedDuplicateCount, 2)
        XCTAssertEqual(result.unsupportedCount, 1)
        XCTAssertEqual(result.renamedCount, 0)
        XCTAssertEqual(result.organizedFolderCount, 0)
        XCTAssertEqual(result.duplicateMatches, preflight.duplicateMatches)
        XCTAssertEqual(result.duplicateGroups.count, 2)
        XCTAssertEqual(
            Set(result.duplicateGroups.flatMap(\.matches).map(
                \.matchingPath
            )),
            [existing.path, newPhoto.path]
        )
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(try store.summary()[.allPhotos], 2)
        XCTAssertEqual(try Data(contentsOf: catalogDuplicate), Data([1, 2, 3, 4]))
        XCTAssertEqual(try Data(contentsOf: newPhoto), Data([4, 3, 2, 1]))
    }

    func testCopyImportCarriesXMPVerifiesBytesAndAvoidsNameCollision()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let photo = source.appendingPathComponent("photo.jpg")
        let collision = destination.appendingPathComponent("photo.jpg")
        try Data([1, 2, 3, 4]).write(to: photo)
        try Data([9, 8, 7, 6]).write(to: collision)
        let state = PhotoUserState(
            rating: 4,
            flagged: true,
            keywords: ["Places > Japan > Tokyo"],
            adjustments: PhotoAdjustments(exposure: 0.6)
        )
        try XMPSidecarService.write(state: state, for: photo)
        let sourceHash = try FileContentHasher.sha256(for: photo)
        let sourceSidecar = try XCTUnwrap(
            XMPSidecarService.existingSidecarURL(for: photo)
        )
        let sourceSidecarHash = try FileContentHasher.sha256(
            for: sourceSidecar
        )

        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(catalogStore: store)
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [source],
                mode: .copyToFolder,
                destinationURL: destination,
                recursive: false,
                skipDuplicates: true
            )
        )
        XCTAssertEqual(preflight.readyCount, 1)
        XCTAssertEqual(preflight.items.first?.sidecarURL, sourceSidecar)

        let result = try await service.execute(preflight)
        let copiedPhoto = destination.appendingPathComponent(
            "photo 2.jpg"
        )
        let copiedSidecar = destination.appendingPathComponent(
            "photo 2.xmp"
        )
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.reusedDestinationCount, 0)
        XCTAssertEqual(result.transfers.count, 1)
        XCTAssertEqual(result.transfers.first?.sourceURL, photo)
        XCTAssertEqual(
            result.transfers.first?.sourceSidecarURL,
            sourceSidecar
        )
        XCTAssertEqual(
            result.transfers.first?.catalogedURL,
            copiedPhoto
        )
        XCTAssertEqual(
            result.transfers.first?.contentHash,
            sourceHash
        )
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedPhoto.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedSidecar.path))
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copiedPhoto),
            sourceHash
        )
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copiedSidecar),
            sourceSidecarHash
        )
        XCTAssertEqual(try FileContentHasher.sha256(for: photo), sourceHash)
        XCTAssertEqual(try Data(contentsOf: collision), Data([9, 8, 7, 6]))
        let imported = try XCTUnwrap(result.importedAssets.first)
        XCTAssertEqual(imported.path, copiedPhoto.path)
        XCTAssertEqual(imported.userState, state)
        XCTAssertEqual(try store.contentHash(id: imported.id), sourceHash)
        XCTAssertEqual(try store.summary()[.allPhotos], 1)
    }

    func testCopyImportOrganizesByDateAndAppliesSequenceNaming()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let photo = source.appendingPathComponent("original.jpg")
        let originalBytes = Data([7, 5, 3, 1])
        try originalBytes.write(to: photo)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let fileDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2024,
            month: 3,
            day: 4,
            hour: 12
        )))
        try FileManager.default.setAttributes(
            [.modificationDate: fileDate],
            ofItemAtPath: photo.path
        )
        let sidecarState = PhotoUserState(
            rating: 3,
            keywords: ["Events > Wedding"]
        )
        try XMPSidecarService.write(
            state: sidecarState,
            for: photo
        )
        let sourceHash = try FileContentHasher.sha256(for: photo)

        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(catalogStore: store)
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .copyToFolder,
                destinationURL: destination,
                recursive: false,
                folderOrganization: .captureDate,
                fileNaming: .customSequence,
                customFilenamePrefix: "Wedding / Selects",
                sequenceStart: 42
            )
        )
        let result = try await service.execute(preflight)

        let dateFolder = destination
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent(
                "2024-03-04",
                isDirectory: true
            )
        let copiedPhoto = dateFolder
            .appendingPathComponent("Wedding - Selects-0042.jpg")
        let copiedSidecar = dateFolder
            .appendingPathComponent("Wedding - Selects-0042.xmp")
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.renamedCount, 1)
        XCTAssertEqual(result.organizedFolderCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: copiedPhoto.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: copiedSidecar.path)
        )
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copiedPhoto),
            sourceHash
        )
        XCTAssertEqual(try Data(contentsOf: photo), originalBytes)
        let entry = try XCTUnwrap(
            store.entries(for: .allPhotos).first
        )
        XCTAssertEqual(entry.path, copiedPhoto.path)
        XCTAssertEqual(entry.rootPath, destination.path)
        XCTAssertEqual(entry.userState, sidecarState)
    }

    func testTokenTemplatesOrganizeRenameAvoidCollisionsAndCarryXMP()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent(
            "Studio Intake",
            isDirectory: true
        )
        let destination = base.appendingPathComponent(
            "destination",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let photo = source.appendingPathComponent("IMG_0001.jpg")
        let sourceBytes = Data([8, 6, 7, 5, 3, 0, 9])
        try sourceBytes.write(to: photo)
        let state = PhotoUserState(
            rating: 4,
            keywords: ["Client > Token QA"]
        )
        try XMPSidecarService.write(state: state, for: photo)
        let sourceSidecar = try XCTUnwrap(
            XMPSidecarService.existingSidecarURL(for: photo)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone =
            TimeZone(secondsFromGMT: 0) ?? .current
        let fileDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2024,
                    month: 3,
                    day: 4,
                    hour: 12
                )
            )
        )
        try FileManager.default.setAttributes(
            [.modificationDate: fileDate],
            ofItemAtPath: photo.path
        )
        let sourceHash = try FileContentHasher.sha256(
            for: photo
        )
        let sourceSidecarHash = try FileContentHasher.sha256(
            for: sourceSidecar
        )

        let targetDirectory = destination
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent(
                "Studio Intake",
                isDirectory: true
            )
            .appendingPathComponent(
                "Unknown Camera",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: true
        )
        let collision = targetDirectory.appendingPathComponent(
            "20240304-IMG_0001-007.jpg"
        )
        let collisionBytes = Data([1, 1, 2, 3, 5, 8])
        try collisionBytes.write(to: collision)

        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(catalogStore: store)
        let request = PhotoImportRequest(
            sourceURLs: [photo],
            mode: .copyToFolder,
            destinationURL: destination,
            recursive: false,
            folderOrganization: .customTemplate,
            fileNaming: .tokenTemplate,
            sequenceStart: 7,
            customFolderTemplate:
                "{date:yyyy}/{folder}/{camera}",
            customFilenameTemplate:
                "{date:yyyyMMdd}-{original}-{sequence:000}"
        )
        XCTAssertNil(request.templateValidationMessage)
        let preflight = try await service.preflight(request)
        let result = try await service.execute(preflight)

        let copiedPhoto = targetDirectory
            .appendingPathComponent(
                "20240304-IMG_0001-007 2.jpg"
            )
        let copiedSidecar = targetDirectory
            .appendingPathComponent(
                "20240304-IMG_0001-007 2.xmp"
            )
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.renamedCount, 1)
        XCTAssertEqual(result.organizedFolderCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: collision),
            collisionBytes
        )
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copiedPhoto),
            sourceHash
        )
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copiedSidecar),
            sourceSidecarHash
        )
        XCTAssertEqual(try Data(contentsOf: photo), sourceBytes)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sourceSidecar.path
            )
        )
        let entry = try XCTUnwrap(
            store.entries(for: .allPhotos).first
        )
        XCTAssertEqual(entry.path, copiedPhoto.path)
        XCTAssertEqual(entry.rootPath, destination.path)
        XCTAssertEqual(entry.userState, state)
    }

    func testInvalidTemplateIsRejectedBeforeDestinationMutation()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let photo = source.appendingPathComponent("safe.jpg")
        let bytes = Data([2, 4, 6, 8])
        try bytes.write(to: photo)
        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(catalogStore: store)
        let request = PhotoImportRequest(
            sourceURLs: [photo],
            mode: .copyToFolder,
            destinationURL: destination,
            recursive: false,
            folderOrganization: .customTemplate,
            customFolderTemplate: "../Escape"
        )
        XCTAssertNotNil(request.templateValidationMessage)
        let preflight = try await service.preflight(request)

        do {
            _ = try await service.execute(preflight)
            XCTFail("Expected template validation to fail.")
        } catch let error as PhotoImportServiceError {
            guard case .invalidTemplate = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: photo), bytes)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        XCTAssertEqual(try store.summary()[.allPhotos], 0)
    }

    func testTemplateFolderCannotEscapeDestinationThroughSymlink()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let external = base.appendingPathComponent("external")
        let stores = base.appendingPathComponent("stores")
        for directory in [
            source,
            destination,
            external,
            stores,
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let escapeLink = destination.appendingPathComponent(
            "escape"
        )
        try FileManager.default.createSymbolicLink(
            at: escapeLink,
            withDestinationURL: external
        )
        let photo = source.appendingPathComponent("safe.jpg")
        let bytes = Data([1, 4, 1, 4])
        try bytes.write(to: photo)
        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(catalogStore: store)
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .copyToFolder,
                destinationURL: destination,
                recursive: false,
                folderOrganization: .customTemplate,
                customFolderTemplate: "escape"
            )
        )
        let result = try await service.execute(preflight)

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try Data(contentsOf: photo), bytes)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: external,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        XCTAssertEqual(try store.summary()[.allPhotos], 0)
    }

    func testMoveImportVerifiesCatalogThenUsesTrashHandlerForPhotoAndXMP()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let photo = source.appendingPathComponent("portrait.jpg")
        let bytes = Data([2, 7, 1, 8, 2, 8])
        try bytes.write(to: photo)
        let state = PhotoUserState(
            rating: 5,
            keywords: ["People > Move QA"]
        )
        try XMPSidecarService.write(state: state, for: photo)
        let sourceSidecar = try XCTUnwrap(
            XMPSidecarService.existingSidecarURL(for: photo)
        )
        let photoHash = try FileContentHasher.sha256(for: photo)
        let sidecarHash = try FileContentHasher.sha256(
            for: sourceSidecar
        )

        let store = CatalogStore(directory: stores)
        let recorder = SourceDispositionInvocationRecorder()
        let service = PhotoImportService(
            catalogStore: store,
            sourceRemovalHandler: { url in
                recorder.record(url)
                try FileManager.default.removeItem(at: url)
            }
        )
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .moveToFolder,
                destinationURL: destination,
                recursive: false
            )
        )
        XCTAssertEqual(preflight.importableCount, 1)

        let result = try await service.execute(preflight)
        let movedPhoto = destination.appendingPathComponent(
            "portrait.jpg"
        )
        let movedSidecar = destination.appendingPathComponent(
            "portrait.xmp"
        )
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.movedCount, 1)
        XCTAssertEqual(result.retainedSourceCount, 0)
        XCTAssertEqual(result.retainedSourceSidecarCount, 0)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: photo.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: sourceSidecar.path)
        )
        XCTAssertEqual(recorder.urls, [sourceSidecar, photo])
        XCTAssertEqual(
            try FileContentHasher.sha256(for: movedPhoto),
            photoHash
        )
        XCTAssertEqual(
            try FileContentHasher.sha256(for: movedSidecar),
            sidecarHash
        )
        let imported = try XCTUnwrap(result.importedAssets.first)
        XCTAssertEqual(imported.path, movedPhoto.path)
        XCTAssertEqual(imported.userState, state)
        XCTAssertEqual(try store.contentHash(id: imported.id), photoHash)
        XCTAssertEqual(try store.summary()[.allPhotos], 1)
    }

    func testMoveRetainsSourceWhenRemovalFailsAfterCatalogCommit()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let photo = source.appendingPathComponent("safe.jpg")
        let bytes = Data([4, 2, 4, 2])
        try bytes.write(to: photo)
        let sourceHash = try FileContentHasher.sha256(for: photo)
        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(
            catalogStore: store,
            sourceRemovalHandler: { _ in
                throw PhotoImportRemovalTestError.blocked
            }
        )
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .moveToFolder,
                destinationURL: destination,
                recursive: false
            )
        )
        let result = try await service.execute(preflight)
        let copied = destination.appendingPathComponent("safe.jpg")

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.copiedCount, 1)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(result.retainedSourceCount, 1)
        XCTAssertEqual(result.retainedSourceSidecarCount, 0)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(
            result.warnings[0].contains(
                "source cleanup did not complete"
            )
        )
        XCTAssertEqual(try Data(contentsOf: photo), bytes)
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copied),
            sourceHash
        )
        XCTAssertEqual(
            try store.entries(for: .allPhotos).map(\.path),
            [copied.path]
        )
    }

    func testMoveRetainsPhotoAndSidecarWhenSidecarTrashFails()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let photo = source.appendingPathComponent("sidecar.jpg")
        try Data([9, 1, 9, 1]).write(to: photo)
        try XMPSidecarService.write(
            state: PhotoUserState(rating: 3),
            for: photo
        )
        let sourceSidecar = try XCTUnwrap(
            XMPSidecarService.existingSidecarURL(for: photo)
        )
        let service = PhotoImportService(
            catalogStore: CatalogStore(directory: stores),
            sourceRemovalHandler: { url in
                if url.pathExtension.lowercased() == "xmp" {
                    throw PhotoImportRemovalTestError.blocked
                }
                try FileManager.default.removeItem(at: url)
            }
        )
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .moveToFolder,
                destinationURL: destination,
                recursive: false
            )
        )
        let result = try await service.execute(preflight)

        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(result.retainedSourceCount, 1)
        XCTAssertEqual(result.retainedSourceSidecarCount, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: photo.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sourceSidecar.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination
                    .appendingPathComponent("sidecar.jpg").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: destination
                    .appendingPathComponent("sidecar.xmp").path
            )
        )
        XCTAssertTrue(
            result.warnings.contains {
                $0.contains("source cleanup did not complete")
            }
        )
    }

    func testSourceChangeBeforeCopyNeverInvokesTrashHandler()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let photo = source.appendingPathComponent("changed.jpg")
        try Data([1, 2, 3, 4]).write(to: photo)
        let recorder = SourceDispositionInvocationRecorder()
        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(
            catalogStore: store,
            sourceRemovalHandler: { url in
                recorder.record(url)
                try FileManager.default.removeItem(at: url)
            }
        )
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .moveToFolder,
                destinationURL: destination,
                recursive: false
            )
        )

        let changedBytes = Data([9, 8, 7, 6])
        try changedBytes.write(to: photo, options: [.atomic])
        let result = try await service.execute(preflight)

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: photo), changedBytes)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        XCTAssertEqual(try store.summary()[.allPhotos], 0)
    }

    func testDestinationDecodingFailureRetainsSourceAndSkipsTrash()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let photo = source.appendingPathComponent("decode.jpg")
        let bytes = Data([4, 8, 15, 16, 23, 42])
        try bytes.write(to: photo)
        let recorder = SourceDispositionInvocationRecorder()
        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(
            catalogStore: store,
            sourceRemovalHandler: { url in
                recorder.record(url)
                try FileManager.default.removeItem(at: url)
            },
            assetInspectionHandler: { _, _, _ in
                throw PhotoImportInspectionTestError.decodingFailed
            }
        )
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .moveToFolder,
                destinationURL: destination,
                recursive: false
            )
        )
        let result = try await service.execute(preflight)

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(
            result.failures[0].contains("decoding failure")
        )
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: photo), bytes)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        XCTAssertEqual(try store.summary()[.allPhotos], 0)
    }

    func testMoveRejectsDestinationInsideSelectedSource()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = source.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let photo = source.appendingPathComponent("keep.jpg")
        let bytes = Data([6, 2, 6, 4])
        try bytes.write(to: photo)
        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(catalogStore: store)
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [source],
                mode: .moveToFolder,
                destinationURL: destination,
                recursive: true
            )
        )

        do {
            _ = try await service.execute(preflight)
            XCTFail("Expected a conflicting Move destination.")
        } catch let error as PhotoImportServiceError {
            XCTAssertEqual(error, .moveDestinationConflictsWithSource)
        }
        XCTAssertEqual(try Data(contentsOf: photo), bytes)
        XCTAssertEqual(try store.summary()[.allPhotos], 0)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testMoveNeverMovesCatalogedPhotoAtItsCurrentPath()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let photo = source.appendingPathComponent("cataloged.jpg")
        let bytes = Data([1, 6, 1, 8])
        try bytes.write(to: photo)
        let store = CatalogStore(directory: stores)
        let asset = try PhotoLibraryScanner.inspectAsset(
            at: photo,
            userStates: [:]
        ).asset
        try store.upsert(
            assets: [asset],
            rootURL: source,
            recursive: false
        )
        let service = PhotoImportService(catalogStore: store)
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .moveToFolder,
                destinationURL: destination,
                recursive: false,
                skipDuplicates: false
            )
        )

        XCTAssertEqual(preflight.duplicateCount, 1)
        XCTAssertEqual(preflight.catalogedSourceMoveConflictCount, 1)
        XCTAssertEqual(preflight.importableCount, 0)
        let result = try await service.execute(preflight)
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(result.skippedDuplicateCount, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(try Data(contentsOf: photo), bytes)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        XCTAssertEqual(try store.summary()[.allPhotos], 1)
    }

    func testDateOrganizationDoesNotReplaceConflictingFolderFile()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [source, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let photo = source.appendingPathComponent("photo.jpg")
        try Data([1, 3, 5, 7]).write(to: photo)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let fileDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2024,
            month: 3,
            day: 4,
            hour: 12
        )))
        try FileManager.default.setAttributes(
            [.modificationDate: fileDate],
            ofItemAtPath: photo.path
        )
        let yearConflict = destination.appendingPathComponent("2024")
        let conflictBytes = Data("keep me".utf8)
        try conflictBytes.write(to: yearConflict)

        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(catalogStore: store)
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [photo],
                mode: .copyToFolder,
                destinationURL: destination,
                recursive: false,
                folderOrganization: .captureDate
            )
        )
        let result = try await service.execute(preflight)

        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(
            result.failures[0].contains(
                "import folder 2024 could not be created"
            )
        )
        XCTAssertEqual(try Data(contentsOf: yearConflict), conflictBytes)
        XCTAssertEqual(try store.summary()[.allPhotos], 0)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent),
            ["2024"]
        )
    }

    func testCancelDuringCatalogingReturnsCompletedPhotos()
        async throws {
        let base = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(
                at: base
            )
        }
        let firstRoot = base.appendingPathComponent(
            "a-source"
        )
        let secondRoot = base.appendingPathComponent(
            "b-source"
        )
        let stores = base.appendingPathComponent(
            "stores"
        )
        for directory in [
            firstRoot,
            secondRoot,
            stores,
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let first = firstRoot.appendingPathComponent(
            "first.jpg"
        )
        let second = secondRoot.appendingPathComponent(
            "second.jpg"
        )
        try Data([1, 2, 3]).write(to: first)
        try Data([4, 5, 6]).write(to: second)

        let store = CatalogStore(directory: stores)
        let service = PhotoImportService(
            catalogStore: store
        )
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [
                    firstRoot,
                    secondRoot,
                ],
                recursive: false
            )
        )
        let task = Task {
            try await service.execute(preflight) {
                progress in
                if progress.phase == .cataloging,
                   progress.completed == 1 {
                    withUnsafeCurrentTask {
                        $0?.cancel()
                    }
                }
            }
        }
        let result = try await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(
            try store.summary()[.allPhotos],
            1
        )
        XCTAssertEqual(
            try store.entries(for: .allPhotos)
                .map(\.path),
            [first.path]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: first.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: second.path
            )
        )
    }

    func testCancelAfterMoveCatalogingRetainsEveryOriginal()
        async throws {
        let base = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(
                at: base
            )
        }
        let source = base.appendingPathComponent(
            "source"
        )
        let destination = base.appendingPathComponent(
            "destination"
        )
        let stores = base.appendingPathComponent(
            "stores"
        )
        for directory in [
            source,
            destination,
            stores,
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let first = source.appendingPathComponent(
            "first.jpg"
        )
        let second = source.appendingPathComponent(
            "second.jpg"
        )
        try Data([7, 8, 9]).write(to: first)
        try Data([10, 11, 12]).write(to: second)

        let store = CatalogStore(directory: stores)
        let recorder = SourceDispositionInvocationRecorder()
        let service = PhotoImportService(
            catalogStore: store,
            sourceRemovalHandler: { url in
                recorder.record(url)
                try FileManager.default.removeItem(at: url)
            }
        )
        let preflight = try await service.preflight(
            PhotoImportRequest(
                sourceURLs: [source],
                mode: .moveToFolder,
                destinationURL: destination,
                recursive: false
            )
        )
        let task = Task {
            try await service.execute(preflight) {
                progress in
                if progress.phase == .cataloging,
                   progress.total > 0,
                   progress.completed
                    == progress.total {
                    withUnsafeCurrentTask {
                        $0?.cancel()
                    }
                }
            }
        }
        let result = try await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(
            result.retainedSourceCount,
            2
        )
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(
            try store.summary()[.allPhotos],
            2
        )
        for filename in [
            "first.jpg",
            "second.jpg",
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: source
                        .appendingPathComponent(
                            filename
                        ).path
                )
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: destination
                        .appendingPathComponent(
                            filename
                        ).path
                )
            )
        }
    }

    func testPreflightRespectsRecursiveFolderOption() async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source")
        let nested = source.appendingPathComponent("nested")
        let stores = base.appendingPathComponent("stores")
        for directory in [nested, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        try Data([1]).write(
            to: source.appendingPathComponent("top.jpg")
        )
        try Data([2]).write(
            to: nested.appendingPathComponent("nested.jpg")
        )
        let service = PhotoImportService(
            catalogStore: CatalogStore(directory: stores)
        )

        let shallow = try await service.preflight(PhotoImportRequest(
            sourceURLs: [source],
            recursive: false
        ))
        XCTAssertEqual(shallow.readyCount, 1)
        XCTAssertEqual(
            shallow.items.map(\.sourceURL.lastPathComponent),
            ["top.jpg"]
        )

        let recursive = try await service.preflight(PhotoImportRequest(
            sourceURLs: [source],
            recursive: true
        ))
        XCTAssertEqual(recursive.readyCount, 2)
        XCTAssertEqual(
            Set(recursive.items.map(\.sourceURL.lastPathComponent)),
            ["top.jpg", "nested.jpg"]
        )
    }
}

private actor AutoImportProgressRecorder {
    private(set) var phases:
        [PhotoImportProgressPhase] = []

    func record(_ phase: PhotoImportProgressPhase) {
        phases.append(phase)
    }
}

final class AutoImportTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        ).appendingPathComponent(
            "rawdesk-auto-import-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func executeSQL(
        _ sql: String,
        databaseURL: URL
    ) throws {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            throw NSError(
                domain: "RAWDeskAutoImportTests",
                code: Int(openResult),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Could not open isolated test catalog.",
                ]
            )
        }
        defer { sqlite3_close_v2(database) }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(
            database,
            sql,
            nil,
            nil,
            &errorMessage
        )
        guard result == SQLITE_OK else {
            let message = errorMessage.map {
                String(cString: $0)
            } ?? "SQLite test setup failed."
            if let errorMessage {
                sqlite3_free(errorMessage)
            }
            throw NSError(
                domain: "RAWDeskAutoImportTests",
                code: Int(result),
                userInfo: [
                    NSLocalizedDescriptionKey: message,
                ]
            )
        }
    }

    func testSettingsNormalizeValidateAndPersist() throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent(
            "watched",
            isDirectory: true
        )
        let destination = base.appendingPathComponent(
            "destination",
            isDirectory: true
        )
        let support = base.appendingPathComponent(
            "support",
            isDirectory: true
        )
        for directory in [watched, destination, support] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        let settings = AutoImportSettings(
            enabled: true,
            watchedFolderURL: watched,
            destinationFolderURL: destination,
            sourceHandling: .moveSourceToTrash,
            folderOrganization: .captureDate,
            fileNaming: .customSequence,
            customFilenamePrefix: "  Studio / Session  ",
            sequenceStart: 1_500_000,
            keywords: [
                " Places > Japan ",
                "places|japan",
                "Client",
            ],
            developmentPreset: .clean,
            settleInterval: 0.1
        )
        XCTAssertNil(settings.validationMessage())
        XCTAssertEqual(
            settings.customFilenamePrefix,
            "Studio - Session"
        )
        XCTAssertEqual(settings.sequenceStart, 999_999)
        XCTAssertEqual(
            settings.keywords,
            ["Places|Japan", "Client"]
        )
        XCTAssertEqual(settings.settleInterval, 0.5)

        let store = AutoImportSettingsStore(directory: support)
        store.save(settings)
        XCTAssertEqual(store.load(), settings)
        XCTAssertEqual(
            AutoImportSettingsStore(directory: support)
                .load().sourceHandling,
            .moveSourceToTrash
        )

        var overlapping = settings
        overlapping.destinationFolderURL = watched
            .appendingPathComponent("output")
        try FileManager.default.createDirectory(
            at: try XCTUnwrap(
                overlapping.destinationFolderURL
            ),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(
            overlapping.validationMessage()?
                .contains("non-nested") == true
        )
    }

    func testLegacySettingsDefaultTemplatesAndRejectUnsafeTemplate()
        throws {
        let legacy = Data(
            """
            {
              "enabled": false,
              "folderOrganization": "singleFolder",
              "fileNaming": "customSequence",
              "customFilenamePrefix": "Legacy",
              "sequenceStart": 17,
              "keywords": [],
              "settleInterval": 2
            }
            """.utf8
        )
        var settings = try JSONDecoder().decode(
            AutoImportSettings.self,
            from: legacy
        )
        XCTAssertEqual(
            settings.customFolderTemplate,
            PhotoImportTemplateRenderer.defaultFolderTemplate
        )
        XCTAssertEqual(
            settings.customFilenameTemplate,
            PhotoImportTemplateRenderer.defaultFilenameTemplate
        )
        XCTAssertFalse(settings.analyzePeopleAfterImport)
        XCTAssertEqual(settings.sourceHandling, .keepSource)
        XCTAssertTrue(settings.usesSequence)

        settings.folderOrganization = .customTemplate
        settings.customFolderTemplate = "../Escape"
        XCTAssertTrue(
            settings.templateValidationMessage?
                .contains("unsafe") == true
        )

        settings.customFolderTemplate =
            "{date:yyyy}/{camera}"
        settings.fileNaming = .tokenTemplate
        settings.customFilenameTemplate =
            "{original}-{sequence:00000}"
        settings.analyzePeopleAfterImport = true
        XCTAssertNil(settings.templateValidationMessage)
        XCTAssertTrue(settings.usesSequence)
        XCTAssertEqual(
            try JSONDecoder().decode(
                AutoImportSettings.self,
                from: JSONEncoder().encode(settings)
            ),
            settings
        )
    }

    func testProductionSourceDispositionHasNoPermanentDeleteFallback()
        throws {
        let repositoryRoot = URL(
            fileURLWithPath: #filePath
        )
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        let autoImportSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/RAWDesk/Services/AutoImportService.swift"
            ),
            encoding: .utf8
        )
        XCTAssertFalse(autoImportSource.contains("removeItem("))

        let importServiceSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/RAWDesk/Services/PhotoImportService.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(importServiceSource.contains("trashItem("))
        let dispositionStart = try XCTUnwrap(
            importServiceSource.range(
                of: "public func moveVerifiedSourcesToTrash"
            )
        )
        let searchRange = Range(
            uncheckedBounds: (
                dispositionStart.lowerBound,
                importServiceSource.endIndex
            )
        )
        let dispositionEnd = try XCTUnwrap(
            importServiceSource.range(
                of: "private func isDescendant",
                range: searchRange
            )
        )
        let dispositionRange = Range(
            uncheckedBounds: (
                dispositionStart.lowerBound,
                dispositionEnd.lowerBound
            )
        )
        let dispositionImplementation =
            importServiceSource[dispositionRange]
        XCTAssertFalse(
            dispositionImplementation.contains("removeItem(")
        )
    }

    func testDefaultAutoImportRetainsSourceWithoutDisposition()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("default-keep.jpg")
        let bytes = Data([1, 3, 3, 7])
        try bytes.write(to: source)

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        let importService = PhotoImportService(
            catalogStore: catalog,
            sourceRemovalHandler: { url in
                recorder.record(url)
                try FileManager.default.removeItem(at: url)
            }
        )
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: importService
        )
        let settings = AutoImportSettings(
            enabled: true,
            watchedFolderURL: watched,
            destinationFolderURL: destination
        )

        XCTAssertEqual(settings.sourceHandling, .keepSource)
        let result = try await service.run(
            settings: settings,
            sourceURLs: [source]
        )
        let target = destination.appendingPathComponent(
            "default-keep.jpg"
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertEqual(
            try catalog.entries(for: .allPhotos).map(\.path),
            [target.path]
        )
    }

    func testExplicitKeepSourceNeverInvokesDispositionHandler()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("explicit-keep.jpg")
        let bytes = Data([2, 4, 6, 8])
        try bytes.write(to: source)

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    recorder.record(url)
                    try FileManager.default.removeItem(at: url)
                }
            )
        )
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                sourceHandling: .keepSource
            ),
            sourceURLs: [source]
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }

    func testMoveSourceToTrashRunsOnceAfterVerificationAndCatalogCommit()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("trash-after-commit.jpg")
        let bytes = Data([5, 10, 15, 20])
        try bytes.write(to: source)
        let sourceHash = try FileContentHasher.sha256(for: source)
        let target = destination.appendingPathComponent(
            source.lastPathComponent
        )

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        let importService = PhotoImportService(
            catalogStore: catalog,
            sourceRemovalHandler: { url in
                recorder.record(url)
                XCTAssertEqual(url.standardizedFileURL, source)
                XCTAssertEqual(
                    try FileContentHasher.sha256(for: target),
                    sourceHash
                )
                XCTAssertEqual(
                    try catalog.entries(for: .allPhotos).map(\.path),
                    [target.path]
                )
                try FileManager.default.removeItem(at: url)
            }
        )
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: importService
        )
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                sourceHandling: .moveSourceToTrash
            ),
            sourceURLs: [source]
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 1)
        XCTAssertEqual(recorder.urls, [source])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: source.path)
        )
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testTrashFailureKeepsSourceAndDestinationWithoutFallback()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("trash-blocked.jpg")
        let bytes = Data([9, 9, 8, 8])
        try bytes.write(to: source)

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    recorder.record(url)
                    throw PhotoImportRemovalTestError.blocked
                }
            )
        )
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                sourceHandling: .moveSourceToTrash
            ),
            sourceURLs: [source]
        )
        let target = destination.appendingPathComponent(
            source.lastPathComponent
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertEqual(
            result.importResult.retainedSourceCount,
            1
        )
        XCTAssertEqual(recorder.urls, [source])
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(
            result.warnings.contains {
                $0.contains("not permanently deleted")
            }
        )
    }

    func testCopyFailureBeforeDispositionRetainsSource()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("copy-fails.jpg")
        let bytes = Data([1, 1, 2, 3, 5])
        try bytes.write(to: source)

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    recorder.record(url)
                    try FileManager.default.removeItem(at: url)
                }
            )
        )
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                sourceHandling: .moveSourceToTrash
            ),
            sourceURLs: [source]
        ) { progress in
            if progress.phase == .copying,
               progress.completed == 0 {
                try? FileManager.default.removeItem(
                    at: destination
                )
            }
        }

        XCTAssertEqual(result.importResult.importedCount, 0)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try catalog.summary()[.allPhotos], 0)
    }

    func testDestinationHashMismatchBeforeDispositionRetainsSource()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("hash-mismatch.jpg")
        let sourceBytes = Data([3, 1, 4, 1, 5])
        let changedBytes = Data([2, 7, 1, 8, 2])
        try sourceBytes.write(to: source)
        let target = destination.appendingPathComponent(
            source.lastPathComponent
        )

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    recorder.record(url)
                    try FileManager.default.removeItem(at: url)
                }
            )
        )
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                sourceHandling: .moveSourceToTrash
            ),
            sourceURLs: [source]
        ) { progress in
            if progress.phase == .removingSources,
               progress.completed == 0 {
                try? changedBytes.write(
                    to: target,
                    options: [.atomic]
                )
            }
        }

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertEqual(
            result.importResult.retainedSourceCount,
            1
        )
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: target), changedBytes)
        XCTAssertTrue(
            result.warnings.contains {
                $0.contains("source cleanup did not complete")
            }
        )
    }

    func testCatalogFailureBeforeDispositionRetainsSource()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("catalog-fails.jpg")
        let bytes = Data([6, 2, 6, 4])
        try bytes.write(to: source)

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        try executeSQL(
            """
            CREATE TRIGGER fail_auto_import_catalog_insert
            BEFORE INSERT ON catalog_photos
            BEGIN
                SELECT RAISE(FAIL, 'simulated catalog persistence failure');
            END;
            """,
            databaseURL: stores.appendingPathComponent(
                "catalog.sqlite"
            )
        )
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    recorder.record(url)
                    try FileManager.default.removeItem(at: url)
                }
            )
        )
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                sourceHandling: .moveSourceToTrash
            ),
            sourceURLs: [source]
        )

        XCTAssertEqual(result.importResult.importedCount, 0)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        XCTAssertEqual(try catalog.summary()[.allPhotos], 0)
        XCTAssertEqual(result.retryURLs, [source])
    }

    func testMetadataPersistenceFailureBlocksDisposition()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("metadata-fails.jpg")
        let bytes = Data([8, 5, 3, 0, 9])
        try bytes.write(to: source)

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        try executeSQL(
            """
            CREATE TRIGGER fail_auto_import_state_update
            BEFORE UPDATE OF state_json ON catalog_photos
            BEGIN
                SELECT RAISE(FAIL, 'simulated metadata persistence failure');
            END;
            """,
            databaseURL: stores.appendingPathComponent(
                "catalog.sqlite"
            )
        )
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    recorder.record(url)
                    try FileManager.default.removeItem(at: url)
                }
            )
        )
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                sourceHandling: .moveSourceToTrash,
                keywords: ["Persistence Guard"]
            ),
            sourceURLs: [source]
        )
        let target = destination.appendingPathComponent(
            source.lastPathComponent
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertEqual(
            result.importResult.retainedSourceCount,
            1
        )
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertTrue(
            result.warnings.contains {
                $0.contains("could not be persisted")
            }
        )
    }

    func testCancellationBeforeDispositionRetainsSource()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("cancel-cleanup.jpg")
        let bytes = Data([1, 6, 1, 8])
        try bytes.write(to: source)

        let recorder = SourceDispositionInvocationRecorder()
        let catalog = CatalogStore(directory: stores)
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    recorder.record(url)
                    try FileManager.default.removeItem(at: url)
                }
            )
        )
        let task = Task {
            try await service.run(
                settings: AutoImportSettings(
                    enabled: true,
                    watchedFolderURL: watched,
                    destinationFolderURL: destination,
                    sourceHandling: .moveSourceToTrash
                ),
                sourceURLs: [source]
            ) { progress in
                if progress.phase == .removingSources,
                   progress.completed == 0 {
                    withUnsafeCurrentTask {
                        $0?.cancel()
                    }
                }
            }
        }
        let result = try await task.value
        let target = destination.appendingPathComponent(
            source.lastPathComponent
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertEqual(
            result.importResult.retainedSourceCount,
            1
        )
        XCTAssertTrue(recorder.urls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertTrue(
            result.warnings.contains {
                $0.contains("source cleanup was canceled")
            }
        )
    }

    func testStabilityTrackerWaitsForPhotoAndSidecar()
        throws {
        let photo = URL(
            fileURLWithPath: "/tmp/auto-import.jpg"
        )
        let sidecar = URL(
            fileURLWithPath: "/tmp/auto-import.xmp"
        )
        let start = Date(timeIntervalSince1970: 10_000)
        var tracker = AutoImportStabilityTracker(
            settleInterval: 2
        )
        let first = AutoImportFileSnapshot(
            url: photo,
            fileSize: 100,
            modificationDate:
                start.addingTimeInterval(-10)
        )
        XCTAssertTrue(
            tracker.readyCandidates(
                from: [first],
                now: start
            ).isEmpty
        )
        XCTAssertTrue(
            tracker.readyCandidates(
                from: [first],
                now: start.addingTimeInterval(1.9)
            ).isEmpty
        )

        let withSidecar = AutoImportFileSnapshot(
            url: photo,
            fileSize: 100,
            modificationDate:
                start.addingTimeInterval(-10),
            sidecarURL: sidecar,
            sidecarFileSize: 20,
            sidecarModificationDate:
                start.addingTimeInterval(1)
        )
        XCTAssertTrue(
            tracker.readyCandidates(
                from: [withSidecar],
                now: start.addingTimeInterval(2)
            ).isEmpty
        )
        XCTAssertEqual(
            tracker.readyCandidates(
                from: [withSidecar],
                now: start.addingTimeInterval(4.1)
            ),
            [photo]
        )
        XCTAssertTrue(
            tracker.readyCandidates(
                from: [withSidecar],
                now: start.addingTimeInterval(8)
            ).isEmpty
        )

        var changed = withSidecar
        changed.fileSize = 101
        XCTAssertTrue(
            tracker.readyCandidates(
                from: [changed],
                now: start.addingTimeInterval(9)
            ).isEmpty
        )
        XCTAssertEqual(
            tracker.readyCandidates(
                from: [changed],
                now: start.addingTimeInterval(11.1)
            ),
            [photo]
        )
    }

    func testSnapshotDiscoveryUsesOnlySupportedDirectChildren()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let nested = watched.appendingPathComponent("nested")
        let stores = base.appendingPathComponent("stores")
        for directory in [nested, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let top = watched.appendingPathComponent("top.jpg")
        let sidecar = watched.appendingPathComponent("top.xmp")
        try Data([1, 2, 3]).write(to: top)
        try Data("<x:xmpmeta/>".utf8).write(to: sidecar)
        try Data([4]).write(
            to: nested.appendingPathComponent("nested.jpg")
        )
        try Data([5]).write(
            to: watched.appendingPathComponent(".hidden.jpg")
        )
        try Data([6]).write(
            to: watched.appendingPathComponent("notes.txt")
        )

        let service = AutoImportService(
            catalogStore: CatalogStore(directory: stores)
        )
        let snapshots = try await service.snapshots(
            in: watched
        )
        XCTAssertEqual(snapshots.map(\.url), [top])
        XCTAssertEqual(snapshots.first?.sidecarURL, sidecar)
        XCTAssertEqual(snapshots.first?.fileSize, 3)
    }

    func testVerifiedAutoImportTrashesPhotoAndXMPAndAppliesInformation()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("capture.jpg")
        let sourceBytes = Data([8, 6, 7, 5, 3, 0, 9])
        try sourceBytes.write(to: source)
        try XMPSidecarService.write(
            state: PhotoUserState(
                rating: 4,
                keywords: ["Existing"]
            ),
            for: source
        )
        let sourceSidecar = try XCTUnwrap(
            XMPSidecarService.existingSidecarURL(for: source)
        )
        let sourceHash = try FileContentHasher.sha256(
            for: source
        )
        let sourceSidecarHash = try FileContentHasher.sha256(
            for: sourceSidecar
        )

        let catalog = CatalogStore(directory: stores)
        let recorder = SourceDispositionInvocationRecorder()
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    recorder.record(url)
                    try FileManager.default.removeItem(at: url)
                }
            )
        )
        let settings = AutoImportSettings(
            enabled: true,
            watchedFolderURL: watched,
            destinationFolderURL: destination,
            sourceHandling: .moveSourceToTrash,
            fileNaming: .customSequence,
            customFilenamePrefix: "Tethered",
            sequenceStart: 7,
            keywords: ["Studio", "Client > Session"],
            developmentPreset: .vivid
        )
        let result = try await service.run(
            settings: settings,
            sourceURLs: [source]
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: source.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sourceSidecar.path
            )
        )
        XCTAssertEqual(recorder.urls, [sourceSidecar, source])

        let copied = destination
            .appendingPathComponent("Tethered-0007.jpg")
        let copiedSidecar = destination
            .appendingPathComponent("Tethered-0007.xmp")
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copied),
            sourceHash
        )
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copiedSidecar),
            sourceSidecarHash
        )
        let imported = try XCTUnwrap(
            result.importResult.importedAssets.first
        )
        XCTAssertEqual(imported.path, copied.path)
        XCTAssertEqual(imported.userState.rating, 4)
        XCTAssertEqual(
            imported.userState.keywords,
            ["Existing", "Studio", "Client|Session"]
        )
        XCTAssertEqual(
            imported.userState.adjustments,
            DevelopmentPreset.vivid.adjustments.normalized
        )
        let cataloged = try XCTUnwrap(
            catalog.entries(for: .allPhotos).first
        )
        XCTAssertEqual(cataloged.path, copied.path)
        XCTAssertEqual(
            cataloged.userState,
            imported.userState
        )
        XCTAssertEqual(
            try catalog.contentHash(id: imported.id),
            sourceHash
        )
    }

    func testAutoImportAppliesTokenTemplatesBeforeTrashDisposition()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("capture.jpg")
        try Data([3, 1, 4, 1, 5, 9]).write(to: source)
        try XMPSidecarService.write(
            state: PhotoUserState(rating: 5),
            for: source
        )
        let sourceSidecar = try XCTUnwrap(
            XMPSidecarService.existingSidecarURL(for: source)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone =
            TimeZone(secondsFromGMT: 0) ?? .current
        let fileDate = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: 2025,
                    month: 6,
                    day: 7,
                    hour: 8
                )
            )
        )
        try FileManager.default.setAttributes(
            [.modificationDate: fileDate],
            ofItemAtPath: source.path
        )
        let photoHash = try FileContentHasher.sha256(for: source)
        let sidecarHash = try FileContentHasher.sha256(
            for: sourceSidecar
        )
        let catalog = CatalogStore(directory: stores)
        let service = AutoImportService(
            catalogStore: catalog,
            photoImportService: PhotoImportService(
                catalogStore: catalog,
                sourceRemovalHandler: { url in
                    try FileManager.default.removeItem(at: url)
                }
            )
        )
        let settings = AutoImportSettings(
            enabled: true,
            watchedFolderURL: watched,
            destinationFolderURL: destination,
            sourceHandling: .moveSourceToTrash,
            folderOrganization: .customTemplate,
            fileNaming: .tokenTemplate,
            sequenceStart: 9,
            customFolderTemplate:
                "{date:yyyy}/{folder}/{camera}",
            customFilenameTemplate:
                "{original}-{sequence:000}"
        )
        let result = try await service.run(
            settings: settings,
            sourceURLs: [source]
        )
        let targetDirectory = destination
            .appendingPathComponent("2025")
            .appendingPathComponent("watched")
            .appendingPathComponent("Unknown Camera")
        let copied = targetDirectory.appendingPathComponent(
            "capture-009.jpg"
        )
        let copiedSidecar = targetDirectory.appendingPathComponent(
            "capture-009.xmp"
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: source.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sourceSidecar.path
            )
        )
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copied),
            photoHash
        )
        XCTAssertEqual(
            try FileContentHasher.sha256(for: copiedSidecar),
            sidecarHash
        )
        XCTAssertEqual(
            try catalog.entries(for: .allPhotos).map(\.path),
            [copied.path]
        )
    }

    func testAutoImportCanAnalyzeImportedPhotosLocallyForPeople()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("portrait.jpg")
        let sourceBytes = Data([9, 2, 6, 5, 3, 5])
        try sourceBytes.write(to: source)

        let catalog = CatalogStore(directory: stores)
        let analyzer = PeopleAnalyzer(
            catalogStore: catalog
        ) { _ in
            [
                PeopleFaceDetection(
                    boundingBox: CGRect(
                        x: 0.2,
                        y: 0.25,
                        width: 0.3,
                        height: 0.4
                    ),
                    confidence: 0.94,
                    captureQuality: 0.83,
                    featurePrintData: Data([4, 2])
                ),
            ]
        }
        let service = AutoImportService(
            catalogStore: catalog,
            peopleAnalyzer: analyzer
        )
        let progressRecorder = AutoImportProgressRecorder()
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                analyzePeopleAfterImport: true
            ),
            sourceURLs: [source]
        ) { progress in
            await progressRecorder.record(progress.phase)
        }

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(
            result.importResult.peopleAnalyzedCount,
            1
        )
        XCTAssertEqual(result.importResult.peopleCachedCount, 0)
        XCTAssertEqual(result.importResult.peopleFaceCount, 1)
        XCTAssertEqual(
            result.importResult.peopleUnavailableCount,
            0
        )
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: source.path)
        )
        XCTAssertEqual(try catalog.catalogFaces().count, 1)
        XCTAssertEqual(try catalog.catalogPeople(), [])
        XCTAssertEqual(try catalog.summary().faceCount, 1)
        let progressPhases = await progressRecorder.phases
        XCTAssertTrue(
            progressPhases.contains(.analyzingPeople)
        )
        XCTAssertEqual(
            try Data(
                contentsOf:
                    destination.appendingPathComponent(
                        "portrait.jpg"
                    )
            ),
            sourceBytes
        )
    }

    func testPeopleAnalysisFailureNeverReversesSafeAutoImport()
        async throws {
        struct DetectionFailure: Error {}

        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let source = watched.appendingPathComponent("keep-import.jpg")
        let bytes = Data([2, 7, 1, 8, 2, 8])
        try bytes.write(to: source)

        let catalog = CatalogStore(directory: stores)
        let analyzer = PeopleAnalyzer(
            catalogStore: catalog
        ) { _ in
            throw DetectionFailure()
        }
        let service = AutoImportService(
            catalogStore: catalog,
            peopleAnalyzer: analyzer
        )
        let result = try await service.run(
            settings: AutoImportSettings(
                enabled: true,
                watchedFolderURL: watched,
                destinationFolderURL: destination,
                analyzePeopleAfterImport: true
            ),
            sourceURLs: [source]
        )
        let target = destination.appendingPathComponent(
            "keep-import.jpg"
        )

        XCTAssertEqual(result.importResult.importedCount, 1)
        XCTAssertEqual(result.removedSourceCount, 0)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(
            result.importResult.peopleUnavailableCount,
            1
        )
        XCTAssertTrue(
            result.warnings.contains {
                $0.contains("completed safely")
            }
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: source.path)
        )
        XCTAssertEqual(try Data(contentsOf: target), bytes)
        XCTAssertEqual(try catalog.catalogFaces(), [])
        XCTAssertEqual(try catalog.summary()[.allPhotos], 1)
    }

    func testExactDuplicateIsRetainedForReview()
        async throws {
        let base = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let watched = base.appendingPathComponent("watched")
        let destination = base.appendingPathComponent("destination")
        let stores = base.appendingPathComponent("stores")
        for directory in [watched, destination, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        let catalog = CatalogStore(directory: stores)
        let service = AutoImportService(catalogStore: catalog)
        let settings = AutoImportSettings(
            enabled: true,
            watchedFolderURL: watched,
            destinationFolderURL: destination
        )

        let original = watched.appendingPathComponent("first.jpg")
        let bytes = Data([2, 4, 6, 8])
        try bytes.write(to: original)
        let first = try await service.run(
            settings: settings,
            sourceURLs: [original]
        )
        XCTAssertEqual(first.removedSourceCount, 0)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: original.path)
        )

        let duplicate = watched.appendingPathComponent(
            "duplicate.jpg"
        )
        try bytes.write(to: duplicate)
        let second = try await service.run(
            settings: settings,
            sourceURLs: [duplicate]
        )
        XCTAssertEqual(second.importResult.importedCount, 0)
        XCTAssertEqual(second.retainedDuplicateCount, 1)
        XCTAssertEqual(second.handledURLs, [duplicate])
        XCTAssertTrue(second.retryURLs.isEmpty)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: duplicate.path
            )
        )
        XCTAssertEqual(try catalog.summary()[.allPhotos], 1)
    }
}

final class SubjectMaskGeneratorTests: XCTestCase {
    func testInstanceHitTestingUsesTopLeftCoordinatesAndRowStride() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                4,
                3,
                kCVPixelFormatType_OneComponent8,
                nil,
                &buffer
            ),
            kCVReturnSuccess
        )
        let mask = try XCTUnwrap(buffer)
        XCTAssertEqual(
            CVPixelBufferLockBaseAddress(mask, []),
            kCVReturnSuccess
        )
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        let dataSize = CVPixelBufferGetDataSize(mask)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(mask))
        base.initializeMemory(as: UInt8.self, repeating: 0, count: dataSize)
        base.storeBytes(of: UInt8(3), as: UInt8.self)
        base.advanced(by: rowBytes + 2).storeBytes(
            of: UInt8(7),
            as: UInt8.self
        )
        base.advanced(by: rowBytes * 2 + 3).storeBytes(
            of: UInt8(5),
            as: UInt8.self
        )
        CVPixelBufferUnlockBaseAddress(mask, [])

        let valid = IndexSet([3, 5])
        XCTAssertEqual(
            try SubjectMaskGenerator.instanceIndex(
                in: mask,
                normalizedX: 0,
                normalizedY: 0,
                validInstances: valid
            ),
            3
        )
        XCTAssertEqual(
            try SubjectMaskGenerator.instanceIndex(
                in: mask,
                normalizedX: 0.999,
                normalizedY: 0.999,
                validInstances: valid
            ),
            5
        )
        XCTAssertNil(
            try SubjectMaskGenerator.instanceIndex(
                in: mask,
                normalizedX: 0.5,
                normalizedY: 0.5,
                validInstances: valid
            )
        )
    }
}

final class AuxiliaryMaskGeneratorTests: XCTestCase {
    func testBitmapExtractionUsesTopLeftRowOrder() throws {
        let width = 12
        let height = 8
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: height / 2,
                width: width,
                height: height - height / 2
            )
        )
        let image = NSImage(
            cgImage: try XCTUnwrap(context.makeImage()),
            size: NSSize(width: width, height: height)
        )

        let extracted = try AuxiliaryMaskGenerator.topLeftRGBA(from: image)
        let top = extracted.bytes
        let bottomOffset = (extracted.height - 1) * extracted.width * 4
        XCTAssertGreaterThan(top[2], top[1])
        XCTAssertGreaterThan(
            extracted.bytes[bottomOffset + 1],
            extracted.bytes[bottomOffset + 2]
        )
    }

    func testDepthNormalizationIsNearToFarAndRejectsInvalidSamples() {
        let values: [Float] = [
            .nan, -1, 1, 2, 3, 4, 100
        ]
        let normalized = AuxiliaryMaskGenerator.normalizedDepthBytes(values)

        XCTAssertEqual(normalized.count, values.count)
        XCTAssertEqual(normalized[0], 255)
        XCTAssertEqual(normalized[1], 255)
        XCTAssertEqual(normalized[2], 0)
        XCTAssertLessThan(normalized[3], normalized[4])
        XCTAssertLessThan(normalized[4], normalized[5])
        XCTAssertEqual(normalized[6], 255)
    }

    func testDepthGeneratorReportsMissingAuxiliaryMap() throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 8,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: 8 * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.gray.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = try XCTUnwrap(
            NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
                .representation(using: .png, properties: [:])
        )
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-no-depth-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(
            try AuxiliaryMaskGenerator.generateDepthMapPNG(from: url)
        ) { error in
            guard case AuxiliaryMaskGenerator.GenerationError.noDepthData = error else {
                return XCTFail("Expected noDepthData, got \(error)")
            }
        }
    }

    func testDepthGeneratorReadsImageIOAuxiliaryDepthEndToEnd() throws {
        let width = 8
        let height = 4
        let values = (0..<(width * height)).map { index in
            Float(index + 1)
        }
        let depthBytes = values.withUnsafeBytes { Data($0) }
        let depthDictionary: [AnyHashable: Any] = [
            kCGImageAuxiliaryDataInfoData as String: depthBytes,
            kCGImageAuxiliaryDataInfoDataDescription as String: [
                kCGImagePropertyPixelFormat as String:
                    NSNumber(value: kCVPixelFormatType_DepthFloat32),
                kCGImagePropertyWidth as String: NSNumber(value: width),
                kCGImagePropertyHeight as String: NSNumber(value: height),
                kCGImagePropertyBytesPerRow as String:
                    NSNumber(value: width * MemoryLayout<Float>.stride)
            ]
        ]
        let depthData = try AVDepthData(
            fromDictionaryRepresentation: depthDictionary
        )
        var auxiliaryType: NSString?
        let auxiliaryDictionary = try XCTUnwrap(
            depthData.dictionaryRepresentation(
                forAuxiliaryDataType: &auxiliaryType
            )
        )
        let resolvedAuxiliaryType = try XCTUnwrap(auxiliaryType)

        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(NSColor.gray.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let sourceImage = try XCTUnwrap(context.makeImage())

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-depth-\(UUID().uuidString).jpg"
            )
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, sourceImage, nil)
        CGImageDestinationAddAuxiliaryDataInfo(
            destination,
            resolvedAuxiliaryType,
            auxiliaryDictionary as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let pngData = try AuxiliaryMaskGenerator.generateDepthMapPNG(
            from: url
        )
        let generatedImage = try XCTUnwrap(NSImage(data: pngData))
        let pixels = try AuxiliaryMaskGenerator.topLeftRGBA(
            from: generatedImage
        )

        XCTAssertEqual(pixels.width, width)
        XCTAssertEqual(pixels.height, height)
        XCTAssertLessThan(pixels.bytes[0], 8)
        XCTAssertGreaterThan(
            pixels.bytes[(width * height - 1) * 4],
            247
        )
    }

    func testEstimatedSkySelectsTopBlueRegionAndExcludesForeground() {
        let width = 24
        let height = 16
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        var foreground = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let byte = index * 4
                if y < height / 2 {
                    rgba[byte] = 105
                    rgba[byte + 1] = 170
                    rgba[byte + 2] = 235
                } else {
                    rgba[byte] = 55
                    rgba[byte + 1] = 120
                    rgba[byte + 2] = 45
                }
                if (9...14).contains(x), (2...7).contains(y) {
                    rgba[byte] = 80
                    rgba[byte + 1] = 70
                    rgba[byte + 2] = 65
                    foreground[index] = 255
                }
            }
        }

        let mask = AuxiliaryMaskGenerator.estimatedSkyMaskBytes(
            rgba: rgba,
            width: width,
            height: height,
            foregroundMask: foreground
        )
        let top = mask[0..<(width * height / 2)]
        let bottom = mask[(width * height / 2)..<(width * height)]
        let topAverage = Double(top.reduce(0) { $0 + Int($1) })
            / Double(top.count)
        let bottomAverage = Double(bottom.reduce(0) { $0 + Int($1) })
            / Double(bottom.count)

        XCTAssertGreaterThan(topAverage, 150)
        XCTAssertLessThan(bottomAverage, 20)
        XCTAssertLessThan(mask[4 * width + 11], 20)
    }
}

final class PhotoAdjustmentsTests: XCTestCase {
    func testRangesAreClamped() {
        let edits = PhotoAdjustments(
            exposure: 9,
            contrast: -150,
            sharpening: -20,
            noiseReduction: 200
        )
        XCTAssertEqual(edits.exposure, 5)
        XCTAssertEqual(edits.contrast, -100)
        XCTAssertEqual(edits.sharpening, 0)
        XCTAssertEqual(edits.noiseReduction, 100)
    }

    func testAdvancedDetailControlsClampRoundTripAndCountAmounts() throws {
        let edits = PhotoAdjustments(
            sharpening: 40,
            sharpeningRadius: 8,
            sharpeningDetail: -10,
            sharpeningMasking: 140,
            noiseReduction: 35,
            noiseReductionDetail: 180,
            noiseReductionContrast: -8,
            colorNoiseReduction: 30,
            colorNoiseDetail: -3,
            colorNoiseSmoothness: 170
        )

        XCTAssertEqual(edits.sharpeningRadius, 3)
        XCTAssertEqual(edits.sharpeningDetail, 0)
        XCTAssertEqual(edits.sharpeningMasking, 100)
        XCTAssertEqual(edits.noiseReductionDetail, 100)
        XCTAssertEqual(edits.noiseReductionContrast, 0)
        XCTAssertEqual(edits.colorNoiseDetail, 0)
        XCTAssertEqual(edits.colorNoiseSmoothness, 100)
        XCTAssertEqual(edits.editCount, 3)

        let data = try JSONEncoder().encode(edits)
        XCTAssertEqual(try JSONDecoder().decode(PhotoAdjustments.self, from: data), edits)
    }

    func testOpticsAndGeometryClampRoundTripAndCountEdits() throws {
        let edits = PhotoAdjustments(
            optics: OpticsAdjustments(
                distortion: 180,
                vignette: -130,
                redCyanShift: 24,
                blueYellowShift: -18,
                purpleDefringe: 140,
                greenDefringe: -10
            ),
            geometry: GeometryAdjustments(
                vertical: 160,
                horizontal: -130,
                aspect: 14,
                scale: 260,
                offsetX: 12,
                offsetY: -18
            )
        )

        XCTAssertEqual(edits.optics.distortion, 100)
        XCTAssertEqual(edits.optics.vignette, -100)
        XCTAssertEqual(edits.optics.purpleDefringe, 100)
        XCTAssertEqual(edits.optics.greenDefringe, 0)
        XCTAssertEqual(edits.geometry.vertical, 100)
        XCTAssertEqual(edits.geometry.horizontal, -100)
        XCTAssertEqual(edits.geometry.scale, 200)
        XCTAssertTrue(edits.geometry.constrainCrop)
        XCTAssertEqual(edits.editCount, 11)

        let data = try JSONEncoder().encode(edits)
        XCTAssertEqual(try JSONDecoder().decode(PhotoAdjustments.self, from: data), edits)
    }

    func testAutomaticChromaticAberrationClampsPersistsAndCombinesWithManualFineTuning()
        throws {
        let automatic =
            AutomaticChromaticAberrationCorrection(
                redCyanShift: 180,
                blueYellowShift: -140,
                purpleDefringe: 125,
                greenDefringe: -12,
                confidence: 4,
                sampledEdgeCount: -7,
                algorithmVersion: 0
            )
        let optics = OpticsAdjustments(
            distortion: 8,
            redCyanShift: -15,
            blueYellowShift: 20,
            purpleDefringe: 12,
            greenDefringe: 9,
            automaticChromaticAberration:
                automatic
        )

        XCTAssertEqual(
            optics.automaticChromaticAberration?
                .redCyanShift,
            100
        )
        XCTAssertEqual(
            optics.automaticChromaticAberration?
                .blueYellowShift,
            -100
        )
        XCTAssertEqual(
            optics.automaticChromaticAberration?
                .purpleDefringe,
            100
        )
        XCTAssertEqual(
            optics.automaticChromaticAberration?
                .greenDefringe,
            0
        )
        XCTAssertEqual(
            optics.automaticChromaticAberration?
                .confidence,
            1
        )
        XCTAssertEqual(
            optics.automaticChromaticAberration?
                .sampledEdgeCount,
            0
        )
        XCTAssertEqual(
            optics.automaticChromaticAberration?
                .algorithmVersion,
            1
        )

        let rendered = optics.renderingCorrection
        XCTAssertEqual(rendered.distortion, 8)
        XCTAssertEqual(rendered.redCyanShift, 85)
        XCTAssertEqual(rendered.blueYellowShift, -80)
        XCTAssertEqual(rendered.purpleDefringe, 100)
        XCTAssertEqual(rendered.greenDefringe, 9)
        XCTAssertNil(rendered.automaticChromaticAberration)
        XCTAssertEqual(optics.editCount, 6)

        let data = try JSONEncoder().encode(optics)
        XCTAssertEqual(
            try JSONDecoder().decode(
                OpticsAdjustments.self,
                from: data
            ),
            optics
        )

        let legacy = try JSONDecoder().decode(
            OpticsAdjustments.self,
            from: Data(
                """
                {
                  "distortion": 12,
                  "redCyanShift": -4
                }
                """.utf8
            )
        )
        XCTAssertNil(
            legacy.automaticChromaticAberration
        )
        XCTAssertEqual(legacy.distortion, 12)
        XCTAssertEqual(legacy.redCyanShift, -4)
    }

    func testAutomaticChromaticAberrationAnalyzerFindsOpposedRadialChannelEdges()
        throws {
        let width = 160
        let height = 120
        let centerX = Double(width - 1) / 2
        let centerY = Double(height - 1) / 2
        var rgba = [UInt8](
            repeating: 255,
            count: width * height * 4
        )

        func channel(
            radius: Double,
            edge: Double
        ) -> UInt8 {
            let transition = min(
                1,
                max(0, (radius - edge + 2) / 4)
            )
            let smooth =
                transition * transition
                * (3 - 2 * transition)
            return UInt8(
                (224 - smooth * 184).rounded()
            )
        }

        for y in 0..<height {
            for x in 0..<width {
                let radius = hypot(
                    Double(x) - centerX,
                    Double(y) - centerY
                )
                let offset = (y * width + x) * 4
                rgba[offset] = channel(
                    radius: radius,
                    edge: 45
                )
                rgba[offset + 1] = channel(
                    radius: radius,
                    edge: 42
                )
                rgba[offset + 2] = channel(
                    radius: radius,
                    edge: 39
                )
            }
        }
        let raster = try XCTUnwrap(
            ChromaticAberrationRaster(
                width: width,
                height: height,
                rgba: rgba
            )
        )
        let correction = try XCTUnwrap(
            AutomaticChromaticAberrationAnalyzer
                .analyze(raster)
        )
        let repeated = try XCTUnwrap(
            AutomaticChromaticAberrationAnalyzer
                .analyze(raster)
        )

        XCTAssertEqual(correction, repeated)
        XCTAssertGreaterThan(
            correction.sampledEdgeCount,
            24
        )
        XCTAssertGreaterThan(
            abs(correction.redCyanShift),
            1
        )
        XCTAssertGreaterThan(
            abs(correction.blueYellowShift),
            1
        )
        XCTAssertLessThan(
            correction.redCyanShift
                * correction.blueYellowShift,
            0
        )
        XCTAssertGreaterThan(
            correction.confidence,
            0.01
        )
    }

    func testAutomaticChromaticAberrationAnalyzerLeavesNeutralEdgesUnchanged()
        throws {
        let width = 120
        let height = 120
        let center = Double(width - 1) / 2
        var rgba = [UInt8](
            repeating: 255,
            count: width * height * 4
        )
        for y in 0..<height {
            for x in 0..<width {
                let radius = hypot(
                    Double(x) - center,
                    Double(y) - center
                )
                let value: UInt8 =
                    radius < 36 ? 220 : 42
                let offset = (y * width + x) * 4
                rgba[offset] = value
                rgba[offset + 1] = value
                rgba[offset + 2] = value
            }
        }
        let raster = try XCTUnwrap(
            ChromaticAberrationRaster(
                width: width,
                height: height,
                rgba: rgba
            )
        )
        let correction = try XCTUnwrap(
            AutomaticChromaticAberrationAnalyzer
                .analyze(raster)
        )

        XCTAssertGreaterThan(
            correction.sampledEdgeCount,
            24
        )
        XCTAssertEqual(correction.correctionCount, 0)
        XCTAssertEqual(correction.redCyanShift, 0)
        XCTAssertEqual(correction.blueYellowShift, 0)
        XCTAssertEqual(correction.purpleDefringe, 0)
        XCTAssertEqual(correction.greenDefringe, 0)
    }

    func testGuidedUprightSolvesPersistsAndAppliesGeometry() throws {
        let guides = [
            GuidedUprightGuide(
                orientation: .horizontal,
                startX: 0.1,
                startY: 0.2,
                endX: 0.9,
                endY: 0.3
            ),
            GuidedUprightGuide(
                orientation: .horizontal,
                startX: 0.1,
                startY: 0.7,
                endX: 0.9,
                endY: 0.8
            ),
            GuidedUprightGuide(
                orientation: .vertical,
                startX: 0.2,
                startY: 0.1,
                endX: 0.16,
                endY: 0.9
            ),
            GuidedUprightGuide(
                orientation: .vertical,
                startX: 0.8,
                startY: 0.1,
                endX: 0.84,
                endY: 0.9
            ),
        ]

        let solution = try XCTUnwrap(
            GuidedUprightSolver.solve(guides)
        )
        XCTAssertEqual(solution.guideCount, 4)
        XCTAssertEqual(solution.horizontalGuideCount, 2)
        XCTAssertEqual(solution.verticalGuideCount, 2)
        XCTAssertEqual(
            solution.straighten,
            -7.125_016,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(abs(solution.vertical), 5)
        XCTAssertLessThan(abs(solution.horizontal), 0.01)

        let edits = GuidedUprightSolver.applying(
            guides,
            to: PhotoAdjustments(
                geometry: GeometryAdjustments(
                    scale: 112,
                    offsetX: 9
                )
            )
        )
        XCTAssertEqual(
            edits.geometry.guidedUprightGuides,
            guides
        )
        XCTAssertEqual(
            edits.straighten,
            solution.straighten,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            edits.geometry.vertical,
            solution.vertical,
            accuracy: 0.000_1
        )
        XCTAssertEqual(edits.geometry.scale, 112)
        XCTAssertEqual(edits.geometry.offsetX, 9)

        let data = try JSONEncoder().encode(edits)
        XCTAssertEqual(
            try JSONDecoder().decode(
                PhotoAdjustments.self,
                from: data
            ),
            edits
        )
    }

    func testGuidedUprightNormalizesLimitsAndSupportsLegacyGeometry()
        throws {
        let aspectAware = GuidedUprightGuide.inferred(
            startX: 0.1,
            startY: 0.1,
            endX: 0.4,
            endY: 0.5,
            imageAspectRatio: 2
        )
        XCTAssertEqual(
            aspectAware.orientation,
            .horizontal
        )
        XCTAssertEqual(
            aspectAware.imageAspectRatio,
            2
        )

        let short = GuidedUprightGuide(
            orientation: .horizontal,
            startX: 0.5,
            startY: 0.5,
            endX: 0.501,
            endY: 0.501
        )
        let effective = (0..<5).map { index in
            GuidedUprightGuide(
                orientation:
                    index.isMultiple(of: 2)
                        ? .horizontal
                        : .vertical,
                startX: -1,
                startY: Double(index) / 10,
                endX: 2,
                endY: Double(index) / 10
            )
        }
        let geometry = GeometryAdjustments(
            guidedUprightGuides: [short] + effective
        )

        XCTAssertEqual(
            geometry.guidedUprightGuides.count,
            4
        )
        XCTAssertEqual(
            geometry.guidedUprightGuides[0].startX,
            0
        )
        XCTAssertEqual(
            geometry.guidedUprightGuides[0].endX,
            1
        )

        let legacy = try JSONDecoder().decode(
            GeometryAdjustments.self,
            from: Data(
                """
                {
                  "vertical": 12,
                  "horizontal": -8,
                  "scale": 100,
                  "constrainCrop": true
                }
                """.utf8
            )
        )
        XCTAssertTrue(
            legacy.guidedUprightGuides.isEmpty
        )
        XCTAssertEqual(legacy.vertical, 12)
        XCTAssertEqual(legacy.horizontal, -8)
    }

    func testTextureAndGrainClampRoundTripAndCountPrimaryAmounts() throws {
        let edits = PhotoAdjustments(
            texture: 140,
            grainAmount: 150,
            grainSize: -20,
            grainRoughness: 180
        )

        XCTAssertEqual(edits.texture, 100)
        XCTAssertEqual(edits.grainAmount, 100)
        XCTAssertEqual(edits.grainSize, 1)
        XCTAssertEqual(edits.grainRoughness, 100)
        XCTAssertEqual(edits.editCount, 2)

        let data = try JSONEncoder().encode(edits)
        XCTAssertEqual(try JSONDecoder().decode(PhotoAdjustments.self, from: data), edits)
    }

    func testLegacyUserStateDecodesWithNeutralAdjustments() throws {
        let data = Data("""
        {"rating":3,"flagged":true,"favorite":false,"note":"legacy"}
        """.utf8)
        let state = try JSONDecoder().decode(PhotoUserState.self, from: data)
        XCTAssertEqual(state.rating, 3)
        XCTAssertTrue(state.flagged)
        XCTAssertEqual(state.note, "legacy")
        XCTAssertEqual(state.adjustments, .neutral)
        XCTAssertTrue(state.versions.isEmpty)
    }

    func testEditCountIgnoresNeutralValues() {
        XCTAssertEqual(PhotoAdjustments.neutral.editCount, 0)
        XCTAssertEqual(PhotoAdjustments(exposure: 0.5, clarity: 20).editCount, 2)
    }

    func testAssetEqualityIncludesMutablePhotoState() {
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        let original = PhotoAsset(
            id: "same-id",
            url: url,
            path: url.path,
            filename: url.lastPathComponent,
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg
        )
        var edited = original
        edited.userState.adjustments = PhotoAdjustments(exposure: 1)
        XCTAssertNotEqual(original, edited)
    }

    func testOlderAdjustmentPayloadDecodesWithGeometryDefaults() throws {
        let data = Data("""
        {"exposure":0.75,"contrast":10,"shadows":20}
        """.utf8)
        let edits = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        XCTAssertEqual(edits.exposure, 0.75)
        XCTAssertEqual(edits.contrast, 10)
        XCTAssertEqual(edits.shadows, 20)
        XCTAssertEqual(edits.straighten, 0)
        XCTAssertEqual(edits.crop, .fullFrame)
        XCTAssertEqual(edits.toneCurve, .neutral)
        XCTAssertEqual(edits.colorMixer, .neutral)
        XCTAssertEqual(edits.colorGrading, .neutral)
        XCTAssertEqual(edits.developmentProfile, .cameraDefault)
        XCTAssertTrue(edits.localMasks.isEmpty)
        XCTAssertTrue(edits.spotRemovals.isEmpty)
        XCTAssertEqual(edits.texture, 0)
        XCTAssertEqual(edits.grainAmount, 0)
        XCTAssertEqual(edits.grainSize, 25)
        XCTAssertEqual(edits.grainRoughness, 50)
        XCTAssertEqual(edits.optics, .neutral)
        XCTAssertEqual(edits.geometry, .neutral)
        XCTAssertTrue(edits.geometry.constrainCrop)
        XCTAssertEqual(edits.rotationDegrees, 0)
        XCTAssertFalse(edits.flipHorizontal)
        XCTAssertFalse(edits.flipVertical)
    }

    func testCropPresetPreservesPortraitOrientation() {
        let crop = CropAspectPreset.sixteenNine.crop(forSourceAspect: 2.0 / 3.0)
        let outputAspect = (2.0 / 3.0) * crop.width / crop.height
        XCTAssertEqual(outputAspect, 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(crop.horizontalPosition, 0.5, accuracy: 0.001)
    }

    func testCropTranslationStaysInsideImage() {
        let crop = NormalizedCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.4)
            .translated(deltaX: 0.8, deltaY: -0.8)
        XCTAssertEqual(crop.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(crop.y, 0, accuracy: 0.001)
        XCTAssertEqual(crop.width, 0.5, accuracy: 0.001)
        XCTAssertEqual(crop.height, 0.4, accuracy: 0.001)
    }

    func testCropCornerResizeUsesRequestedHandle() {
        let crop = NormalizedCrop(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
            .resized(
                from: .topLeft,
                deltaX: 0.1,
                deltaY: 0.15
            )
        XCTAssertEqual(crop.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(crop.y, 0.35, accuracy: 0.001)
        XCTAssertEqual(crop.width, 0.4, accuracy: 0.001)
        XCTAssertEqual(crop.height, 0.35, accuracy: 0.001)
    }

    func testBuiltInPresetsAreNonNeutralAndNormalized() {
        for preset in DevelopmentPreset.allCases {
            XCTAssertFalse(preset.adjustments.isNeutral, preset.name)
            XCTAssertEqual(preset.adjustments, preset.adjustments.normalized)
        }
    }

    func testDevelopmentProfileClampsCountsAndRoundTrips() throws {
        let settings = DevelopmentProfileSettings(
            profile: .cinematicTeal,
            amount: 275
        )
        let edits = PhotoAdjustments(
            developmentProfile: settings,
            exposure: 0.5
        )

        XCTAssertEqual(edits.developmentProfile.profile, .cinematicTeal)
        XCTAssertEqual(edits.developmentProfile.amount, 200)
        XCTAssertEqual(edits.exposure, 0.5)
        XCTAssertEqual(edits.editCount, 2)

        let data = try JSONEncoder().encode(edits)
        XCTAssertEqual(
            try JSONDecoder().decode(PhotoAdjustments.self, from: data),
            edits
        )
    }

    func testCameraDefaultProfileNormalizesAmountAndIsNotAnEdit() {
        let settings = DevelopmentProfileSettings(
            profile: .cameraDefault,
            amount: 0
        )
        XCTAssertEqual(settings.amount, 100)
        XCTAssertTrue(settings.isDefault)
        XCTAssertFalse(settings.isEffective)
        XCTAssertEqual(
            PhotoAdjustments(developmentProfile: settings).editCount,
            0
        )
    }

    func testAdvancedColorValuesClampAndCountEdits() {
        var mixer = ColorMixer.neutral
        mixer.red = HSLChannelAdjustment(hue: 140, saturation: -130, luminance: 24)
        let edits = PhotoAdjustments(
            toneCurve: ToneCurve(midtones: 1.4),
            colorMixer: mixer
        )

        XCTAssertEqual(edits.toneCurve.midtones, 1)
        XCTAssertEqual(edits.colorMixer.red.hue, 100)
        XCTAssertEqual(edits.colorMixer.red.saturation, -100)
        XCTAssertEqual(edits.colorMixer.red.luminance, 24)
        XCTAssertEqual(edits.editCount, 4)
    }

    func testAdvancedColorRoundTrip() throws {
        var mixer = ColorMixer.neutral
        mixer.blue = HSLChannelAdjustment(hue: -12, saturation: 30, luminance: -8)
        let original = PhotoAdjustments(
            toneCurve: ToneCurve(shadows: 0.18, highlights: 0.84),
            colorMixer: mixer
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testColorGradingClampsRoundTripsAndIgnoresHueUntilSaturated() throws {
        let grading = ColorGrading(
            shadows: ColorGradingWheel(
                hue: 725,
                saturation: 140,
                luminance: -160
            ),
            highlights: ColorGradingWheel(hue: -30),
            blending: 130,
            balance: -150
        )
        let edits = PhotoAdjustments(colorGrading: grading)

        XCTAssertEqual(edits.colorGrading.shadows.hue, 5)
        XCTAssertEqual(edits.colorGrading.shadows.saturation, 100)
        XCTAssertEqual(edits.colorGrading.shadows.luminance, -100)
        XCTAssertEqual(edits.colorGrading.highlights.hue, 330)
        XCTAssertTrue(edits.colorGrading.highlights.isNeutral)
        XCTAssertEqual(edits.colorGrading.blending, 100)
        XCTAssertEqual(edits.colorGrading.balance, -100)
        XCTAssertEqual(edits.editCount, 4)

        let data = try JSONEncoder().encode(edits)
        XCTAssertEqual(try JSONDecoder().decode(PhotoAdjustments.self, from: data), edits)
    }

    func testCalibrationClampsCountsAndRoundTrips() throws {
        let edits = PhotoAdjustments(
            calibration: CalibrationAdjustments(
                shadowsTint: 130,
                redPrimaryHue: -150,
                redPrimarySaturation: 22,
                greenPrimaryHue: -18,
                bluePrimarySaturation: 160
            )
        )

        XCTAssertEqual(edits.calibration.shadowsTint, 100)
        XCTAssertEqual(edits.calibration.redPrimaryHue, -100)
        XCTAssertEqual(edits.calibration.redPrimarySaturation, 22)
        XCTAssertEqual(edits.calibration.greenPrimaryHue, -18)
        XCTAssertEqual(edits.calibration.bluePrimarySaturation, 100)
        XCTAssertEqual(edits.editCount, 5)

        let data = try JSONEncoder().encode(edits)
        XCTAssertEqual(try JSONDecoder().decode(PhotoAdjustments.self, from: data), edits)
    }

    func testPointColorSampleIsNeutralUntilAdjustedAndRoundTrips() throws {
        let neutralPoint = PointColorAdjustment(
            sample: PointColorSample(hue: 375, saturation: 140, luminance: -20)
        )
        let sampled = PhotoAdjustments(pointColors: [neutralPoint])
        XCTAssertEqual(sampled.pointColors.first?.sample.hue, 15)
        XCTAssertEqual(sampled.pointColors.first?.sample.saturation, 100)
        XCTAssertEqual(sampled.pointColors.first?.sample.luminance, 0)
        XCTAssertTrue(sampled.isNeutral)

        let editedPoint = PointColorAdjustment(
            id: neutralPoint.id,
            sample: neutralPoint.sample,
            hueShift: 140,
            saturationShift: -130,
            luminanceShift: 22,
            variance: -17,
            hueRange: 500,
            saturationRange: -1,
            luminanceRange: 250
        )
        let edited = PhotoAdjustments(pointColors: [editedPoint])
        let point = try XCTUnwrap(edited.pointColors.first)
        XCTAssertEqual(point.hueShift, 100)
        XCTAssertEqual(point.saturationShift, -100)
        XCTAssertEqual(point.hueRange, 180)
        XCTAssertEqual(point.saturationRange, 1)
        XCTAssertEqual(point.luminanceRange, 100)
        XCTAssertEqual(edited.editCount, 4)

        let data = try JSONEncoder().encode(edited)
        XCTAssertEqual(
            try JSONDecoder().decode(PhotoAdjustments.self, from: data),
            edited
        )
    }

    func testPointColorStoresAtMostEightSwatches() {
        let points = (0..<12).map { index in
            PointColorAdjustment(
                sample: PointColorSample(
                    hue: Double(index) * 30,
                    saturation: 70,
                    luminance: 50
                )
            )
        }
        XCTAssertEqual(PhotoAdjustments(pointColors: points).pointColors.count, 8)
    }

    func testOrientationNormalizesAndCountsAsEdits() {
        let edits = PhotoAdjustments(
            rotationDegrees: -91,
            flipHorizontal: true,
            flipVertical: true
        )
        XCTAssertEqual(edits.rotationDegrees, 270)
        XCTAssertEqual(edits.editCount, 3)
    }

    func testLocalMaskClampsAndRoundTrips() throws {
        let original = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "  Window  ",
                    kind: .linear,
                    centerX: 2,
                    centerY: -1,
                    size: 9,
                    feather: -2,
                    angle: 540,
                    inverted: true,
                    adjustments: LocalToneAdjustments(
                        exposure: 9,
                        contrast: -150,
                        highlights: 140,
                        shadows: -130,
                        whites: 120,
                        blacks: -110,
                        hue: 500,
                        saturation: 22,
                        texture: -125,
                        sharpness: 135,
                        noiseReduction: 150
                    )
                )
            ]
        )

        let mask = try XCTUnwrap(original.localMasks.first)
        XCTAssertEqual(mask.name, "Window")
        XCTAssertEqual(mask.centerX, 1)
        XCTAssertEqual(mask.centerY, 0)
        XCTAssertEqual(mask.size, 1.5)
        XCTAssertEqual(mask.feather, 0)
        XCTAssertEqual(mask.angle, 180)
        XCTAssertEqual(mask.adjustments.exposure, 5)
        XCTAssertEqual(mask.adjustments.contrast, -100)
        XCTAssertEqual(mask.adjustments.highlights, 100)
        XCTAssertEqual(mask.adjustments.shadows, -100)
        XCTAssertEqual(mask.adjustments.whites, 100)
        XCTAssertEqual(mask.adjustments.blacks, -100)
        XCTAssertEqual(mask.adjustments.hue, 180)
        XCTAssertEqual(mask.adjustments.texture, -100)
        XCTAssertEqual(mask.adjustments.sharpness, 100)
        XCTAssertEqual(mask.adjustments.noiseReduction, 100)
        XCTAssertEqual(original.editCount, 1)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testMaskRangeOperationsClampLimitAndRoundTrip() throws {
        let operations = (0..<20).map { index in
            MaskRangeOperation(
                name: index == 0 ? "  Reds  " : nil,
                kind: index.isMultiple(of: 2) ? .color : .luminance,
                combination: MaskCombinationMode.allCases[
                    index % MaskCombinationMode.allCases.count
                ],
                colorSample: PointColorSample(
                    hue: 725,
                    saturation: 120,
                    luminance: -5
                ),
                hueRange: 500,
                saturationRange: -2,
                colorLuminanceRange: 200,
                luminanceMinimum: 90,
                luminanceMaximum: 10,
                luminanceFeather: 80
            )
        }
        let original = LocalAdjustmentMask(
            name: "Range",
            kind: .radial,
            rangeOperations: operations,
            adjustments: LocalToneAdjustments(exposure: 1)
        )

        XCTAssertEqual(original.rangeOperations.count, 16)
        let first = try XCTUnwrap(original.rangeOperations.first)
        XCTAssertEqual(first.name, "Reds")
        XCTAssertEqual(first.colorSample.hue, 5)
        XCTAssertEqual(first.colorSample.saturation, 100)
        XCTAssertEqual(first.colorSample.luminance, 0)
        XCTAssertEqual(first.hueRange, 180)
        XCTAssertEqual(first.saturationRange, 1)
        XCTAssertEqual(first.colorLuminanceRange, 100)
        XCTAssertEqual(first.luminanceMinimum, 10)
        XCTAssertEqual(first.luminanceMaximum, 90)
        XCTAssertEqual(first.luminanceFeather, 50)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalAdjustmentMask.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testMaskPrimaryOperationsClampLimitAndRoundTrip() throws {
        let operations = (0..<20).map { index in
            MaskPrimaryOperation(
                name: index == 0 ? "  Subtract Brush  " : nil,
                kind: index.isMultiple(of: 2) ? .brush : .linear,
                combination: MaskCombinationMode.allCases[
                    index % MaskCombinationMode.allCases.count
                ],
                centerX: 2,
                centerY: -1,
                size: 9,
                feather: -2,
                angle: 540,
                flow: 3,
                strokes: [
                    BrushStroke(points: [BrushPoint(x: 0.5, y: 0.5)])
                ]
            )
        }
        let original = LocalAdjustmentMask(
            name: "Graph",
            kind: .radial,
            primaryOperations: operations,
            adjustments: LocalToneAdjustments(exposure: 1)
        )

        XCTAssertEqual(original.primaryOperations.count, 16)
        let first = try XCTUnwrap(original.primaryOperations.first)
        XCTAssertEqual(first.name, "Subtract Brush")
        XCTAssertEqual(first.centerX, 1)
        XCTAssertEqual(first.centerY, 0)
        XCTAssertEqual(first.size, 1.5)
        XCTAssertEqual(first.feather, 0)
        XCTAssertEqual(first.angle, 180)
        XCTAssertEqual(first.flow, 1)
        XCTAssertTrue(first.hasCoverage)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LocalAdjustmentMask.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testLocalPointColorCountsAsMaskedEditAndRoundTrips() throws {
        let point = PointColorAdjustment(
            sample: PointColorSample(hue: 8, saturation: 85, luminance: 42),
            hueShift: 35
        )
        let original = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Local red",
                    kind: .radial,
                    pointColors: [point],
                    adjustments: .neutral
                )
            ]
        )

        XCTAssertEqual(original.editCount, 1)
        XCTAssertFalse(original.isNeutral)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(
            try JSONDecoder().decode(PhotoAdjustments.self, from: data),
            original
        )
    }

    func testOlderLocalMaskPayloadDecodesWithoutRangeOperations() throws {
        let payload = """
        {
          "id":"04B894C2-9642-4687-807A-38FA248B81EA",
          "name":"Legacy",
          "kind":"radial",
          "centerX":0.5,
          "centerY":0.5,
          "size":0.55,
          "feather":0.5,
          "angle":0,
          "inverted":false,
          "flow":1,
          "strokes":[],
          "adjustments":{"exposure":1}
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(LocalAdjustmentMask.self, from: payload)
        XCTAssertTrue(decoded.primaryOperations.isEmpty)
        XCTAssertTrue(decoded.rangeOperations.isEmpty)
        XCTAssertTrue(decoded.pointColors.isEmpty)
        XCTAssertEqual(
            decoded.adjustments,
            LocalToneAdjustments(exposure: 1)
        )
    }

    func testMaskWithoutToneIsNeutral() {
        let edits = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Empty",
                    kind: .radial,
                    adjustments: .neutral
                )
            ]
        )
        XCTAssertTrue(edits.isNeutral)
        XCTAssertEqual(edits.editCount, 0)
    }

    func testEmptyBrushMaskIsNeutralUntilPainted() {
        let empty = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Brush",
                    kind: .brush,
                    size: 0.04,
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertTrue(empty.isNeutral)
        XCTAssertEqual(empty.editCount, 0)

        let painted = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Brush",
                    kind: .brush,
                    size: 0.04,
                    strokes: [
                        BrushStroke(points: [BrushPoint(x: 0.5, y: 0.5)])
                    ],
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertFalse(painted.isNeutral)
        XCTAssertEqual(painted.editCount, 1)

        let additiveRange = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Range only",
                    kind: .brush,
                    strokes: [],
                    rangeOperations: [
                        MaskRangeOperation(
                            kind: .luminance,
                            combination: .add
                        )
                    ],
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertFalse(additiveRange.isNeutral)
        XCTAssertEqual(additiveRange.editCount, 1)
    }

    func testBrushMaskRoundTripsAndClamps() throws {
        let original = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "  Dodge  ",
                    kind: .brush,
                    size: -1,
                    feather: 2,
                    flow: -4,
                    strokes: [
                        BrushStroke(
                            points: [
                                BrushPoint(x: -2, y: 0.25),
                                BrushPoint(x: 3, y: 0.75)
                            ]
                        )
                    ],
                    adjustments: LocalToneAdjustments(exposure: 0.8)
                )
            ]
        )

        let brush = try XCTUnwrap(original.localMasks.first)
        XCTAssertEqual(brush.name, "Dodge")
        XCTAssertEqual(brush.size, 0.005)
        XCTAssertEqual(brush.feather, 1)
        XCTAssertEqual(brush.flow, 0)
        XCTAssertEqual(brush.strokes.first?.points.first?.x, 0)
        XCTAssertEqual(brush.strokes.first?.points.last?.x, 1)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSubjectMaskNeedsRasterDataAndRoundTrips() throws {
        let pending = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Subject",
                    kind: .subject,
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertTrue(pending.isNeutral)

        let original = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Subject",
                    kind: .subject,
                    rasterMaskData: Data([1, 2, 3, 4]),
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertEqual(original.editCount, 1)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testObjectMaskNeedsRasterDataAndRoundTrips() throws {
        let pending = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Object",
                    kind: .object,
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertTrue(pending.isNeutral)

        let original = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Object",
                    kind: .object,
                    rasterMaskData: Data([4, 3, 2, 1]),
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertEqual(original.editCount, 1)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSkyMaskNeedsRasterDataAndRoundTrips() throws {
        let pending = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Sky",
                    kind: .sky,
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertTrue(pending.isNeutral)

        let original = PhotoAdjustments(
            localMasks: [
                LocalAdjustmentMask(
                    name: "Sky",
                    kind: .sky,
                    rasterMaskData: Data([9, 8, 7, 6]),
                    adjustments: LocalToneAdjustments(exposure: 1)
                )
            ]
        )
        XCTAssertEqual(original.editCount, 1)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDepthRangeClampsAndRoundTrips() throws {
        let original = MaskRangeOperation(
            name: "  Depth  ",
            kind: .depth,
            combination: .subtract,
            rasterMaskData: Data([1, 2, 3, 4]),
            depthMinimum: 94,
            depthMaximum: -20,
            depthFeather: 90
        )

        XCTAssertEqual(original.name, "Depth")
        XCTAssertEqual(original.depthMinimum, 0)
        XCTAssertEqual(original.depthMaximum, 94)
        XCTAssertEqual(original.depthFeather, 50)
        XCTAssertEqual(original.rasterMaskData, Data([1, 2, 3, 4]))

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            MaskRangeOperation.self,
            from: data
        )
        XCTAssertEqual(decoded, original)
    }

    func testOlderRangePayloadDecodesWithoutDepthData() throws {
        let payload = """
        {
          "kind":"luminance",
          "combination":"intersect",
          "luminanceMinimum":12,
          "luminanceMaximum":76
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(
            MaskRangeOperation.self,
            from: payload
        )

        XCTAssertEqual(decoded.kind, .luminance)
        XCTAssertNil(decoded.rasterMaskData)
        XCTAssertEqual(decoded.depthMinimum, 0)
        XCTAssertEqual(decoded.depthMaximum, 50)
        XCTAssertEqual(decoded.depthFeather, 10)
    }

    func testSpotRemovalClampsAndRoundTrips() throws {
        let original = PhotoAdjustments(
            spotRemovals: [
                SpotRemoval(
                    name: "  Dust  ",
                    kind: .clone,
                    targetX: 2,
                    targetY: -1,
                    sourceX: -3,
                    sourceY: 4,
                    radius: 2,
                    feather: -1,
                    opacity: 9
                )
            ]
        )

        let spot = try XCTUnwrap(original.spotRemovals.first)
        XCTAssertEqual(spot.name, "Dust")
        XCTAssertEqual(spot.targetX, 1)
        XCTAssertEqual(spot.targetY, 0)
        XCTAssertEqual(spot.sourceX, 0)
        XCTAssertEqual(spot.sourceY, 1)
        XCTAssertEqual(spot.radius, 0.25)
        XCTAssertEqual(spot.feather, 0)
        XCTAssertEqual(spot.opacity, 1)
        XCTAssertEqual(original.editCount, 1)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PhotoAdjustments.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class PhotoProcessorTests: XCTestCase {
    func testExposureChangesPixelsWithoutChangingDimensions() throws {
        let source = makeSolidImage(width: 32, height: 24, gray: 0.25)
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(exposure: 1)
        )

        XCTAssertEqual(edited.size.width, 32)
        XCTAssertEqual(edited.size.height, 24)
        XCTAssertGreaterThan(brightness(of: edited), brightness(of: source))
    }

    func testProfileAmountZeroIsPixelNeutralWithoutChangingOtherControls() throws {
        let source = makeColorImage(
            width: 24,
            height: 16,
            color: NSColor(
                srgbRed: 0.58,
                green: 0.34,
                blue: 0.22,
                alpha: 1
            )
        )
        let adjustments = PhotoAdjustments(
            developmentProfile: DevelopmentProfileSettings(
                profile: .vivid,
                amount: 0
            ),
            contrast: 0
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: adjustments
        )
        let baseline = try PhotoProcessor.apply(
            to: source,
            adjustments: .neutral
        )

        XCTAssertEqual(adjustments.developmentProfile.profile, .vivid)
        XCTAssertEqual(adjustments.developmentProfile.amount, 0)
        XCTAssertEqual(adjustments.contrast, 0)
        XCTAssertLessThan(
            colorDistance(
                try XCTUnwrap(color(of: baseline)),
                try XCTUnwrap(color(of: edited))
            ),
            0.015
        )
    }

    func testVividProfileRaisesSaturationAndAmountScalesEffect() throws {
        let source = makeColorImage(
            width: 24,
            height: 16,
            color: NSColor(
                srgbRed: 0.55,
                green: 0.42,
                blue: 0.34,
                alpha: 1
            )
        )
        let normal = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                developmentProfile: DevelopmentProfileSettings(
                    profile: .vivid,
                    amount: 100
                )
            )
        )
        let doubled = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                developmentProfile: DevelopmentProfileSettings(
                    profile: .vivid,
                    amount: 200
                )
            )
        )
        let sourceColor = try XCTUnwrap(color(of: source))
        let normalColor = try XCTUnwrap(color(of: normal))
        let doubledColor = try XCTUnwrap(color(of: doubled))

        XCTAssertGreaterThan(
            normalColor.saturationComponent,
            sourceColor.saturationComponent + 0.02
        )
        XCTAssertGreaterThan(
            colorDistance(sourceColor, doubledColor),
            colorDistance(sourceColor, normalColor) + 0.01
        )
    }

    func testMonochromeProfileProducesNeutralChannels() throws {
        let source = makeColorImage(
            width: 24,
            height: 16,
            color: NSColor(
                srgbRed: 0.72,
                green: 0.30,
                blue: 0.10,
                alpha: 1
            )
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                developmentProfile: DevelopmentProfileSettings(
                    profile: .monochrome,
                    amount: 100
                )
            )
        )
        let output = try XCTUnwrap(color(of: edited))

        XCTAssertEqual(
            output.redComponent,
            output.greenComponent,
            accuracy: 0.012
        )
        XCTAssertEqual(
            output.greenComponent,
            output.blueComponent,
            accuracy: 0.012
        )
    }

    func testHistogramHasExpectedBinCount() {
        let source = makeSolidImage(width: 24, height: 16, gray: 0.5)
        let histogram = HistogramAnalyzer.analyze(source, binCount: 64)
        XCTAssertEqual(histogram?.red.count, 64)
        XCTAssertEqual(histogram?.green.count, 64)
        XCTAssertEqual(histogram?.blue.count, 64)
        XCTAssertGreaterThan(histogram?.red.max() ?? 0, 0)
    }

    func testHistogramReportsClippedShadowsAndHighlights() {
        let black = HistogramAnalyzer.analyze(
            makeSolidImage(width: 16, height: 16, gray: 0),
            binCount: 64
        )
        let white = HistogramAnalyzer.analyze(
            makeSolidImage(width: 16, height: 16, gray: 1),
            binCount: 64
        )
        XCTAssertGreaterThan(black?.shadowClippingFraction ?? 0, 0.9)
        XCTAssertGreaterThan(white?.highlightClippingFraction ?? 0, 0.9)
    }

    func testSquareCropChangesOutputDimensions() throws {
        let source = makeSolidImage(width: 80, height: 50, gray: 0.5)
        let crop = CropAspectPreset.square.crop(forSourceAspect: 80.0 / 50.0)
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(crop: crop)
        )
        XCTAssertEqual(edited.size.width, 50)
        XCTAssertEqual(edited.size.height, 50)
    }

    func testStraightenKeepsCanvasDimensions() throws {
        let source = makeSolidImage(width: 80, height: 50, gray: 0.5)
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(straighten: 5)
        )
        XCTAssertEqual(edited.size.width, 80)
        XCTAssertEqual(edited.size.height, 50)
    }

    func testGeometryTransformKeepsCanvasDimensionsAndMovesImage() throws {
        let source = makeSplitImage(
            width: 80,
            height: 50,
            left: NSColor.red,
            right: NSColor.blue
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                geometry: GeometryAdjustments(
                    vertical: 22,
                    horizontal: -18,
                    aspect: 15,
                    scale: 115,
                    offsetX: 20,
                    offsetY: -8
                )
            )
        )

        XCTAssertEqual(edited.size.width, 80)
        XCTAssertEqual(edited.size.height, 50)
        let sourceCenter = try XCTUnwrap(color(of: source, x: 40, y: 25))
        let editedCenter = try XCTUnwrap(color(of: edited, x: 40, y: 25))
        XCTAssertGreaterThan(colorDistance(sourceCenter, editedCenter), 0.2)
    }

    func testConstrainCropFillsPerspectiveEdges() throws {
        let source = makeSolidImage(width: 120, height: 80, gray: 0.8)
        let unconstrained = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                geometry: GeometryAdjustments(
                    vertical: 65,
                    constrainCrop: false
                )
            )
        )
        let constrained = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                geometry: GeometryAdjustments(
                    vertical: 65,
                    constrainCrop: true
                )
            )
        )
        let samplePoints = [(2, 2), (117, 2), (2, 77), (117, 77)]
        let unconstrainedMinimum = samplePoints.map {
            brightness(of: unconstrained, x: $0.0, y: $0.1)
        }.min() ?? 0
        let constrainedMinimum = samplePoints.map {
            brightness(of: constrained, x: $0.0, y: $0.1)
        }.min() ?? 0

        XCTAssertGreaterThan(constrainedMinimum, unconstrainedMinimum + 0.5)
    }

    func testLensVignetteCorrectionBrightensEdgesMoreThanCenter() throws {
        let source = makeSolidImage(width: 80, height: 80, gray: 0.2)
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                optics: OpticsAdjustments(vignette: 100)
            )
        )

        let center = brightness(of: edited, x: 40, y: 40)
        let corner = brightness(of: edited, x: 2, y: 2)
        XCTAssertGreaterThan(corner, center + 0.1)
    }

    func testPurpleDefringeSuppressesSaturationAtHighContrastEdge() throws {
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: NSColor(srgbRed: 0.8, green: 0.02, blue: 1, alpha: 1),
            right: NSColor(white: 0.85, alpha: 1)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                optics: OpticsAdjustments(purpleDefringe: 100)
            )
        )

        let reductions = try (34...45).map { x -> CGFloat in
            let original = try XCTUnwrap(color(of: source, x: x, y: 20))
            let corrected = try XCTUnwrap(color(of: edited, x: x, y: 20))
            return original.saturationComponent - corrected.saturationComponent
        }
        XCTAssertGreaterThan(reductions.max() ?? 0, 0.2)
    }

    func testAutomaticChromaticAberrationCorrectionReducesSyntheticRadialFringe()
        throws {
        let fixture = makeRadialChromaticImage(
            width: 160,
            height: 120
        )
        let correction = try XCTUnwrap(
            AutomaticChromaticAberrationAnalyzer
                .analyze(fixture.raster)
        )
        let edited = try PhotoProcessor.apply(
            to: fixture.image,
            adjustments: PhotoAdjustments(
                optics: OpticsAdjustments(
                    automaticChromaticAberration:
                        correction
                )
            )
        )

        XCTAssertLessThan(
            radialChromaticError(
                in: edited,
                innerRadius: 36,
                outerRadius: 49
            ),
            radialChromaticError(
                in: fixture.image,
                innerRadius: 36,
                outerRadius: 49
            )
        )
    }

    func testFilmGrainAddsDeterministicLuminanceVariation() throws {
        let source = makeSolidImage(width: 64, height: 64, gray: 0.5)
        let adjustments = PhotoAdjustments(
            grainAmount: 100,
            grainSize: 35,
            grainRoughness: 80
        )
        let first = try PhotoProcessor.apply(to: source, adjustments: adjustments)
        let second = try PhotoProcessor.apply(to: source, adjustments: adjustments)

        XCTAssertGreaterThan(brightnessVariance(of: first), 0.002)
        XCTAssertEqual(
            brightness(of: first, x: 17, y: 29),
            brightness(of: second, x: 17, y: 29),
            accuracy: 0.001
        )
    }

    func testDisabledEffectsPreserveSettingsWithoutChangingPixels() throws {
        let source = makeSolidImage(width: 64, height: 64, gray: 0.5)
        let disabled = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                effectsEnabled: false,
                texture: 80,
                clarity: 70,
                dehaze: 60,
                vignette: -75,
                grainAmount: 100,
                grainSize: 35,
                grainRoughness: 80
            )
        )
        let baseline = try PhotoProcessor.apply(
            to: source,
            adjustments: .neutral
        )
        let enabled = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                effectsEnabled: true,
                texture: 80,
                clarity: 70,
                dehaze: 60,
                vignette: -75,
                grainAmount: 100,
                grainSize: 35,
                grainRoughness: 80
            )
        )

        for point in [(2, 2), (17, 29), (32, 32), (61, 61)] {
            XCTAssertLessThan(
                colorDistance(
                    try XCTUnwrap(
                        color(
                            of: disabled,
                            x: point.0,
                            y: point.1
                        )
                    ),
                    try XCTUnwrap(
                        color(
                            of: baseline,
                            x: point.0,
                            y: point.1
                        )
                    )
                ),
                0.01
            )
        }
        XCTAssertGreaterThan(
            brightnessVariance(of: enabled),
            brightnessVariance(of: disabled) + 0.001
        )
    }

    func testToneCurveRaisesMidtones() throws {
        let source = makeSolidImage(width: 32, height: 24, gray: 0.5)
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                toneCurve: ToneCurve(midtones: 0.8)
            )
        )
        XCTAssertGreaterThan(brightness(of: edited), brightness(of: source) + 0.1)
    }

    func testPersistedQuarterTurnSwapsDimensions() throws {
        let source = makeSolidImage(width: 80, height: 50, gray: 0.5)
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(rotationDegrees: 90)
        )
        XCTAssertEqual(edited.size.width, 50)
        XCTAssertEqual(edited.size.height, 80)
    }

    func testCalibrationRedPrimaryTargetsRedMoreThanBlue() throws {
        let source = makeSplitImage(
            width: 64,
            height: 32,
            left: NSColor(srgbRed: 0.62, green: 0.22, blue: 0.2, alpha: 1),
            right: NSColor(srgbRed: 0.2, green: 0.22, blue: 0.62, alpha: 1)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                calibration: CalibrationAdjustments(
                    redPrimaryHue: 100,
                    redPrimarySaturation: 60
                )
            )
        )
        let baseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        let baselineRed = try XCTUnwrap(color(of: baseline, x: 16, y: 16))
        let baselineBlue = try XCTUnwrap(color(of: baseline, x: 48, y: 16))
        let editedRed = try XCTUnwrap(color(of: edited, x: 16, y: 16))
        let editedBlue = try XCTUnwrap(color(of: edited, x: 48, y: 16))
        XCTAssertGreaterThan(
            colorDistance(baselineRed, editedRed),
            colorDistance(baselineBlue, editedBlue) + 0.12
        )
        XCTAssertGreaterThan(
            editedRed.saturationComponent,
            baselineRed.saturationComponent + 0.12
        )
    }

    func testCalibrationShadowsTintTargetsDarkTones() throws {
        let source = makeSplitImage(
            width: 64,
            height: 32,
            left: NSColor(white: 0.15, alpha: 1),
            right: NSColor(white: 0.82, alpha: 1)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                calibration: CalibrationAdjustments(shadowsTint: 100)
            )
        )
        let dark = try XCTUnwrap(color(of: edited, x: 16, y: 16))
        let bright = try XCTUnwrap(color(of: edited, x: 48, y: 16))
        let darkMagentaBias =
            (dark.redComponent + dark.blueComponent) / 2 - dark.greenComponent
        let brightMagentaBias =
            (bright.redComponent + bright.blueComponent) / 2 - bright.greenComponent

        XCTAssertGreaterThan(darkMagentaBias, brightMagentaBias + 0.08)
    }

    func testColorMixerCanDesaturateOneChannel() throws {
        var mixer = ColorMixer.neutral
        mixer.red = HSLChannelAdjustment(saturation: -100)
        let source = makeColorImage(
            width: 32,
            height: 24,
            color: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(colorMixer: mixer)
        )

        XCTAssertLessThan(saturation(of: edited), 0.1)
        XCTAssertGreaterThan(saturation(of: source), 0.9)
    }

    func testColorMixerLeavesDistantHueAlone() throws {
        var mixer = ColorMixer.neutral
        mixer.red = HSLChannelAdjustment(saturation: -100)
        let source = makeColorImage(
            width: 32,
            height: 24,
            color: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(colorMixer: mixer)
        )

        XCTAssertGreaterThan(saturation(of: edited), 0.9)
    }

    func testPointColorTargetsSampledHueAndLeavesDistantHueAlone() throws {
        let point = PointColorAdjustment(
            sample: PointColorSample(hue: 0, saturation: 100, luminance: 50),
            saturationShift: -100,
            hueRange: 24,
            saturationRange: 50,
            luminanceRange: 50
        )
        let source = makeSplitImage(
            width: 64,
            height: 32,
            left: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            right: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(pointColors: [point])
        )

        let editedRed = try XCTUnwrap(color(of: edited, x: 16, y: 16))
        let editedBlue = try XCTUnwrap(color(of: edited, x: 48, y: 16))
        XCTAssertLessThan(editedRed.saturationComponent, 0.18)
        XCTAssertGreaterThan(editedBlue.saturationComponent, 0.85)
    }

    func testPointColorVisualizationIsExplicitPreviewOnly() throws {
        let point = PointColorAdjustment(
            sample: PointColorSample(hue: 0, saturation: 100, luminance: 50),
            hueRange: 24,
            saturationRange: 50,
            luminanceRange: 50
        )
        let adjustments = PhotoAdjustments(pointColors: [point])
        let source = makeSplitImage(
            width: 64,
            height: 32,
            left: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            right: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        )
        let normal = try PhotoProcessor.apply(
            to: source,
            adjustments: adjustments
        )
        let neutral = try PhotoProcessor.apply(
            to: source,
            adjustments: .neutral
        )
        let visualized = try PhotoProcessor.apply(
            to: source,
            adjustments: adjustments,
            visualizePointColorID: point.id
        )

        XCTAssertLessThan(
            colorDistance(
                try XCTUnwrap(color(of: neutral, x: 48, y: 16)),
                try XCTUnwrap(color(of: normal, x: 48, y: 16))
            ),
            0.02
        )
        XCTAssertGreaterThan(
            brightness(of: visualized, x: 16, y: 16),
            brightness(of: visualized, x: 48, y: 16) + 0.25
        )

        let stronglyShiftedPoint = PointColorAdjustment(
            id: point.id,
            sample: point.sample,
            hueShift: 100,
            hueRange: point.hueRange,
            saturationRange: point.saturationRange,
            luminanceRange: point.luminanceRange
        )
        let shiftedVisualization = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(pointColors: [stronglyShiftedPoint]),
            visualizePointColorID: point.id
        )
        XCTAssertGreaterThan(
            brightness(of: shiftedVisualization, x: 16, y: 16),
            brightness(of: shiftedVisualization, x: 48, y: 16) + 0.25
        )
    }

    func testSoftProofSettingsLimitPaperSimulationToPrintProfile() {
        XCTAssertFalse(
            SoftProofSettings(
                isEnabled: true,
                profile: .sRGB,
                simulatePaperAndInk: true
            ).simulatePaperAndInk
        )
        XCTAssertTrue(
            SoftProofSettings(
                isEnabled: true,
                profile: .genericCMYK,
                simulatePaperAndInk: true
            ).simulatePaperAndInk
        )
    }

    func testLegacySoftProofSettingsDecodeWithoutMonitorWarning()
        throws
    {
        let data = Data(
            """
            {
              "isEnabled": true,
              "profile": "genericCMYK",
              "renderingIntent": "relativeColorimetric",
              "showDestinationGamutWarning": true,
              "simulatePaperAndInk": true
            }
            """.utf8
        )
        let settings = try JSONDecoder().decode(
            SoftProofSettings.self,
            from: data
        )

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.profile, .genericCMYK)
        XCTAssertEqual(
            settings.renderingIntent,
            .relativeColorimetric
        )
        XCTAssertTrue(
            settings.showDestinationGamutWarning
        )
        XCTAssertFalse(
            settings.showMonitorGamutWarning
        )
        XCTAssertTrue(settings.simulatePaperAndInk)
    }

    func testICCProfileImportsToPrivateStableCopyAndRoundTrips()
        throws
    {
        let root = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-icc-profile-\(UUID().uuidString)",
            isDirectory: true
        )
        let imports = root.appendingPathComponent(
            "imports",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let colorSpace = try XCTUnwrap(
            CGColorSpace(
                name: CGColorSpace.genericCMYK
            )
        )
        let data = try XCTUnwrap(
            colorSpace.copyICCData() as Data?
        )
        let source = root.appendingPathComponent(
            "fixture.icc"
        )
        try data.write(to: source, options: .atomic)

        let sourceProfile =
            try SoftProofProfileCatalog.profile(
                at: source
            )
        XCTAssertEqual(
            sourceProfile.colorModel,
            .cmyk
        )
        XCTAssertEqual(
            sourceProfile.iccProfile?.profileClass,
            "prtr"
        )
        XCTAssertTrue(
            sourceProfile.supportsPaperAndInk
        )

        let imported =
            try SoftProofProfileCatalog.importProfile(
                at: source,
                directory: imports
            )
        let importedICC = try XCTUnwrap(
            imported.iccProfile
        )
        XCTAssertEqual(
            importedICC.fingerprint,
            sourceProfile.iccProfile?.fingerprint
        )
        XCTAssertEqual(
            importedICC.url.deletingLastPathComponent(),
            imports
        )
        XCTAssertEqual(
            importedICC.url.lastPathComponent,
            "\(importedICC.fingerprint).icc"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: importedICC.url.path
            )
        )
        XCTAssertEqual(
            try SoftProofProfileCatalog.colorSpace(
                for: imported
            ).model,
            .cmyk
        )

        let encoded = try JSONEncoder().encode(
            imported
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                SoftProofProfile.self,
                from: encoded
            ),
            imported
        )

        var changedData = data
        changedData[127] ^= 1
        try changedData.write(
            to: importedICC.url,
            options: .atomic
        )
        XCTAssertThrowsError(
            try SoftProofProfileCatalog.colorSpace(
                for: imported
            )
        ) { error in
            guard let catalogError =
                    error as?
                    SoftProofProfileCatalog
                        .CatalogError,
                  case .fingerprintMismatch =
                    catalogError else {
                return XCTFail(
                    "Expected a fingerprint mismatch, got \(error)"
                )
            }
        }
    }

    func testInstalledICCProfileCatalogIncludesOutputProfile() {
        let profiles =
            SoftProofProfileCatalog
                .installedProfiles(refresh: true)

        XCTAssertFalse(profiles.isEmpty)
        XCTAssertTrue(
            profiles.allSatisfy {
                $0.iccProfile != nil
            }
        )
        XCTAssertTrue(
            profiles.contains {
                $0.colorModel == .cmyk
                    && $0.supportsPaperAndInk
            }
        )
    }

    func testDefaultICCImportRespectsTestSupportBoundary()
        throws
    {
        let root = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-default-icc-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let colorSpace = try XCTUnwrap(
            CGColorSpace(
                name: CGColorSpace.genericCMYK
            )
        )
        let source = root.appendingPathComponent(
            "default-fixture.icc"
        )
        try XCTUnwrap(
            colorSpace.copyICCData() as Data?
        ).write(to: source, options: .atomic)

        let imported =
            try SoftProofProfileCatalog.importProfile(
                at: source
            )
        let importedURL = try XCTUnwrap(
            imported.iccProfile?.url
        )
        let support =
            RAWDeskStorageDirectory.resolve(nil)
        XCTAssertEqual(
            importedURL
                .deletingLastPathComponent(),
            support.appendingPathComponent(
                "Proof Profiles",
                isDirectory: true
            )
        )
        XCTAssertFalse(
            importedURL.path.hasPrefix(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(
                        "Library/Application Support/RAWDesk",
                        isDirectory: true
                    )
                    .path
            ),
            "Test imports must never reach the normal RAWDesk support directory."
        )
        try FileManager.default.removeItem(
            at: importedURL
        )
    }

    func testSoftProofDisabledReturnsCleanSource() throws {
        let source = makeColorImage(
            width: 18,
            height: 12,
            color: .systemRed
        )
        let result = try SoftProofProcessor.apply(
            to: source,
            settings: .disabled
        )

        XCTAssertTrue(result.displayImage === source)
        XCTAssertTrue(result.proofImage === source)
        XCTAssertNil(result.destinationGamutFraction)
    }

    func testCMYKSoftProofConvertsWithoutFlippingImage() throws {
        let source = makeHorizontalSplitImage(
            width: 24,
            height: 40,
            top: NSColor(
                srgbRed: 0,
                green: 1,
                blue: 0,
                alpha: 1
            ),
            bottom: NSColor(
                srgbRed: 1,
                green: 0,
                blue: 1,
                alpha: 1
            )
        )
        let result = try SoftProofProcessor.apply(
            to: source,
            settings: SoftProofSettings(
                isEnabled: true,
                profile: .genericCMYK,
                renderingIntent: .relativeColorimetric
            )
        )

        XCTAssertEqual(result.proofImage.size, source.size)
        let top = try XCTUnwrap(
            color(
                of: result.proofImage,
                x: 12,
                y: 6
            )
        )
        let bottom = try XCTUnwrap(
            color(
                of: result.proofImage,
                x: 12,
                y: 34
            )
        )
        XCTAssertGreaterThan(
            top.greenComponent,
            top.redComponent
        )
        XCTAssertGreaterThan(
            bottom.redComponent,
            bottom.greenComponent
        )
        XCTAssertGreaterThan(
            bottom.blueComponent,
            bottom.greenComponent
        )
    }

    func testDestinationWarningIsSeparateFromCleanProof() throws {
        let source = makeColorImage(
            width: 20,
            height: 16,
            color: NSColor(
                srgbRed: 1,
                green: 0,
                blue: 0,
                alpha: 1
            )
        )
        let result = try SoftProofProcessor.apply(
            to: source,
            settings: SoftProofSettings(
                isEnabled: true,
                profile: .genericCMYK,
                renderingIntent: .perceptual,
                showDestinationGamutWarning: true
            )
        )

        XCTAssertGreaterThan(
            result.destinationGamutFraction ?? 0,
            0.95
        )
        let proof = try XCTUnwrap(
            color(of: result.proofImage)
        )
        let warning = try XCTUnwrap(
            color(of: result.displayImage)
        )
        XCTAssertGreaterThan(
            warning.redComponent,
            proof.redComponent
        )
        XCTAssertLessThan(
            warning.greenComponent,
            proof.greenComponent
        )

    }

    func testMonitorGamutWarningIsBlueAndIndependent()
        throws
    {
        let p3 = try XCTUnwrap(
            CGColorSpace(
                name: CGColorSpace.displayP3
            )
        )
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 20,
                height: 16,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: p3,
                bitmapInfo:
                    CGImageAlphaInfo
                        .premultipliedLast.rawValue
            )
        )
        context.setFillColor(
            try XCTUnwrap(
                CGColor(
                    colorSpace: p3,
                    components: [0, 1, 0, 1]
                )
            )
        )
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: 20,
                height: 16
            )
        )
        let source = NSImage(
            cgImage: try XCTUnwrap(
                context.makeImage()
            ),
            size: NSSize(width: 20, height: 16)
        )
        let sRGB = try XCTUnwrap(
            CGColorSpace(
                name: CGColorSpace.sRGB
            )
        )
        let monitor = try XCTUnwrap(
            SoftProofMonitorProfile(
                name: "sRGB Test Display",
                colorSpace: sRGB
            )
        )
        let result = try SoftProofProcessor.apply(
            to: source,
            settings: SoftProofSettings(
                isEnabled: true,
                profile: .displayP3,
                renderingIntent:
                    .relativeColorimetric,
                showMonitorGamutWarning: true
            ),
            monitorProfile: monitor
        )

        XCTAssertNil(
            result.destinationGamutFraction
        )
        XCTAssertGreaterThan(
            result.monitorGamutFraction ?? 0,
            0.95
        )
        XCTAssertEqual(
            result.monitorName,
            "sRGB Test Display"
        )
        let proof = try XCTUnwrap(
            color(of: result.proofImage)
        )
        let warning = try XCTUnwrap(
            color(of: result.displayImage)
        )
        XCTAssertGreaterThan(
            warning.blueComponent,
            proof.blueComponent
        )
        XCTAssertLessThan(
            warning.greenComponent,
            proof.greenComponent
        )

        let inGamut = try SoftProofProcessor.apply(
            to: makeColorImage(
                width: 12,
                height: 8,
                color: NSColor(
                    srgbRed: 0.25,
                    green: 0.5,
                    blue: 0.75,
                    alpha: 1
                )
            ),
            settings: SoftProofSettings(
                isEnabled: true,
                profile: .sRGB,
                showMonitorGamutWarning: true
            ),
            monitorProfile: monitor
        )
        XCTAssertEqual(
            inGamut.monitorGamutFraction,
            0
        )
    }

    func testWarningOverlayUsesRedBlueAndMagenta()
        throws
    {
        let proof: [UInt8] = [
            100, 120, 140, 255,
            100, 120, 140, 255,
            100, 120, 140, 255,
        ]
        let output =
            SoftProofProcessor.overlayWarnings(
                on: proof,
                destination: [true, false, true],
                monitor: [false, true, true]
            )

        XCTAssertEqual(
            Array(output[0..<4]),
            [215, 30, 35, 255]
        )
        XCTAssertEqual(
            Array(output[4..<8]),
            [25, 30, 225, 255]
        )
        XCTAssertEqual(
            Array(output[8..<12]),
            [230, 32, 220, 255]
        )
    }

    func testAdjustedSoftProofKeepsWideGamutUntilProfileConversion()
        throws
    {
        let displayP3 = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.displayP3)
        )
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 20,
                height: 16,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: displayP3,
                bitmapInfo:
                    CGImageAlphaInfo
                        .premultipliedLast.rawValue
            )
        )
        context.setFillColor(
            try XCTUnwrap(
                CGColor(
                    colorSpace: displayP3,
                    components: [0, 1, 0, 1]
                )
            )
        )
        context.fill(
            CGRect(x: 0, y: 0, width: 20, height: 16)
        )
        let cgImage = try XCTUnwrap(context.makeImage())
        let source = NSImage(
            cgImage: cgImage,
            size: NSSize(width: 20, height: 16)
        )
        let settings = SoftProofSettings(
            isEnabled: true,
            profile: .displayP3,
            renderingIntent: .relativeColorimetric
        )
        let p3ColorSpace = try XCTUnwrap(
            NSColorSpace(cgColorSpace: displayP3)
        )
        func p3Color(_ image: NSImage) -> NSColor? {
            guard let image = image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            ) else {
                return nil
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            return bitmap.colorAt(
                x: bitmap.pixelsWide / 2,
                y: bitmap.pixelsHigh / 2
            )?.usingColorSpace(p3ColorSpace)
        }
        var greatestDifference: CGFloat = 0
        for exposure in [
            -2.0,
            -1.0,
            -0.35,
            0.35,
            1.0,
            2.0,
        ] {
            let adjustments = PhotoAdjustments(
                exposure: exposure
            )
            let direct =
                try PhotoProcessor.applySoftProof(
                    to: source,
                    adjustments: adjustments,
                    settings: settings
                )
            let prematurelyRasterized =
                try PhotoProcessor.apply(
                    to: source,
                    adjustments: adjustments
                )
            let legacy = try SoftProofProcessor.apply(
                to: prematurelyRasterized,
                settings: settings
            )
            let directColor = try XCTUnwrap(
                p3Color(direct.proofImage)
            )
            let legacyColor = try XCTUnwrap(
                p3Color(legacy.proofImage)
            )
            let difference =
                abs(
                    directColor.redComponent
                        - legacyColor.redComponent
                )
                + abs(
                    directColor.greenComponent
                        - legacyColor.greenComponent
                )
                + abs(
                    directColor.blueComponent
                        - legacyColor.blueComponent
                )
            greatestDifference = max(
                greatestDifference,
                difference
            )
        }

        XCTAssertGreaterThan(
            greatestDifference,
            0.01,
            "The proof must use the wide-gamut working result, not an already-clipped sRGB preview."
        )
    }

    func testSoftProofRAWPreviewUsesHalfFloatWorkingBuffer()
        throws
    {
        let base = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-wide-preview-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: base)
        }
        let url = base.appendingPathComponent(
            "wide-preview.png"
        )
        let p3 = try XCTUnwrap(
            CGColorSpace(name: CGColorSpace.displayP3)
        )
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 48,
                height: 32,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: p3,
                bitmapInfo:
                    CGImageAlphaInfo
                        .premultipliedLast.rawValue
            )
        )
        context.setFillColor(
            try XCTUnwrap(
                CGColor(
                    colorSpace: p3,
                    components: [0, 1, 0, 1]
                )
            )
        )
        context.fill(
            CGRect(x: 0, y: 0, width: 48, height: 32)
        )
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.png" as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            try XCTUnwrap(context.makeImage()),
            nil
        )
        XCTAssertTrue(
            CGImageDestinationFinalize(destination)
        )

        let preview = try RAWImageLoader.load(
            url: url,
            targetLongestEdge: 32,
            preserveWideGamut: true
        )
        let image = try XCTUnwrap(
            preview.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        )
        XCTAssertEqual(image.bitsPerComponent, 16)
        XCTAssertEqual(image.bitsPerPixel, 64)
        XCTAssertEqual(
            image.colorSpace?.name,
            CGColorSpace.extendedLinearSRGB
        )
    }

    @MainActor
    func testViewerSoftProofKeepsCleanSamplingImage()
        async throws
    {
        let base = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-soft-proof-viewer-\(UUID().uuidString)",
            isDirectory: true
        )
        let cacheDirectory = base.appendingPathComponent(
            "cache",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: base)
        }
        let photoURL = base.appendingPathComponent(
            "proof.jpg"
        )
        try writeJPEG(
            makeColorImage(
                width: 48,
                height: 32,
                color: NSColor(
                    srgbRed: 1,
                    green: 0,
                    blue: 0,
                    alpha: 1
                )
            ),
            to: photoURL
        )
        let values = try photoURL.resourceValues(
            forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
            ]
        )
        let asset = PhotoAsset(
            id: "proof",
            url: photoURL,
            path: photoURL.path,
            filename: photoURL.lastPathComponent,
            fileExtension: "jpg",
            fileSize: Int64(values.fileSize ?? 0),
            creationDate: nil,
            modificationDate:
                values.contentModificationDate,
            format: .jpeg
        )
        let viewer = PhotoViewerViewModel(
            loader: ImageLoader(
                cache: ImageCache(
                    directory: cacheDirectory
                ),
                maxConcurrent: 1
            ),
            renderQueue: PhotoRenderQueue()
        )
        viewer.display(asset)
        for _ in 0..<300
            where viewer.loadState != .loaded {
            try await Task.sleep(
                for: .milliseconds(10)
            )
        }
        XCTAssertEqual(viewer.loadState, .loaded)
        XCTAssertNotNil(viewer.image)

        viewer.updateAdjustments(
            PhotoAdjustments(exposure: 0.2),
            for: asset.id
        )
        for _ in 0..<300
            where viewer.isDeveloping {
            try await Task.sleep(
                for: .milliseconds(10)
            )
        }
        XCTAssertFalse(viewer.isDeveloping)

        viewer.setSoftProofProfile(.genericCMYK)
        viewer.setSoftProofGamutWarning(true)
        viewer.setSoftProofEnabled(true)
        for _ in 0..<300
            where viewer.isSoftProofRendering
                || viewer.isDeveloping {
            try await Task.sleep(
                for: .milliseconds(10)
            )
        }

        XCTAssertTrue(
            viewer.softProofSettings.isEnabled
        )
        XCTAssertGreaterThan(
            viewer.softProofDestinationGamutFraction
                ?? 0,
            0.90
        )
        let clean = try XCTUnwrap(
            viewer.colorSamplingImage
        )
        let display = try XCTUnwrap(viewer.image)
        XCTAssertNotEqual(
            color(of: clean),
            color(of: display)
        )

        viewer.setSoftProofEnabled(false)
        for _ in 0..<300
            where viewer.isDeveloping {
            try await Task.sleep(
                for: .milliseconds(10)
            )
        }
        XCTAssertFalse(
            viewer.softProofSettings.isEnabled
        )
        XCTAssertNil(
            viewer.softProofDestinationGamutFraction
        )
        XCTAssertTrue(
            viewer.image
                === viewer.colorSamplingImage
        )

        let missingProfile = SoftProofProfile.icc(
            SoftProofProfile.ICCProfile(
                fingerprint:
                    String(repeating: "0", count: 64),
                name: "Missing Output Profile",
                url: base.appendingPathComponent(
                    "missing.icc"
                ),
                colorModel: .cmyk,
                profileClass: "prtr"
            )
        )
        viewer.setSoftProofProfile(missingProfile)
        viewer.setSoftProofEnabled(true)
        for _ in 0..<300
            where viewer.isSoftProofRendering
                || viewer.isDeveloping {
            try await Task.sleep(
                for: .milliseconds(10)
            )
        }
        XCTAssertTrue(
            viewer.softProofSettings.isEnabled
        )
        XCTAssertNotNil(
            viewer.softProofErrorMessage
        )
        XCTAssertNil(
            viewer.softProofDestinationGamutFraction
        )
        XCTAssertNil(
            viewer.softProofMonitorGamutFraction
        )
        XCTAssertTrue(
            viewer.image
                === viewer.colorSamplingImage
        )

        viewer.setSoftProofEnabled(false)
    }

    func testImageColorSamplerFindsColorsAtPreviewCoordinates() throws {
        let source = makeSplitImage(
            width: 60,
            height: 30,
            left: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
            right: NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        )
        let red = try XCTUnwrap(
            ImageColorSampler.sample(
                image: source,
                normalizedX: 0.25,
                normalizedY: 0.5
            )
        )
        let blue = try XCTUnwrap(
            ImageColorSampler.sample(
                image: source,
                normalizedX: 0.75,
                normalizedY: 0.5
            )
        )

        XCTAssertTrue(red.hue < 2 || red.hue > 358)
        XCTAssertEqual(blue.hue, 240, accuracy: 2)
        XCTAssertGreaterThan(red.saturation, 98)
        XCTAssertGreaterThan(blue.saturation, 98)

        let redRGB = try XCTUnwrap(
            ImageColorSampler.sampleRGB(
                image: source,
                normalizedX: 0.25,
                normalizedY: 0.5
            )
        )
        XCTAssertEqual(redRGB.red, 1, accuracy: 0.01)
        XCTAssertEqual(redRGB.green, 0, accuracy: 0.01)
        XCTAssertEqual(redRGB.blue, 0, accuracy: 0.01)
        XCTAssertEqual(
            redRGB.lab.lightness,
            53.2408,
            accuracy: 0.1
        )

        let vertical = makeHorizontalSplitImage(
            width: 30,
            height: 60,
            top: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
            bottom: NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        )
        let top = try XCTUnwrap(
            ImageColorSampler.sample(
                image: vertical,
                normalizedX: 0.5,
                normalizedY: 0.2
            )
        )
        let bottom = try XCTUnwrap(
            ImageColorSampler.sample(
                image: vertical,
                normalizedX: 0.5,
                normalizedY: 0.8
            )
        )
        XCTAssertEqual(top.hue, 120, accuracy: 2)
        XCTAssertEqual(bottom.hue, 300, accuracy: 2)
    }

    func testShadowColorGradingTargetsDarkTonesMoreThanHighlights() throws {
        let grading = ColorGrading(
            shadows: ColorGradingWheel(hue: 235, saturation: 100)
        )
        let dark = makeSolidImage(width: 32, height: 24, gray: 0.18)
        let bright = makeSolidImage(width: 32, height: 24, gray: 0.82)
        let darkEdited = try PhotoProcessor.apply(
            to: dark,
            adjustments: PhotoAdjustments(colorGrading: grading)
        )
        let brightEdited = try PhotoProcessor.apply(
            to: bright,
            adjustments: PhotoAdjustments(colorGrading: grading)
        )

        XCTAssertGreaterThan(
            saturation(of: darkEdited),
            saturation(of: brightEdited) + 0.25
        )
    }

    func testRadialMaskChangesCenterMoreThanCorner() throws {
        let source = makeSolidImage(width: 64, height: 64, gray: 0.2)
        let mask = LocalAdjustmentMask(
            name: "Center",
            kind: .radial,
            size: 0.6,
            feather: 0.5,
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )

        let center = brightness(of: edited, x: 32, y: 32)
        let corner = brightness(of: edited, x: 2, y: 2)
        XCTAssertGreaterThan(center, corner + 0.15)
    }

    func testLinearMaskCreatesDirectionalDifference() throws {
        let source = makeSolidImage(width: 64, height: 32, gray: 0.2)
        let mask = LocalAdjustmentMask(
            name: "Across",
            kind: .linear,
            size: 0.8,
            feather: 1,
            angle: 0,
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )

        let left = brightness(of: edited, x: 4, y: 16)
        let right = brightness(of: edited, x: 59, y: 16)
        XCTAssertGreaterThan(right, left + 0.15)
    }

    func testBrushMaskChangesOnlyPaintedArea() throws {
        let source = makeSolidImage(width: 64, height: 64, gray: 0.2)
        let brush = LocalAdjustmentMask(
            name: "Dodge",
            kind: .brush,
            size: 0.15,
            feather: 0.25,
            strokes: [
                BrushStroke(
                    points: [
                        BrushPoint(x: 0.42, y: 0.5),
                        BrushPoint(x: 0.58, y: 0.5)
                    ]
                )
            ],
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [brush])
        )

        let center = brightness(of: edited, x: 32, y: 32)
        let corner = brightness(of: edited, x: 2, y: 2)
        XCTAssertGreaterThan(center, corner + 0.15)
    }

    func testSubjectRasterMaskChangesOnlySelectedArea() throws {
        let source = makeSolidImage(width: 64, height: 64, gray: 0.2)
        let subject = LocalAdjustmentMask(
            name: "Subject",
            kind: .subject,
            rasterMaskData: try makeSplitMaskPNG(width: 64, height: 64),
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [subject])
        )

        let left = brightness(of: edited, x: 16, y: 32)
        let right = brightness(of: edited, x: 48, y: 32)
        XCTAssertGreaterThan(abs(left - right), 0.15)
    }

    func testObjectRasterMaskChangesOnlySelectedArea() throws {
        let source = makeSolidImage(width: 64, height: 64, gray: 0.2)
        let object = LocalAdjustmentMask(
            name: "Object",
            kind: .object,
            rasterMaskData: try makeSplitMaskPNG(width: 64, height: 64),
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [object])
        )

        let left = brightness(of: edited, x: 16, y: 32)
        let right = brightness(of: edited, x: 48, y: 32)
        XCTAssertGreaterThan(abs(left - right), 0.15)
    }

    func testSkyRasterMaskChangesOnlySelectedArea() throws {
        let source = makeSolidImage(width: 64, height: 64, gray: 0.2)
        let sky = LocalAdjustmentMask(
            name: "Sky",
            kind: .sky,
            rasterMaskData: try makeSplitMaskPNG(width: 64, height: 64),
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [sky])
        )

        let left = brightness(of: edited, x: 16, y: 32)
        let right = brightness(of: edited, x: 48, y: 32)
        XCTAssertGreaterThan(abs(left - right), 0.15)
    }

    func testLocalHueAdjustmentStaysInsideRasterMask() throws {
        let red = NSColor(srgbRed: 0.75, green: 0.08, blue: 0.05, alpha: 1)
        let source = makeSplitImage(
            width: 64,
            height: 40,
            left: red,
            right: red
        )
        let object = LocalAdjustmentMask(
            name: "Hue",
            kind: .object,
            rasterMaskData: try makeSplitMaskPNG(width: 64, height: 40),
            adjustments: LocalToneAdjustments(hue: 120)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [object])
        )
        let baseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        let leftDistance = colorDistance(
            try XCTUnwrap(color(of: edited, x: 16, y: 20)),
            try XCTUnwrap(color(of: baseline, x: 16, y: 20))
        )
        let rightDistance = colorDistance(
            try XCTUnwrap(color(of: edited, x: 48, y: 20)),
            try XCTUnwrap(color(of: baseline, x: 48, y: 20))
        )
        XCTAssertGreaterThan(max(leftDistance, rightDistance), 0.25)
        XCTAssertLessThan(min(leftDistance, rightDistance), 0.03)
    }

    func testPrimaryAddOperationExpandsSelection() throws {
        let source = makeSolidImage(width: 80, height: 40, gray: 0.2)
        let split = try makeSplitMaskPNG(width: 80, height: 40)
        let addComplement = MaskPrimaryOperation(
            name: "Other half",
            kind: .object,
            combination: .add,
            inverted: true,
            rasterMaskData: split
        )
        let mask = LocalAdjustmentMask(
            name: "Whole frame from two tools",
            kind: .subject,
            rasterMaskData: split,
            primaryOperations: [addComplement],
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )
        let baseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        XCTAssertGreaterThan(
            brightness(of: edited, x: 20, y: 20),
            brightness(of: baseline, x: 20, y: 20) + 0.15
        )
        XCTAssertGreaterThan(
            brightness(of: edited, x: 60, y: 20),
            brightness(of: baseline, x: 60, y: 20) + 0.15
        )
    }

    func testPrimarySubtractAndIntersectOperationsRestrictSelection() throws {
        let source = makeSolidImage(width: 80, height: 40, gray: 0.2)
        let split = try makeSplitMaskPNG(width: 80, height: 40)
        let baseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        for combination in [MaskCombinationMode.subtract, .intersect] {
            let operation = MaskPrimaryOperation(
                kind: .object,
                combination: combination,
                rasterMaskData: split
            )
            let mask = LocalAdjustmentMask(
                name: combination.name,
                kind: .subject,
                rasterMaskData: try makeSolidMaskPNG(width: 80, height: 40),
                primaryOperations: [operation],
                adjustments: LocalToneAdjustments(exposure: 2)
            )
            let edited = try PhotoProcessor.apply(
                to: source,
                adjustments: PhotoAdjustments(localMasks: [mask])
            )
            let leftDelta = abs(
                brightness(of: edited, x: 20, y: 20)
                    - brightness(of: baseline, x: 20, y: 20)
            )
            let rightDelta = abs(
                brightness(of: edited, x: 60, y: 20)
                    - brightness(of: baseline, x: 60, y: 20)
            )
            XCTAssertGreaterThan(max(leftDelta, rightDelta), 0.15)
            XCTAssertLessThan(min(leftDelta, rightDelta), 0.04)
        }
    }

    func testPrimaryOperationsComposeInStoredOrder() throws {
        let source = makeSolidImage(width: 80, height: 40, gray: 0.2)
        let split = try makeSplitMaskPNG(width: 80, height: 40)
        let operations = [
            MaskPrimaryOperation(
                name: "Remove half",
                kind: .object,
                combination: .subtract,
                rasterMaskData: split
            ),
            MaskPrimaryOperation(
                name: "Restore half",
                kind: .object,
                combination: .add,
                rasterMaskData: split
            )
        ]
        let mask = LocalAdjustmentMask(
            name: "Ordered primary graph",
            kind: .subject,
            rasterMaskData: try makeSolidMaskPNG(width: 80, height: 40),
            primaryOperations: operations,
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )
        let baseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        XCTAssertGreaterThan(
            brightness(of: edited, x: 20, y: 20),
            brightness(of: baseline, x: 20, y: 20) + 0.15
        )
        XCTAssertGreaterThan(
            brightness(of: edited, x: 60, y: 20),
            brightness(of: baseline, x: 60, y: 20) + 0.15
        )
    }

    func testLocalPointColorStaysInsideMask() throws {
        let red = NSColor(srgbRed: 0.72, green: 0.08, blue: 0.05, alpha: 1)
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: red,
            right: red
        )
        let point = PointColorAdjustment(
            sample: PointColorSample(red: 0.72, green: 0.08, blue: 0.05),
            hueShift: 70,
            hueRange: 25,
            saturationRange: 35,
            luminanceRange: 35
        )
        let mask = LocalAdjustmentMask(
            name: "Local red shift",
            kind: .object,
            rasterMaskData: try makeSplitMaskPNG(width: 80, height: 40),
            pointColors: [point],
            adjustments: .neutral
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )
        let baseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )
        let leftDistance = colorDistance(
            try XCTUnwrap(color(of: edited, x: 20, y: 20)),
            try XCTUnwrap(color(of: baseline, x: 20, y: 20))
        )
        let rightDistance = colorDistance(
            try XCTUnwrap(color(of: edited, x: 60, y: 20)),
            try XCTUnwrap(color(of: baseline, x: 60, y: 20))
        )

        XCTAssertGreaterThan(max(leftDistance, rightDistance), 0.15)
        XCTAssertLessThan(min(leftDistance, rightDistance), 0.04)
    }

    func testColorRangeIntersectTargetsSampledHue() throws {
        let red = NSColor(srgbRed: 0.32, green: 0.04, blue: 0.04, alpha: 1)
        let blue = NSColor(srgbRed: 0.04, green: 0.04, blue: 0.32, alpha: 1)
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: red,
            right: blue
        )
        let operation = MaskRangeOperation(
            kind: .color,
            combination: .intersect,
            colorSample: PointColorSample(red: 0.32, green: 0.04, blue: 0.04),
            hueRange: 18,
            saturationRange: 30,
            colorLuminanceRange: 30
        )
        let mask = LocalAdjustmentMask(
            name: "Red only",
            kind: .subject,
            rasterMaskData: try makeSolidMaskPNG(width: 80, height: 40),
            rangeOperations: [operation],
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )
        let managedBaseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        let sourceRed = brightness(of: managedBaseline, x: 20, y: 20)
        let sourceBlue = brightness(of: managedBaseline, x: 60, y: 20)
        let editedRed = brightness(of: edited, x: 20, y: 20)
        let editedBlue = brightness(of: edited, x: 60, y: 20)
        XCTAssertGreaterThan(editedRed, sourceRed + 0.18)
        XCTAssertEqual(editedBlue, sourceBlue, accuracy: 0.04)
    }

    func testLuminanceRangeIntersectTargetsSelectedBrightness() throws {
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: NSColor(white: 0.15, alpha: 1),
            right: NSColor(white: 0.75, alpha: 1)
        )
        let operation = MaskRangeOperation(
            kind: .luminance,
            combination: .intersect,
            luminanceMinimum: 0,
            luminanceMaximum: 35,
            luminanceFeather: 0
        )
        let mask = LocalAdjustmentMask(
            name: "Shadows",
            kind: .subject,
            rasterMaskData: try makeSolidMaskPNG(width: 80, height: 40),
            rangeOperations: [operation],
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )
        let managedBaseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        XCTAssertGreaterThan(
            brightness(of: edited, x: 20, y: 20),
            brightness(of: managedBaseline, x: 20, y: 20) + 0.18
        )
        XCTAssertEqual(
            brightness(of: edited, x: 60, y: 20),
            brightness(of: managedBaseline, x: 60, y: 20),
            accuracy: 0.04
        )
    }

    func testDepthRangeUsesStoredNearToFarMap() throws {
        let source = makeSolidImage(width: 80, height: 40, gray: 0.2)
        let operation = MaskRangeOperation(
            kind: .depth,
            combination: .intersect,
            rasterMaskData: try makeSplitMaskPNG(width: 80, height: 40),
            depthMinimum: 0,
            depthMaximum: 20,
            depthFeather: 0
        )
        let mask = LocalAdjustmentMask(
            name: "Near depth",
            kind: .subject,
            rasterMaskData: try makeSolidMaskPNG(width: 80, height: 40),
            rangeOperations: [operation],
            adjustments: LocalToneAdjustments(exposure: 2)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )

        let far = brightness(of: edited, x: 20, y: 20)
        let near = brightness(of: edited, x: 60, y: 20)
        XCTAssertGreaterThan(near, far + 0.15)
    }

    func testAddRangeExpandsPrimaryMask() throws {
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: NSColor(white: 0.2, alpha: 1),
            right: NSColor(white: 0.72, alpha: 1)
        )
        let addHighlights = MaskRangeOperation(
            kind: .luminance,
            combination: .add,
            luminanceMinimum: 60,
            luminanceMaximum: 100,
            luminanceFeather: 0
        )
        let mask = LocalAdjustmentMask(
            name: "Left plus highlights",
            kind: .subject,
            rasterMaskData: try makeSplitMaskPNG(width: 80, height: 40),
            rangeOperations: [addHighlights],
            adjustments: LocalToneAdjustments(exposure: 1.5)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )
        let managedBaseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        XCTAssertGreaterThan(
            brightness(of: edited, x: 20, y: 20),
            brightness(of: managedBaseline, x: 20, y: 20) + 0.12
        )
        XCTAssertGreaterThan(
            brightness(of: edited, x: 60, y: 20),
            brightness(of: managedBaseline, x: 60, y: 20) + 0.08
        )
    }

    func testSubtractRangeRemovesSelectionFromPrimaryMask() throws {
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: NSColor(white: 0.18, alpha: 1),
            right: NSColor(white: 0.68, alpha: 1)
        )
        let subtractShadows = MaskRangeOperation(
            kind: .luminance,
            combination: .subtract,
            luminanceMinimum: 0,
            luminanceMaximum: 30,
            luminanceFeather: 0
        )
        let mask = LocalAdjustmentMask(
            name: "Not shadows",
            kind: .subject,
            rasterMaskData: try makeSolidMaskPNG(width: 80, height: 40),
            rangeOperations: [subtractShadows],
            adjustments: LocalToneAdjustments(exposure: 1.5)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )
        let managedBaseline = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(contrast: 0.000_2)
        )

        XCTAssertEqual(
            brightness(of: edited, x: 20, y: 20),
            brightness(of: managedBaseline, x: 20, y: 20),
            accuracy: 0.04
        )
        XCTAssertGreaterThan(
            brightness(of: edited, x: 60, y: 20),
            brightness(of: managedBaseline, x: 60, y: 20) + 0.08
        )
    }

    func testSubtractAndAddRangeOperationsComposeInOrder() throws {
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: NSColor(white: 0.15, alpha: 1),
            right: NSColor(white: 0.72, alpha: 1)
        )
        let subtractDark = MaskRangeOperation(
            kind: .luminance,
            combination: .subtract,
            luminanceMinimum: 0,
            luminanceMaximum: 30,
            luminanceFeather: 0
        )
        let addDark = MaskRangeOperation(
            kind: .luminance,
            combination: .add,
            luminanceMinimum: 0,
            luminanceMaximum: 30,
            luminanceFeather: 0
        )
        let mask = LocalAdjustmentMask(
            name: "Ordered graph",
            kind: .subject,
            rasterMaskData: try makeSolidMaskPNG(width: 80, height: 40),
            rangeOperations: [subtractDark, addDark],
            adjustments: LocalToneAdjustments(exposure: 1.5)
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(localMasks: [mask])
        )

        XCTAssertGreaterThan(
            brightness(of: edited, x: 20, y: 20),
            brightness(of: source, x: 20, y: 20) + 0.12
        )
        XCTAssertGreaterThan(
            brightness(of: edited, x: 60, y: 20),
            brightness(of: source, x: 60, y: 20) + 0.08
        )
    }

    func testLocalMaskOverlayIsExplicitPreviewOnly() throws {
        let source = makeSolidImage(width: 48, height: 48, gray: 0.3)
        let mask = LocalAdjustmentMask(
            name: "Overlay",
            kind: .radial,
            size: 0.7,
            feather: 0.5,
            adjustments: LocalToneAdjustments(exposure: 1)
        )
        let adjustments = PhotoAdjustments(localMasks: [mask])
        let normal = try PhotoProcessor.apply(to: source, adjustments: adjustments)
        let visualized = try PhotoProcessor.apply(
            to: source,
            adjustments: adjustments,
            visualizeLocalMaskID: mask.id
        )

        let normalCenter = try XCTUnwrap(color(of: normal, x: 24, y: 24))
        let visualizedCenter = try XCTUnwrap(color(of: visualized, x: 24, y: 24))
        XCTAssertGreaterThan(
            visualizedCenter.redComponent - visualizedCenter.greenComponent,
            normalCenter.redComponent - normalCenter.greenComponent + 0.2
        )
    }

    func testColorNoiseReductionReducesPixelToPixelChromaVariation() throws {
        let source = makeColorCheckerboard(width: 64, height: 64)
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(
                colorNoiseReduction: 100,
                colorNoiseDetail: 0,
                colorNoiseSmoothness: 100
            )
        )

        let sourceA = try XCTUnwrap(color(of: source, x: 31, y: 32))
        let sourceB = try XCTUnwrap(color(of: source, x: 32, y: 32))
        let editedA = try XCTUnwrap(color(of: edited, x: 31, y: 32))
        let editedB = try XCTUnwrap(color(of: edited, x: 32, y: 32))
        XCTAssertLessThan(
            colorDistance(editedA, editedB),
            colorDistance(sourceA, sourceB) * 0.5
        )
    }

    func testCloneSpotCopiesSourcePixelsToTarget() throws {
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: NSColor(srgbRed: 0.9, green: 0.08, blue: 0.05, alpha: 1),
            right: NSColor(srgbRed: 0.04, green: 0.08, blue: 0.9, alpha: 1)
        )
        let repair = SpotRemoval(
            name: "Clone",
            kind: .clone,
            targetX: 0.75,
            targetY: 0.5,
            sourceX: 0.25,
            sourceY: 0.5,
            radius: 0.2,
            feather: 0.1
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(spotRemovals: [repair])
        )

        let originalTarget = try XCTUnwrap(color(of: source, x: 60, y: 20))
        let editedTarget = try XCTUnwrap(color(of: edited, x: 60, y: 20))
        XCTAssertGreaterThan(editedTarget.redComponent, originalTarget.redComponent + 0.5)
        XCTAssertLessThan(editedTarget.blueComponent, originalTarget.blueComponent - 0.5)
    }

    func testHealSpotTransfersTextureLuminanceWithoutCloningHue() throws {
        let source = makeSplitImage(
            width: 80,
            height: 40,
            left: NSColor(white: 0.85, alpha: 1),
            right: NSColor(srgbRed: 0.02, green: 0.08, blue: 0.28, alpha: 1)
        )
        let repair = SpotRemoval(
            name: "Heal",
            kind: .heal,
            targetX: 0.75,
            targetY: 0.5,
            sourceX: 0.25,
            sourceY: 0.5,
            radius: 0.2,
            feather: 0.1
        )
        let edited = try PhotoProcessor.apply(
            to: source,
            adjustments: PhotoAdjustments(spotRemovals: [repair])
        )

        let originalTarget = try XCTUnwrap(color(of: source, x: 60, y: 20))
        let editedTarget = try XCTUnwrap(color(of: edited, x: 60, y: 20))
        XCTAssertGreaterThan(
            editedTarget.brightnessComponent,
            originalTarget.brightnessComponent + 0.35
        )
        XCTAssertGreaterThan(editedTarget.blueComponent, editedTarget.redComponent)
    }

    func testFullResolutionExportUsesOriginalAndAppliesRotation() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sourceURL = temp.appendingPathComponent("source.jpg")
        let outputURL = temp.appendingPathComponent("output.png")
        try writeJPEG(makeSolidImage(width: 80, height: 50, gray: 0.35), to: sourceURL)

        let asset = PhotoAsset(
            id: "export",
            url: sourceURL,
            path: sourceURL.path,
            filename: sourceURL.lastPathComponent,
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg
        )
        var transform = ImageTransformState()
        transform.rotateRight()

        try await ImageExporter.export(
            asset: asset,
            adjustments: PhotoAdjustments(exposure: 0.5, vibrance: 10),
            transform: transform,
            to: outputURL,
            format: .png
        )

        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any] else {
            XCTFail("Could not read export")
            return
        }
        XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 50)
        XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 80)
    }

    func testExportPreservesCameraMetadataAndNormalizesOrientation() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-metadata-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let sourceURL = temp.appendingPathComponent("oriented.jpg")
        let outputURL = temp.appendingPathComponent("developed.jpg")
        try writeJPEG(
            makeSolidImage(width: 80, height: 50, gray: 0.4),
            to: sourceURL,
            properties: [
                kCGImagePropertyOrientation: 6,
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFMake: "RAWDesk Test Camera"
                ],
                kCGImagePropertyIPTCDictionary: [
                    kCGImagePropertyIPTCKeywords: ["Embedded old keyword"],
                    kCGImagePropertyIPTCCaptionAbstract:
                        "Keep this embedded caption",
                ]
            ]
        )
        let asset = PhotoAsset(
            id: "metadata-export",
            url: sourceURL,
            path: sourceURL.path,
            filename: sourceURL.lastPathComponent,
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg,
            userState: PhotoUserState(
                keywords: [
                    "Places > Japan > Tokyo",
                    "People > Family",
                    "Family",
                ]
            )
        )
        let keywordStoreDirectory = temp.appendingPathComponent(
            "keyword-store",
            isDirectory: true
        )
        let keywordStore = CatalogStore(
            directory: keywordStoreDirectory
        )
        try keywordStore.saveKeywordDefinition(
            CatalogKeywordDefinition(
                path: "Places|Japan|Tokyo",
                synonyms: ["Edo"]
            )
        )
        let exportKeywords = try keywordStore.exportKeywords(
            for: asset.userState.keywords
        )

        try await ImageExporter.export(
            asset: asset,
            adjustments: .neutral,
            transform: .identity,
            to: outputURL,
            format: .jpeg(quality: 0.9),
            keywords: exportKeywords
        )

        let outputSource = try XCTUnwrap(
            CGImageSourceCreateWithURL(outputURL as CFURL, nil)
        )
        let outputProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [CFString: Any]
        )
        let tiff = outputProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake] as? String, "RAWDesk Test Camera")
        let iptc = outputProperties[
            kCGImagePropertyIPTCDictionary
        ] as? [CFString: Any]
        XCTAssertEqual(
            iptc?[kCGImagePropertyIPTCKeywords] as? [String],
            ["Tokyo", "Edo", "Family"]
        )
        XCTAssertEqual(
            iptc?[kCGImagePropertyIPTCCaptionAbstract] as? String,
            "Keep this embedded caption"
        )
        XCTAssertEqual(
            (outputProperties[kCGImagePropertyOrientation] as? NSNumber)?.intValue,
            1
        )
        XCTAssertEqual(
            (outputProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            50
        )
        XCTAssertEqual(
            (outputProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            80
        )
    }

    func testExportAppliesManualGPSOverrideAndHonorsRemoval()
        async throws
    {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-location-export-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temp,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temp) }

        let sourceURL = temp.appendingPathComponent("source.jpg")
        let manualURL = temp.appendingPathComponent("manual.jpg")
        let removedURL = temp.appendingPathComponent("removed.jpg")
        let privateURL = temp.appendingPathComponent("private.jpg")
        try writeJPEG(
            makeSolidImage(width: 48, height: 32, gray: 0.4),
            to: sourceURL,
            properties: [
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 35.681236,
                    kCGImagePropertyGPSLatitudeRef: "N",
                    kCGImagePropertyGPSLongitude: 139.767125,
                    kCGImagePropertyGPSLongitudeRef: "E",
                ] as [CFString: Any],
                kCGImagePropertyIPTCDictionary: [
                    kCGImagePropertyIPTCKeywords:
                        ["Keep Keyword"],
                    kCGImagePropertyIPTCCaptionAbstract:
                        "Keep Caption",
                    kCGImagePropertyIPTCSubLocation:
                        "Private Studio",
                    kCGImagePropertyIPTCCity: "Tokyo",
                    kCGImagePropertyIPTCProvinceState:
                        "Tokyo",
                    kCGImagePropertyIPTCCountryPrimaryLocationCode:
                        "JPN",
                    kCGImagePropertyIPTCCountryPrimaryLocationName:
                        "Japan",
                ] as [CFString: Any],
            ]
        )
        let manualLocation = try XCTUnwrap(
            PhotoLocation(
                latitude: -33.86882,
                longitude: 151.209296,
                altitude: 58
            )
        )
        let baseAsset = PhotoAsset(
            id: "location-export",
            url: sourceURL,
            path: sourceURL.path,
            filename: sourceURL.lastPathComponent,
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg,
            metadata: PhotoMetadata(
                location: try XCTUnwrap(
                    PhotoLocation(
                        latitude: 35.681236,
                        longitude: 139.767125
                    )
                )
            ),
            userState: PhotoUserState(
                locationOverride: manualLocation
            )
        )
        try await ImageExporter.export(
            asset: baseAsset,
            adjustments: .neutral,
            transform: .identity,
            to: manualURL,
            format: .jpeg(quality: 0.9)
        )
        let manualProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(
                try XCTUnwrap(
                    CGImageSourceCreateWithURL(
                        manualURL as CFURL,
                        nil
                    )
                ),
                0,
                nil
            ) as? [CFString: Any]
        )
        let manualGPS = try XCTUnwrap(
            manualProperties[kCGImagePropertyGPSDictionary]
                as? [CFString: Any]
        )
        XCTAssertEqual(
            (manualGPS[kCGImagePropertyGPSLatitude]
                as? NSNumber)?.doubleValue ?? 0,
            33.86882,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            manualGPS[kCGImagePropertyGPSLatitudeRef] as? String,
            "S"
        )
        XCTAssertEqual(
            (manualGPS[kCGImagePropertyGPSLongitude]
                as? NSNumber)?.doubleValue ?? 0,
            151.209296,
            accuracy: 0.000_001
        )

        var removedAsset = baseAsset
        removedAsset.userState.removeLocation()
        try await ImageExporter.export(
            asset: removedAsset,
            adjustments: .neutral,
            transform: .identity,
            to: removedURL,
            format: .jpeg(quality: 0.9)
        )
        let removedProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(
                try XCTUnwrap(
                    CGImageSourceCreateWithURL(
                        removedURL as CFURL,
                        nil
                    )
                ),
                0,
                nil
            ) as? [CFString: Any]
        )
        XCTAssertNil(
            removedProperties[kCGImagePropertyGPSDictionary]
        )

        try await ImageExporter.export(
            asset: baseAsset,
            adjustments: .neutral,
            transform: .identity,
            to: privateURL,
            format: .jpeg(quality: 0.9),
            suppressLocation: true
        )
        let privateProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(
                try XCTUnwrap(
                    CGImageSourceCreateWithURL(
                        privateURL as CFURL,
                        nil
                    )
                ),
                0,
                nil
            ) as? [CFString: Any]
        )
        XCTAssertNil(
            privateProperties[kCGImagePropertyGPSDictionary]
        )
        let privateIPTC = try XCTUnwrap(
            privateProperties[kCGImagePropertyIPTCDictionary]
                as? [CFString: Any]
        )
        XCTAssertEqual(
            privateIPTC[kCGImagePropertyIPTCKeywords]
                as? [String],
            ["Keep Keyword"]
        )
        XCTAssertEqual(
            privateIPTC[
                kCGImagePropertyIPTCCaptionAbstract
            ] as? String,
            "Keep Caption"
        )
        XCTAssertNil(
            privateIPTC[kCGImagePropertyIPTCSubLocation]
        )
        XCTAssertNil(privateIPTC[kCGImagePropertyIPTCCity])
        XCTAssertNil(
            privateIPTC[kCGImagePropertyIPTCProvinceState]
        )
        XCTAssertNil(
            privateIPTC[
                kCGImagePropertyIPTCCountryPrimaryLocationCode
            ]
        )
        XCTAssertNil(
            privateIPTC[
                kCGImagePropertyIPTCCountryPrimaryLocationName
            ]
        )
    }

    private func makeSolidImage(width: Int, height: Int, gray: CGFloat) -> NSImage {
        makeColorImage(
            width: width,
            height: height,
            color: NSColor(white: gray, alpha: 1)
        )
    }

    private func makeColorImage(
        width: Int,
        height: Int,
        color: NSColor
    ) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let converted = color.usingColorSpace(.sRGB) ?? color
        context.setFillColor(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func makeRadialChromaticImage(
        width: Int,
        height: Int
    ) -> (
        image: NSImage,
        raster: ChromaticAberrationRaster
    ) {
        let centerX = Double(width - 1) / 2
        let centerY = Double(height - 1) / 2
        var rgba = [UInt8](
            repeating: 255,
            count: width * height * 4
        )

        func channel(
            radius: Double,
            edge: Double
        ) -> UInt8 {
            let transition = min(
                1,
                max(0, (radius - edge + 2) / 4)
            )
            let smooth =
                transition * transition
                * (3 - 2 * transition)
            return UInt8(
                (224 - smooth * 184).rounded()
            )
        }

        for y in 0..<height {
            for x in 0..<width {
                let radius = hypot(
                    Double(x) - centerX,
                    Double(y) - centerY
                )
                let offset = (y * width + x) * 4
                rgba[offset] = channel(
                    radius: radius,
                    edge: 45
                )
                rgba[offset + 1] = channel(
                    radius: radius,
                    edge: 42
                )
                rgba[offset + 2] = channel(
                    radius: radius,
                    edge: 39
                )
            }
        }
        let raster = ChromaticAberrationRaster(
            width: width,
            height: height,
            rgba: rgba
        )!
        let data = Data(rgba) as CFData
        let provider = CGDataProvider(data: data)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue:
                    CGImageAlphaInfo
                        .premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        return (
            NSImage(
                cgImage: cgImage,
                size: NSSize(
                    width: width,
                    height: height
                )
            ),
            raster
        )
    }

    private func radialChromaticError(
        in image: NSImage,
        innerRadius: Double,
        outerRadius: Double
    ) -> Double {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return .infinity
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let centerX = Double(bitmap.pixelsWide - 1) / 2
        let centerY = Double(bitmap.pixelsHigh - 1) / 2
        var total = 0.0
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let radius = hypot(
                    Double(x) - centerX,
                    Double(y) - centerY
                )
                guard radius >= innerRadius,
                      radius <= outerRadius,
                      let color = bitmap.colorAt(
                        x: x,
                        y: y
                      )?.usingColorSpace(.sRGB) else {
                    continue
                }
                total += Double(
                    abs(
                        color.redComponent
                            - color.greenComponent
                    )
                    + abs(
                        color.blueComponent
                            - color.greenComponent
                    )
                )
                count += 1
            }
        }
        return total / Double(max(1, count))
    }

    private func makeSplitImage(
        width: Int,
        height: Int,
        left: NSColor,
        right: NSColor
    ) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let convertedLeft = left.usingColorSpace(.sRGB) ?? left
        context.setFillColor(convertedLeft.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let convertedRight = right.usingColorSpace(.sRGB) ?? right
        context.setFillColor(convertedRight.cgColor)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func makeHorizontalSplitImage(
        width: Int,
        height: Int,
        top: NSColor,
        bottom: NSColor
    ) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let convertedBottom = bottom.usingColorSpace(.sRGB) ?? bottom
        context.setFillColor(convertedBottom.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        let convertedTop = top.usingColorSpace(.sRGB) ?? top
        context.setFillColor(convertedTop.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: height / 2,
                width: width,
                height: height - height / 2
            )
        )
        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    private func makeSplitMaskPNG(width: Int, height: Int) throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(
                using: .png,
                properties: [:]
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private func makeSolidMaskPNG(width: Int, height: Int) throws -> Data {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(
                using: .png,
                properties: [:]
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private func makeColorCheckerboard(width: Int, height: Int) -> NSImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in 0..<height {
            for x in 0..<width {
                context.setFillColor(
                    ((x + y) % 2 == 0
                        ? NSColor(srgbRed: 0.95, green: 0.05, blue: 0.35, alpha: 1)
                        : NSColor(srgbRed: 0.05, green: 0.4, blue: 0.95, alpha: 1))
                        .cgColor
                )
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        let image = context.makeImage()!
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        let left = lhs.usingColorSpace(.sRGB) ?? lhs
        let right = rhs.usingColorSpace(.sRGB) ?? rhs
        let red = left.redComponent - right.redComponent
        let green = left.greenComponent - right.greenComponent
        let blue = left.blueComponent - right.blueComponent
        return sqrt(red * red + green * green + blue * blue)
    }

    private func brightness(of image: NSImage) -> CGFloat {
        color(of: image)?.brightnessComponent ?? 0
    }

    private func brightness(of image: NSImage, x: Int, y: Int) -> CGFloat {
        color(of: image, x: x, y: y)?.brightnessComponent ?? 0
    }

    private func brightnessVariance(of image: NSImage) -> CGFloat {
        var values: [CGFloat] = []
        for y in stride(from: 2, to: Int(image.size.height) - 2, by: 3) {
            for x in stride(from: 2, to: Int(image.size.width) - 2, by: 3) {
                values.append(brightness(of: image, x: x, y: y))
            }
        }
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / CGFloat(values.count)
        return values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / CGFloat(values.count)
    }

    private func saturation(of image: NSImage) -> CGFloat {
        color(of: image)?.saturationComponent ?? 0
    }

    private func color(of image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
            .usingColorSpace(.sRGB)
    }

    private func color(of image: NSImage, x: Int, y: Int) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let clampedX = min(bitmap.pixelsWide - 1, max(0, x))
        let clampedY = min(bitmap.pixelsHigh - 1, max(0, y))
        return bitmap.colorAt(x: clampedX, y: clampedY)?.usingColorSpace(.sRGB)
    }

    private func writeJPEG(
        _ image: NSImage,
        to url: URL,
        properties: [CFString: Any]? = nil
    ) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.jpeg" as CFString,
                1,
                nil
              ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary?)
        if !CGImageDestinationFinalize(destination) {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

final class ImageCacheTests: XCTestCase {
    func testThumbnailPersistsAcrossCacheInstances() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = NSImage(size: NSSize(width: 32, height: 24))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 24).fill()
        image.unlockFocus()

        let first = ImageCache(directory: directory)
        first.storeThumbnail(image, for: "stable-key")
        first.flushDiskWrites()

        let second = ImageCache(directory: directory)
        let restored = second.thumbnail(for: "stable-key")
        XCTAssertNotNil(restored)
        XCTAssertNil(second.thumbnail(for: "different-key"))
    }

    func testThumbnailDecodeSourcePersistsAcrossCacheInstances()
        throws
    {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-cache-source-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let image = NSImage(
            size: NSSize(width: 32, height: 24)
        )
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(
            x: 0,
            y: 0,
            width: 32,
            height: 24
        ).fill()
        image.unlockFocus()

        let first = ImageCache(directory: directory)
        first.storeThumbnail(
            image,
            for: "raw-source-key",
            rawDecodeSource: .ciRAWFilter
        )
        first.flushDiskWrites()

        let second = ImageCache(directory: directory)
        XCTAssertNotNil(
            second.thumbnail(for: "raw-source-key")
        )
        XCTAssertEqual(
            second.thumbnailDecodeSource(
                for: "raw-source-key"
            ),
            .ciRAWFilter
        )
    }

    func testLegacyRawThumbnailRestoresWithoutRedecode()
        async throws
    {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-legacy-raw-cache-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let missingURL = directory
            .appendingPathComponent("missing.ARW")
        let asset = PhotoAsset(
            id: "legacy-cached-raw",
            url: missingURL,
            path: missingURL.path,
            filename: missingURL.lastPathComponent,
            fileExtension: "ARW",
            fileSize: 42,
            creationDate: nil,
            modificationDate:
                Date(timeIntervalSince1970: 1_700_000_000),
            format: .sonyARW
        )
        let target: CGFloat = 256
        let key = ImageCache.key(
            for: asset,
            target: target,
            scale: 1
        )
        let image = NSImage(
            size: NSSize(width: 32, height: 24)
        )
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(
            x: 0,
            y: 0,
            width: 32,
            height: 24
        ).fill()
        image.unlockFocus()

        let first = ImageCache(directory: directory)
        first.storeThumbnail(image, for: key)
        first.flushDiskWrites()

        let loader = ImageLoader(
            cache: ImageCache(directory: directory),
            maxConcurrent: 1
        )
        let outcome = await loader.load(
            asset: asset,
            kind: .thumbnail(target: target)
        )
        XCTAssertEqual(outcome.state, .loaded)
        XCTAssertNotNil(outcome.image)
        XCTAssertNil(outcome.rawDecodeSource)
    }
}

final class ImageLoadGateTests: XCTestCase {
    private actor OrderRecorder {
        private var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }

        func snapshot() -> [String] {
            values
        }
    }

    private func waitForPending(
        _ expected: Int,
        in gate: ImageLoadGate
    ) async throws {
        for _ in 0..<200 {
            let counts = await gate.counts()
            if counts.pending == expected {
                return
            }
            try await Task.sleep(
                for: .milliseconds(5)
            )
        }
        XCTFail(
            "Expected \(expected) queued image loads."
        )
    }

    func testCanceledWaiterDoesNotConsumePermit()
        async throws
    {
        let gate = ImageLoadGate(limit: 1)
        let acquired = await gate.acquire(
            priority: .thumbnail
        )
        XCTAssertTrue(acquired)

        let waiting = Task {
            await gate.acquire(
                priority: .thumbnail
            )
        }
        try await waitForPending(1, in: gate)
        waiting.cancel()
        let waitingResult = await waiting.value
        XCTAssertFalse(waitingResult)

        let queuedCounts = await gate.counts()
        XCTAssertEqual(queuedCounts.active, 1)
        XCTAssertEqual(queuedCounts.pending, 0)
        await gate.release()
        let finalCounts = await gate.counts()
        XCTAssertEqual(finalCounts.active, 0)
        XCTAssertEqual(finalCounts.pending, 0)
    }

    func testPreviewWaiterRunsBeforeEarlierThumbnail()
        async throws
    {
        let gate = ImageLoadGate(limit: 1)
        let recorder = OrderRecorder()
        let acquired = await gate.acquire(
            priority: .thumbnail
        )
        XCTAssertTrue(acquired)

        let thumbnail = Task {
            guard await gate.acquire(
                priority: .thumbnail
            ) else {
                return
            }
            await recorder.append("thumbnail")
            await gate.release()
        }
        try await waitForPending(1, in: gate)

        let preview = Task {
            guard await gate.acquire(
                priority: .preview
            ) else {
                return
            }
            await recorder.append("preview")
            await gate.release()
        }
        try await waitForPending(2, in: gate)

        await gate.release()
        await preview.value
        await thumbnail.value
        let order = await recorder.snapshot()
        XCTAssertEqual(
            order,
            ["preview", "thumbnail"]
        )
        let counts = await gate.counts()
        XCTAssertEqual(counts.active, 0)
        XCTAssertEqual(counts.pending, 0)
    }
}

final class LargeLibraryPerformanceTests: XCTestCase {
    func testTenThousandPhotoFilterAndSortStayInteractive() {
        let assets = (0..<10_000).map { index in
            let filename = String(
                format: "frame-%05d.jpg",
                index
            )
            return PhotoAsset(
                id: "large-\(index)",
                url: URL(
                    fileURLWithPath: "/virtual/\(filename)"
                ),
                path: "/virtual/\(filename)",
                filename: filename,
                fileExtension: "jpg",
                fileSize: Int64(index + 1),
                creationDate: Date(
                    timeIntervalSince1970: Double(index)
                ),
                modificationDate: nil,
                format: .jpeg,
                userState: PhotoUserState(
                    rating: index % 6
                )
            )
        }
        let filter = FilterState(
            searchText: "frame-09",
            minimumRating: 3
        )

        let started = CFAbsoluteTimeGetCurrent()
        let visible = LibrarySort.filename.sorted(
            assets.filter(filter.matches),
            ascending: true
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertEqual(visible.count, 499)
        XCTAssertEqual(
            visible.first?.filename,
            "frame-09003.jpg"
        )
        XCTAssertEqual(
            visible.last?.filename,
            "frame-09999.jpg"
        )
        XCTAssertLessThan(
            elapsed,
            2,
            "Filtering and sorting 10,000 in-memory photos must remain within an interactive QA budget."
        )
    }

    func testWarmRawGridRestoresFirstViewportWithoutRedecode()
        async throws
    {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-large-warm-grid-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let assets = (0..<4_706).map { index in
            let filename = String(
                format: "raw-%05d.ARW",
                index
            )
            let url = directory
                .appendingPathComponent(filename)
            return PhotoAsset(
                id: "large-raw-\(index)",
                url: url,
                path: url.path,
                filename: filename,
                fileExtension: "ARW",
                fileSize: Int64(index + 10),
                creationDate: nil,
                modificationDate:
                    Date(
                        timeIntervalSince1970:
                            1_700_000_000
                            + Double(index)
                    ),
                format: .sonyARW
            )
        }
        let firstViewport = Array(assets.prefix(24))
        let target: CGFloat = 256
        let image = NSImage(
            size: NSSize(width: 48, height: 32)
        )
        image.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(
            x: 0,
            y: 0,
            width: 48,
            height: 32
        ).fill()
        image.unlockFocus()

        let writer = ImageCache(directory: directory)
        for asset in firstViewport {
            writer.storeThumbnail(
                image,
                for: ImageCache.key(
                    for: asset,
                    target: target,
                    scale: 1
                )
            )
        }
        writer.flushDiskWrites()

        let loader = ImageLoader(
            cache: ImageCache(directory: directory),
            maxConcurrent: 3
        )
        let started = CFAbsoluteTimeGetCurrent()
        let outcomes = await withTaskGroup(
            of: ImageLoader.LoadOutcome.self,
            returning:
                [ImageLoader.LoadOutcome].self
        ) { group in
            for asset in firstViewport {
                group.addTask {
                    await loader.load(
                        asset: asset,
                        kind:
                            .thumbnail(target: target)
                    )
                }
            }
            var values:
                [ImageLoader.LoadOutcome] = []
            for await outcome in group {
                values.append(outcome)
            }
            return values
        }
        let elapsed =
            CFAbsoluteTimeGetCurrent() - started

        XCTAssertEqual(outcomes.count, 24)
        XCTAssertTrue(
            outcomes.allSatisfy {
                $0.state == .loaded
                    && $0.image != nil
                    && $0.rawDecodeSource == nil
            }
        )
        XCTAssertLessThan(
            elapsed,
            2,
            "A warm 24-cell RAW viewport should never wait for source-file decoding."
        )
    }
}

final class SonyARWIntegrationTests: XCTestCase {
    func testRealSonyAlphaARWRoundTripPreservesOriginal()
        async throws
    {
        let fixtureDirectory = try fixtureDirectory()
        let sourceURL = fixtureDirectory
            .appendingPathComponent("ETH01641.ARW")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw XCTSkip(
                "ETH01641.ARW is not present in the configured fixture directory."
            )
        }

        let sourceHashBefore = try FileContentHasher.sha256(
            for: sourceURL
        )
        let canonicalSidecar =
            XMPSidecarService.canonicalSidecarURL(for: sourceURL)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: canonicalSidecar.path
            )
        )

        let inspection = try PhotoLibraryScanner.inspectAsset(
            at: sourceURL,
            userStates: [:]
        )
        let asset = inspection.asset
        XCTAssertEqual(asset.format, .sonyARW)
        XCTAssertTrue(asset.isSonyARW)
        XCTAssertEqual(asset.metadata?.cameraMake, "SONY")
        XCTAssertEqual(asset.metadata?.cameraModel, "ILCE-7M4")
        XCTAssertEqual(asset.metadata?.pixelWidth, 4_608)
        XCTAssertEqual(asset.metadata?.pixelHeight, 3_072)
        XCTAssertEqual(asset.metadata?.iso, 1_600)
        XCTAssertEqual(
            asset.metadata?.shutterSpeed ?? 0,
            0.008,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            asset.metadata?.aperture ?? 0,
            4,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            asset.metadata?.focalLength ?? 0,
            70,
            accuracy: 0.000_001
        )

        let thumbnail = try ThumbnailGenerator.generate(
            for: asset,
            targetPixelSize: 512,
            quality: .grid
        )
        let thumbnailCG = try XCTUnwrap(
            thumbnail.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        )
        XCTAssertGreaterThan(thumbnailCG.width, 0)
        XCTAssertGreaterThan(thumbnailCG.height, 0)
        XCTAssertLessThanOrEqual(
            max(thumbnailCG.width, thumbnailCG.height),
            512
        )

        let preview = try ThumbnailGenerator.generate(
            for: asset,
            targetPixelSize: 1_440,
            quality: .preview
        )
        let previewCG = try XCTUnwrap(
            preview.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        )
        XCTAssertEqual(
            max(previewCG.width, previewCG.height),
            1_440
        )
        XCTAssertEqual(previewCG.bitsPerComponent, 16)

        let adjustments = PhotoAdjustments(
            exposure: 0.65,
            contrast: 9,
            highlights: -28,
            shadows: 22,
            whites: 8,
            blacks: -7,
            temperature: 12,
            tint: 3,
            vibrance: 18,
            texture: 10,
            clarity: 8,
            dehaze: 5,
            sharpening: 35,
            noiseReduction: 18,
            colorNoiseReduction: 25
        )
        let developed = try PhotoProcessor.renderFullResolution(
            asset: asset,
            adjustments: adjustments
        )
        let developedCG = try XCTUnwrap(
            developed.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        )
        XCTAssertEqual(developedCG.width, 4_608)
        XCTAssertEqual(developedCG.height, 3_072)

        let outputDirectory = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-sony-arw-integration-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: outputDirectory
            )
        }

        let imageCache = ImageCache(
            directory:
                outputDirectory
                    .appendingPathComponent(
                        "image-cache",
                        isDirectory: true
                    )
        )
        let imageLoader = ImageLoader(
            cache: imageCache,
            maxConcurrent: 1
        )
        let firstLoad =
            await imageLoader.load(
                asset: asset,
                kind: .thumbnail(target: 512)
            )
        XCTAssertEqual(
            firstLoad.state,
            .loaded
        )
        XCTAssertNotNil(firstLoad.image)
        XCTAssertNil(
            firstLoad.rawDecodeSource,
            "Grid thumbnails must not block on full RAW decoder classification."
        )

        let cachedLoad =
            await imageLoader.load(
                asset: asset,
                kind: .thumbnail(target: 512)
            )
        XCTAssertEqual(
            cachedLoad.state,
            .loaded
        )
        XCTAssertNotNil(cachedLoad.image)
        XCTAssertNil(cachedLoad.rawDecodeSource)

        imageCache.flushDiskWrites()
        let restartedLoader = ImageLoader(
            cache: ImageCache(
                directory:
                    outputDirectory
                        .appendingPathComponent(
                            "image-cache",
                            isDirectory: true
                        )
            ),
            maxConcurrent: 1
        )
        let restartedLoad =
            await restartedLoader.load(
                asset: asset,
                kind: .thumbnail(target: 512)
            )
        XCTAssertEqual(
            restartedLoad.state,
            .loaded
        )
        XCTAssertNotNil(restartedLoad.image)
        XCTAssertNil(
            restartedLoad.rawDecodeSource,
            "A persisted grid thumbnail must display before RAW decoder inspection."
        )

        let previewLoad =
            await imageLoader.load(
                asset: asset,
                kind: .preview(target: 512)
            )
        XCTAssertEqual(previewLoad.state, .loaded)
        XCTAssertNotNil(previewLoad.image)
        let firstDecodeSource =
            try XCTUnwrap(
                previewLoad.rawDecodeSource
            )
        let cachedPreviewLoad =
            await imageLoader.load(
                asset: asset,
                kind: .preview(target: 512)
            )
        XCTAssertEqual(
            cachedPreviewLoad.rawDecodeSource,
            firstDecodeSource
        )

        let catalogDirectory = outputDirectory
            .appendingPathComponent(
                "catalog",
                isDirectory: true
            )
        let expectedState = PhotoUserState(
            rating: 4,
            flagged: true,
            note: "Sony alpha real-RAW integration",
            adjustments: adjustments
        )
        do {
            let catalog = CatalogStore(
                directory: catalogDirectory
            )
            try catalog.upsert(
                assets: [asset],
                rootURL: fixtureDirectory,
                recursive: false
            )
            try catalog.updateUserState(
                id: asset.id,
                state: expectedState
            )
        }
        let reopenedCatalog = CatalogStore(
            directory: catalogDirectory
        )
        let restoredStates = try reopenedCatalog.userStates(
            rootPath: fixtureDirectory.path
        )
        XCTAssertEqual(restoredStates[asset.id], expectedState)

        let exportURL = outputDirectory
            .appendingPathComponent("ETH01641-developed.jpg")
        try await ImageExporter.export(
            asset: asset,
            adjustments: adjustments,
            transform: .identity,
            to: exportURL,
            format: .jpeg(quality: 0.92)
        )
        let exportedSource = try XCTUnwrap(
            CGImageSourceCreateWithURL(
                exportURL as CFURL,
                nil
            )
        )
        let exportedProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(
                exportedSource,
                0,
                nil
            ) as? [CFString: Any]
        )
        XCTAssertEqual(
            (exportedProperties[kCGImagePropertyPixelWidth]
                as? NSNumber)?.intValue,
            4_608
        )
        XCTAssertEqual(
            (exportedProperties[kCGImagePropertyPixelHeight]
                as? NSNumber)?.intValue,
            3_072
        )
        let exportedTIFF = try XCTUnwrap(
            exportedProperties[kCGImagePropertyTIFFDictionary]
                as? [CFString: Any]
        )
        XCTAssertEqual(
            exportedTIFF[kCGImagePropertyTIFFMake] as? String,
            "SONY"
        )
        XCTAssertEqual(
            exportedTIFF[kCGImagePropertyTIFFModel] as? String,
            "ILCE-7M4"
        )

        XCTAssertEqual(
            try FileContentHasher.sha256(for: sourceURL),
            sourceHashBefore
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: canonicalSidecar.path
            )
        )
    }

    func testRealSonyAndCanonGridThumbnailsUseEmbeddedFastPath()
        throws
    {
        let directory = try fixtureDirectory()
        for filename in [
            "ETH01641.ARW",
            "IMG_0002.CR2",
        ] {
            let url = directory
                .appendingPathComponent(filename)
            guard FileManager.default.fileExists(
                atPath: url.path
            ) else {
                throw XCTSkip(
                    "\(filename) is not present in the configured fixture directory."
                )
            }
            let hashBefore =
                try FileContentHasher.sha256(
                    for: url
                )
            let started =
                CFAbsoluteTimeGetCurrent()
            let thumbnail =
                RAWImageLoader.loadGridThumbnail(
                    url: url,
                    targetLongestEdge: 256
                )
            let elapsed =
                CFAbsoluteTimeGetCurrent()
                - started

            XCTAssertNotNil(
                thumbnail,
                "\(filename) should expose an embedded grid thumbnail."
            )
            XCTAssertLessThan(
                elapsed,
                2,
                "\(filename) grid thumbnail should not run a full RAW decode."
            )
            XCTAssertEqual(
                try FileContentHasher.sha256(
                    for: url
                ),
                hashBefore
            )
        }
    }

    private func fixtureDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment[
            "RAWDESK_SONY_ARW_FIXTURE_DIR"
        ],
        !path.isEmpty else {
            throw XCTSkip(
                "Set RAWDESK_SONY_ARW_FIXTURE_DIR to run real Sony ARW integration."
            )
        }
        return URL(
            fileURLWithPath: path,
            isDirectory: true
        ).standardizedFileURL
    }
}

final class MetadataReaderTests: XCTestCase {
    /// Synthesize a tiny JPEG with TIFF/EXIF tags and verify the reader extracts them.
    func testReadsBasicEXIF() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-meta-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Build a 16x12 RGB image.
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 16, height: 12,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = ctx.makeImage() else {
            XCTFail("Could not synthesize image"); return
        }

        let props: [String: Any] = [
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFMake as String: "TestCamera",
                kCGImagePropertyTIFFModel as String: "TM-100"
            ],
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifISOSpeedRatings as String: [400 as NSNumber],
                kCGImagePropertyExifFNumber as String: 4.0 as NSNumber,
                kCGImagePropertyExifExposureTime as String: 0.004 as NSNumber,
                kCGImagePropertyExifFocalLength as String: 50.0 as NSNumber,
                kCGImagePropertyExifDateTimeOriginal as String: "2024:01:02 03:04:05"
            ]
        ]

        guard let dest = CGImageDestinationCreateWithURL(
            tmp as CFURL, "public.jpeg" as CFString, 1, nil
        ) else { XCTFail("dest"); return }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let m = MetadataReader.read(url: tmp)
        XCTAssertNil(m.error)
        XCTAssertEqual(m.pixelWidth, 16)
        XCTAssertEqual(m.pixelHeight, 12)
        XCTAssertEqual(m.cameraMake, "TestCamera")
        XCTAssertEqual(m.cameraModel, "TM-100")
        XCTAssertEqual(m.iso, 400)
        XCTAssertEqual(m.aperture, 4.0)
        XCTAssertEqual(m.shutterSpeed ?? 0, 0.004, accuracy: 0.0001)
        XCTAssertEqual(m.focalLength, 50.0)
        XCTAssertNotNil(m.captureDate)
        XCTAssertEqual(
            m.readerVersion,
            MetadataReader.currentReaderVersion
        )
    }

    func testReadsSignedGPSAndAltitude() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-gps-\(UUID().uuidString).jpg"
            )
        defer { try? FileManager.default.removeItem(at: tmp) }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 16,
            height: 12,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo:
                CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            tmp as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            XCTFail("Could not synthesize GPS image")
            return
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.86882,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 151.209296,
                kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSAltitude: 7.25,
                kCGImagePropertyGPSAltitudeRef: 1,
            ] as [CFString: Any],
        ]
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let metadata = MetadataReader.read(url: tmp)
        let location = try XCTUnwrap(metadata.location)
        XCTAssertEqual(location.latitude, -33.86882, accuracy: 0.000_001)
        XCTAssertEqual(location.longitude, 151.209296, accuracy: 0.000_001)
        XCTAssertEqual(
            try XCTUnwrap(location.altitude),
            -7.25,
            accuracy: 0.001
        )
    }
}

final class PhotoLibraryScannerTests: XCTestCase {
    func testScanRecognizesExtensions() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        for name in ["a.jpg", "b.ARW", "c.cr2", "d.txt", "e.dng"] {
            let f = tmp.appendingPathComponent(name)
            try Data([0x00]).write(to: f)
        }

        let scanner = PhotoLibraryScanner()
        let result = await scanner.scan(rootURL: tmp, recursive: false, userStates: [:])
        let names = Set(result.assets.map { $0.filename })
        XCTAssertEqual(names, ["a.jpg", "b.ARW", "c.cr2", "e.dng"])
        XCTAssertTrue(result.assets.contains { $0.format == .sonyARW && $0.isSonyARW })
        XCTAssertTrue(result.assets.contains { $0.format == .canonCR2 && $0.isCanonCR2 })
    }

    func testInitialScanCatalogsEmbeddedCaptureTime() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-scan-metadata-\(UUID().uuidString)",
                isDirectory: true
            )
        let catalogDirectory = temp.appendingPathComponent(
            "catalog",
            isDirectory: true
        )
        let photosDirectory = temp.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: photosDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temp) }

        let photoURL = photosDirectory.appendingPathComponent("burst.jpg")
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 16,
                height: 12,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:
                    CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                photoURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImagePropertyExifDictionary as String: [
                    kCGImagePropertyExifDateTimeOriginal as String:
                        "2026:07:25 12:00:05"
                ],
                kCGImagePropertyTIFFDictionary as String: [
                    kCGImagePropertyTIFFMake as String: "RAWDesk QA",
                    kCGImagePropertyTIFFModel as String: "Fixture Camera"
                ],
            ] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let scanner = PhotoLibraryScanner()
        let result = await scanner.scan(
            rootURL: photosDirectory,
            recursive: false,
            userStates: [:]
        )
        let asset = try XCTUnwrap(result.assets.first)
        let captureDate = try XCTUnwrap(asset.metadata?.captureDate)
        XCTAssertEqual(
            captureDate.timeIntervalSince1970,
            1_784_980_805,
            accuracy: 0.5
        )
        XCTAssertEqual(asset.metadata?.cameraMake, "RAWDesk QA")
        XCTAssertEqual(asset.metadata?.cameraModel, "Fixture Camera")

        let catalog = CatalogStore(directory: catalogDirectory)
        try catalog.upsert(
            assets: result.assets,
            rootURL: photosDirectory,
            recursive: false
        )
        let catalogAsset = try XCTUnwrap(
            catalog.entries(for: .allPhotos).first?.asset
        )
        XCTAssertEqual(
            catalogAsset.metadata?.captureDate?.timeIntervalSince1970,
            captureDate.timeIntervalSince1970
        )
    }

    func testFileIdentityAndUserStateSurviveRename() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawdesk-rename-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let originalURL = temp.appendingPathComponent("before.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: originalURL)
        let scanner = PhotoLibraryScanner()
        let first = await scanner.scan(rootURL: temp, recursive: false, userStates: [:])
        let firstAsset = try XCTUnwrap(first.assets.first)

        let renamedURL = temp.appendingPathComponent("after.jpg")
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        let expectedState = PhotoUserState(
            rating: 5,
            adjustments: PhotoAdjustments(exposure: 0.5)
        )
        let second = await scanner.scan(
            rootURL: temp,
            recursive: false,
            userStates: [firstAsset.id: expectedState]
        )
        let secondAsset = try XCTUnwrap(second.assets.first)

        XCTAssertEqual(secondAsset.id, firstAsset.id)
        XCTAssertEqual(secondAsset.filename, "after.jpg")
        XCTAssertEqual(secondAsset.userState, expectedState)
    }
}

final class LibraryViewModelTests: XCTestCase {
    private func makeAsset(id: String) -> PhotoAsset {
        PhotoAsset(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            path: "/tmp/\(id).jpg",
            filename: "\(id).jpg",
            fileExtension: "jpg",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg
        )
    }

    func testSelectionAfterScanKeepsCurrentWhenStillPresent() {
        let assets = [makeAsset(id: "a"), makeAsset(id: "b")]
        XCTAssertEqual(LibraryViewModel.selectionAfterScan(current: "b", assets: assets), "b")
    }

    func testSelectionAfterScanMovesToFirstWhenCurrentDisappears() {
        let assets = [makeAsset(id: "new-a"), makeAsset(id: "new-b")]
        XCTAssertEqual(LibraryViewModel.selectionAfterScan(current: "old", assets: assets), "new-a")
    }

    func testSelectionAfterScanClearsForEmptyFolder() {
        XCTAssertNil(LibraryViewModel.selectionAfterScan(current: "old", assets: []))
    }

    func testSelectionForVisibleAssetsKeepsCurrentWhenStillVisible() {
        let assets = [
            makeAsset(id: "a"),
            PhotoAsset(
                id: "b",
                url: URL(fileURLWithPath: "/tmp/b.jpg"),
                path: "/tmp/b.jpg",
                filename: "b.jpg",
                fileExtension: "jpg",
                fileSize: 1,
                creationDate: nil,
                modificationDate: nil,
                format: .jpeg,
                userState: PhotoUserState(rating: 4)
            )
        ]
        XCTAssertEqual(
            LibraryViewModel.selectionForVisibleAssets(
                current: "b",
                assets: assets,
                filter: FilterState(minimumRating: 3)
            ),
            "b"
        )
    }

    func testSelectionForVisibleAssetsMovesWhenCurrentIsFilteredOut() {
        let assets = [
            makeAsset(id: "plain"),
            PhotoAsset(
                id: "favorite",
                url: URL(fileURLWithPath: "/tmp/favorite.jpg"),
                path: "/tmp/favorite.jpg",
                filename: "favorite.jpg",
                fileExtension: "jpg",
                fileSize: 1,
                creationDate: nil,
                modificationDate: nil,
                format: .jpeg,
                userState: PhotoUserState(favorite: true)
            )
        ]
        XCTAssertEqual(
            LibraryViewModel.selectionForVisibleAssets(
                current: "plain",
                assets: assets,
                filter: FilterState(primary: .favoritesOnly)
            ),
            "favorite"
        )
    }

    func testSelectionForVisibleAssetsClearsWhenFilterHasNoMatches() {
        XCTAssertNil(
            LibraryViewModel.selectionForVisibleAssets(
                current: "plain",
                assets: [makeAsset(id: "plain")],
                filter: FilterState(primary: .favoritesOnly)
            )
        )
    }

    func testSelectionRangeIncludesBothEndpoints() {
        let assets = ["a", "b", "c", "d", "e"].map(makeAsset)
        XCTAssertEqual(
            LibraryViewModel.selectionRangeIDs(
                anchor: "b",
                target: "d",
                assets: assets
            ),
            ["b", "c", "d"]
        )
    }

    func testSelectionRangeFallsBackToTargetWhenAnchorIsMissing() {
        let assets = ["a", "b"].map(makeAsset)
        XCTAssertEqual(
            LibraryViewModel.selectionRangeIDs(
                anchor: "missing",
                target: "b",
                assets: assets
            ),
            ["b"]
        )
    }

    @MainActor
    func testSelectiveAndAutomaticAdjustmentSyncPreserveTargets()
        async throws
    {
        let base = URL(
            fileURLWithPath: NSTemporaryDirectory()
        )
        .appendingPathComponent(
            "rawdesk-adjustment-sync-\(UUID().uuidString)",
            isDirectory: true
        )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer {
            try? FileManager.default.removeItem(at: base)
        }
        for (index, name) in [
            "a.jpg", "b.jpg", "c.jpg",
        ].enumerated() {
            try Data([UInt8(index + 1)]).write(
                to: photos.appendingPathComponent(name)
            )
        }

        let library = LibraryViewModel(
            userStateStore: UserStateStore(
                directory: stores
            ),
            recentStore: RecentFolderStore(
                directory: stores
            ),
            catalogStore: CatalogStore(
                directory: stores
            )
        )
        library.recursiveScan = false
        library.sort = .filename
        library.sortAscending = true
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(
                for: .milliseconds(10)
            )
        }

        let ids = Dictionary(
            uniqueKeysWithValues:
                library.assets.map {
                    ($0.filename, $0.id)
                }
        )
        let a = try XCTUnwrap(ids["a.jpg"])
        let b = try XCTUnwrap(ids["b.jpg"])
        let c = try XCTUnwrap(ids["c.jpg"])

        library.setAdjustments(
            PhotoAdjustments(
                exposure: -0.5,
                contrast: -10,
                temperature: -20
            ),
            for: a,
            coalescingHistory: false
        )
        library.setAdjustments(
            PhotoAdjustments(
                exposure: 0.25,
                contrast: 8,
                temperature: 12
            ),
            for: b,
            coalescingHistory: false
        )
        library.setAdjustments(
            PhotoAdjustments(
                exposure: 1,
                contrast: 30,
                temperature: 40
            ),
            for: c,
            coalescingHistory: false
        )

        library.select(a)
        library.select(b, extending: true)
        library.select(c, extending: true)
        XCTAssertEqual(library.selectionID, c)
        XCTAssertTrue(
            library.canSynchronizeSelectedAdjustments
        )
        XCTAssertEqual(
            library.synchronizeSelectedAdjustments(
                groups: [.light]
            ),
            2
        )

        let syncedA = try XCTUnwrap(
            library.assets.first { $0.id == a }
        )
        XCTAssertEqual(
            syncedA.userState.adjustments.exposure,
            1
        )
        XCTAssertEqual(
            syncedA.userState.adjustments.contrast,
            30
        )
        XCTAssertEqual(
            syncedA.userState.adjustments.temperature,
            -20
        )

        var aAdjustments =
            syncedA.userState.adjustments
        aAdjustments.contrast = -40
        library.setAdjustments(
            aAdjustments,
            for: a,
            coalescingHistory: false
        )
        var bAdjustments = try XCTUnwrap(
            library.assets.first { $0.id == b }
        ).userState.adjustments
        bAdjustments.contrast = -50
        library.setAdjustments(
            bAdjustments,
            for: b,
            coalescingHistory: false
        )

        library.setAutoSyncEnabled(true)
        XCTAssertTrue(library.isAutoSyncEnabled)
        var active = try XCTUnwrap(
            library.assets.first { $0.id == c }
        ).userState.adjustments
        active.exposure = 2
        library.setAdjustments(
            active,
            for: c,
            coalescingHistory: false
        )

        let autoA = try XCTUnwrap(
            library.assets.first { $0.id == a }
        ).userState.adjustments
        let autoB = try XCTUnwrap(
            library.assets.first { $0.id == b }
        ).userState.adjustments
        XCTAssertEqual(autoA.exposure, 2)
        XCTAssertEqual(autoB.exposure, 2)
        XCTAssertEqual(autoA.contrast, -40)
        XCTAssertEqual(autoB.contrast, -50)
        XCTAssertEqual(autoA.temperature, -20)
        XCTAssertEqual(autoB.temperature, 12)

        library.undoAdjustments(for: a)
        XCTAssertEqual(
            library.assets.first { $0.id == a }?
                .userState.adjustments.exposure,
            1
        )
        XCTAssertEqual(
            library.assets.first { $0.id == a }?
                .userState.adjustments.contrast,
            -40
        )

        library.select(c)
        XCTAssertFalse(library.isAutoSyncEnabled)
        XCTAssertFalse(
            library.canSynchronizeSelectedAdjustments
        )
    }

    @MainActor
    func testCompareWorkflowKeepsCandidateActiveAndReconcilesFilter()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-compare-library-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        for (index, name) in ["a.jpg", "b.jpg", "c.jpg"]
            .enumerated() {
            try Data([UInt8(index + 1)]).write(
                to: photos.appendingPathComponent(name)
            )
        }

        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        library.recursiveScan = false
        library.sort = .filename
        library.sortAscending = true
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            library.filtered.map(\.filename),
            ["a.jpg", "b.jpg", "c.jpg"]
        )

        let ids = Dictionary(
            uniqueKeysWithValues:
                library.assets.map { ($0.filename, $0.id) }
        )
        let a = try XCTUnwrap(ids["a.jpg"])
        let b = try XCTUnwrap(ids["b.jpg"])
        let c = try XCTUnwrap(ids["c.jpg"])
        library.select(a)
        library.startCompare()

        XCTAssertEqual(
            library.compareState,
            PhotoCompareState(selectID: a, candidateID: b)
        )
        XCTAssertEqual(library.selectionID, b)
        XCTAssertEqual(library.compareRole(for: a), .select)
        XCTAssertEqual(
            library.compareRole(for: b),
            .candidate
        )

        library.select(c)
        XCTAssertEqual(library.compareState?.selectID, a)
        XCTAssertEqual(library.compareState?.candidateID, c)
        XCTAssertEqual(library.selectionID, c)

        library.setRating(5, for: c)
        XCTAssertEqual(
            library.assets.first { $0.id == c }?
                .userState.rating,
            5
        )
        XCTAssertEqual(
            library.assets.first { $0.id == a }?
                .userState.rating,
            0
        )

        library.swapComparePhotos()
        XCTAssertEqual(
            library.compareState,
            PhotoCompareState(selectID: c, candidateID: a)
        )
        XCTAssertEqual(library.selectionID, a)

        library.filter.minimumRating = 5
        XCTAssertNil(library.compareState)
        XCTAssertEqual(library.selectionID, c)
        XCTAssertEqual(library.selectedIDs, [c])
    }

    @MainActor
    func testSurveyWorkflowKeepsMetadataActiveOnlyAndSwitchesCompare()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-survey-library-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        for (index, name) in [
            "a.jpg", "b.jpg", "c.jpg", "d.jpg",
        ].enumerated() {
            try Data([UInt8(index + 1)]).write(
                to: photos.appendingPathComponent(name)
            )
        }

        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        library.recursiveScan = false
        library.sort = .filename
        library.sortAscending = true
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        let ids = Dictionary(
            uniqueKeysWithValues:
                library.assets.map { ($0.filename, $0.id) }
        )
        let a = try XCTUnwrap(ids["a.jpg"])
        let b = try XCTUnwrap(ids["b.jpg"])
        let c = try XCTUnwrap(ids["c.jpg"])
        let d = try XCTUnwrap(ids["d.jpg"])

        library.select(a)
        XCTAssertTrue(library.canSelectAllVisiblePhotos)
        library.selectAllVisiblePhotos()
        XCTAssertEqual(library.selectedIDs, [a, b, c, d])
        XCTAssertEqual(library.selectionID, a)
        library.select(d, extending: true)
        XCTAssertEqual(library.selectedIDs, [a, b, c])
        XCTAssertTrue(library.canStartSurvey)
        library.startSurvey()

        XCTAssertEqual(
            library.surveyState,
            PhotoSurveyState(
                photoIDs: [a, b, c],
                activeID: a
            )
        )
        XCTAssertEqual(library.selectedIDs, [a, b, c])
        XCTAssertEqual(library.surveyRole(for: a), .active)
        XCTAssertEqual(library.surveyRole(for: c), .selected)

        library.setRating(5, for: c)
        XCTAssertEqual(
            library.assets.first { $0.id == c }?
                .userState.rating,
            5
        )
        XCTAssertEqual(
            library.assets.first { $0.id == a }?
                .userState.rating,
            0
        )
        XCTAssertEqual(
            library.assets.first { $0.id == b }?
                .userState.rating,
            0
        )

        library.setSurveyActive(b)
        XCTAssertEqual(library.selectionID, b)
        XCTAssertEqual(library.selectedIDs, [a, b, c])

        library.addSurveyPhoto(d)
        XCTAssertEqual(
            library.surveyState,
            PhotoSurveyState(
                photoIDs: [a, b, c, d],
                activeID: d
            )
        )
        library.removeSurveyPhoto(d)
        XCTAssertEqual(
            library.surveyState,
            PhotoSurveyState(
                photoIDs: [a, b, c],
                activeID: c
            )
        )

        library.startCompare()
        XCTAssertNil(library.surveyState)
        XCTAssertEqual(
            library.compareState,
            PhotoCompareState(
                selectID: c,
                candidateID: a
            )
        )

        library.startSurvey()
        XCTAssertNil(library.compareState)
        XCTAssertEqual(
            library.surveyState,
            PhotoSurveyState(
                photoIDs: [a, c],
                activeID: a
            )
        )

        library.filter.minimumRating = 5
        XCTAssertNil(library.surveyState)
        XCTAssertEqual(library.selectionID, c)
        XCTAssertEqual(library.selectedIDs, [c])
    }

    @MainActor
    func testReferenceWorkflowKeepsActiveEditableAndLockedReferenceReusable()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-reference-library-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        for (index, name) in [
            "a.jpg", "b.jpg", "c.jpg", "d.jpg",
        ].enumerated() {
            try Data([UInt8(index + 1)]).write(
                to: photos.appendingPathComponent(name)
            )
        }

        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        library.recursiveScan = false
        library.sort = .filename
        library.sortAscending = true
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        let ids = Dictionary(
            uniqueKeysWithValues:
                library.assets.map { ($0.filename, $0.id) }
        )
        let a = try XCTUnwrap(ids["a.jpg"])
        let b = try XCTUnwrap(ids["b.jpg"])
        let c = try XCTUnwrap(ids["c.jpg"])
        let d = try XCTUnwrap(ids["d.jpg"])

        library.select(a)
        library.select(c, extending: true)
        library.startReferenceView()

        XCTAssertEqual(
            library.referenceState,
            PhotoReferenceState(
                referenceID: a,
                activeID: c
            )
        )
        XCTAssertEqual(library.referenceAsset?.id, a)
        XCTAssertEqual(library.selectionID, c)
        XCTAssertEqual(library.selectedIDs, [c])

        library.setRating(5, for: c)
        XCTAssertEqual(
            library.assets.first { $0.id == c }?
                .userState.rating,
            5
        )
        XCTAssertEqual(
            library.assets.first { $0.id == a }?
                .userState.rating,
            0
        )

        library.setReferencePhoto(b)
        library.setReferenceLayout(.topBottom)
        library.setReferenceLocked(true)
        XCTAssertEqual(
            library.referenceState,
            PhotoReferenceState(
                referenceID: b,
                activeID: c,
                layout: .topBottom,
                isReferenceLocked: true
            )
        )

        library.endReferenceView()
        XCTAssertNil(library.referenceState)
        XCTAssertEqual(library.lockedReferenceID, b)

        library.select(d)
        library.startReferenceView()
        XCTAssertEqual(
            library.referenceState,
            PhotoReferenceState(
                referenceID: b,
                activeID: d,
                layout: .topBottom,
                isReferenceLocked: true
            )
        )

        library.moveReferenceActive(direction: 1)
        XCTAssertEqual(library.referenceState?.activeID, a)
        XCTAssertEqual(library.selectionID, a)

        library.startCompare()
        XCTAssertNil(library.referenceState)
        XCTAssertEqual(
            library.compareState,
            PhotoCompareState(
                selectID: a,
                candidateID: b
            )
        )
        XCTAssertEqual(library.lockedReferenceID, b)

        library.startReferenceView()
        XCTAssertNil(library.compareState)
        XCTAssertEqual(
            library.referenceState,
            PhotoReferenceState(
                referenceID: a,
                activeID: b,
                layout: .topBottom
            )
        )
    }

    func testFilenameSortUsesNaturalOrdering() {
        let assets = [makeAsset(id: "IMG_10"), makeAsset(id: "IMG_2")]
        XCTAssertEqual(
            LibrarySort.filename.sorted(assets, ascending: true).map(\.id),
            ["IMG_2", "IMG_10"]
        )
    }

    func testRatingSortDescending() {
        var low = makeAsset(id: "low")
        low.userState.rating = 1
        var high = makeAsset(id: "high")
        high.userState.rating = 5
        XCTAssertEqual(
            LibrarySort.rating.sorted([low, high], ascending: false).map(\.id),
            ["high", "low"]
        )
    }

    func testPhotoStackLayoutGroupsMembersAndUsesVisibleRepresentative() {
        let outside = makeAsset(id: "outside")
        let top = makeAsset(id: "top")
        let second = makeAsset(id: "second")
        let third = makeAsset(id: "third")
        let stackID = UUID()
        let collapsed = CatalogPhotoStack(
            id: stackID,
            scopePath: "/tmp",
            memberIDs: ["top", "second", "third"],
            isCollapsed: true
        )
        let sorted = [outside, second, top, third]

        XCTAssertEqual(
            LibraryViewModel.applyPhotoStacks(
                to: sorted,
                stacks: [collapsed]
            ).map(\.id),
            ["outside", "top"]
        )
        XCTAssertEqual(
            LibraryViewModel.applyPhotoStacks(
                to: [second, third],
                stacks: [collapsed]
            ).map(\.id),
            ["second"]
        )

        let expanded = CatalogPhotoStack(
            id: stackID,
            scopePath: "/tmp",
            memberIDs: collapsed.memberIDs,
            isCollapsed: false
        )
        XCTAssertEqual(
            LibraryViewModel.applyPhotoStacks(
                to: sorted,
                stacks: [expanded]
            ).map(\.id),
            ["outside", "top", "second", "third"]
        )
    }

    func testCaptureTimeAutoStackPreviewUsesContiguousIntervalsAndFolderBoundaries() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func asset(
            _ id: String,
            folder: String,
            seconds: TimeInterval?,
            missing: Bool = false
        ) -> PhotoAsset {
            let url = URL(
                fileURLWithPath: "/tmp/\(folder)/\(id).jpg"
            )
            return PhotoAsset(
                id: id,
                url: url,
                path: url.path,
                filename: url.lastPathComponent,
                fileExtension: "jpg",
                fileSize: 1,
                creationDate: nil,
                modificationDate: nil,
                format: .jpeg,
                catalogMissing: missing,
                metadata: PhotoMetadata(
                    captureDate: seconds.map {
                        start.addingTimeInterval($0)
                    }
                )
            )
        }

        let assets = [
            asset("a", folder: "a", seconds: 0),
            asset("b", folder: "a", seconds: 10),
            asset("c", folder: "a", seconds: 20),
            asset("d", folder: "a", seconds: 31),
            asset("e", folder: "b", seconds: 5),
            asset("f", folder: "b", seconds: 15),
            asset("no-date", folder: "b", seconds: nil),
            asset(
                "unavailable",
                folder: "b",
                seconds: 15,
                missing: true
            ),
            asset("stacked-1", folder: "a", seconds: 21),
            asset("stacked-2", folder: "a", seconds: 22),
        ]
        let existingStack = CatalogPhotoStack(
            scopePath: "/tmp/a",
            memberIDs: ["stacked-1", "stacked-2"]
        )

        let preview = CaptureTimeAutoStackPlanner.preview(
            assets: Array(assets.reversed()),
            existingStacks: [existingStack],
            maximumGap: 10
        )

        XCTAssertEqual(preview.maximumGap, 10)
        XCTAssertEqual(preview.scopePhotoCount, 10)
        XCTAssertEqual(preview.eligiblePhotoCount, 6)
        XCTAssertEqual(preview.alreadyStackedPhotoCount, 2)
        XCTAssertEqual(preview.missingCaptureTimePhotoCount, 1)
        XCTAssertEqual(preview.unavailablePhotoCount, 1)
        XCTAssertEqual(preview.stackCount, 2)
        XCTAssertEqual(preview.groupedPhotoCount, 5)
        XCTAssertEqual(preview.ungroupedEligiblePhotoCount, 1)
        XCTAssertEqual(
            preview.photoIDGroups,
            [
                ["a", "b", "c"],
                ["e", "f"],
            ]
        )
        XCTAssertEqual(
            preview.groups.first?.firstCaptureDate,
            start
        )
        XCTAssertEqual(
            preview.groups.first?.lastCaptureDate,
            start.addingTimeInterval(20)
        )
    }

    func testCaptureTimeAutoStackZeroRequiresMatchingCaptureTimes() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func asset(
            _ id: String,
            folder: String,
            seconds: TimeInterval
        ) -> PhotoAsset {
            let url = URL(
                fileURLWithPath: "/tmp/\(folder)/\(id).jpg"
            )
            return PhotoAsset(
                id: id,
                url: url,
                path: url.path,
                filename: url.lastPathComponent,
                fileExtension: "jpg",
                fileSize: 1,
                creationDate: nil,
                modificationDate: nil,
                format: .jpeg,
                metadata: PhotoMetadata(
                    captureDate:
                        start.addingTimeInterval(seconds)
                )
            )
        }
        let assets = [
            asset("a", folder: "one", seconds: 0),
            asset("b", folder: "one", seconds: 0),
            asset("c", folder: "one", seconds: 1),
            asset("other-folder", folder: "two", seconds: 0),
        ]

        XCTAssertEqual(
            CaptureTimeAutoStackPlanner.preview(
                assets: assets,
                existingStacks: [],
                maximumGap: 0
            ).photoIDGroups,
            [["a", "b"]]
        )
        XCTAssertEqual(
            CaptureTimeAutoStackPlanner.preview(
                assets: assets,
                existingStacks: [],
                maximumGap: 1
            ).photoIDGroups,
            [["a", "b", "c"]]
        )
        XCTAssertEqual(
            CaptureTimeAutoStackPlanner.normalizedGap(7_200),
            3_600
        )
        XCTAssertEqual(
            CaptureTimeAutoStackView.durationLabel(3_600),
            "1 hour"
        )
    }

    @MainActor
    func testFolderScanIndexesCatalogAndSavedKeywordCollection() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-catalog-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent("photos", isDirectory: true)
        let stores = base.appendingPathComponent("stores", isDirectory: true)
        try FileManager.default.createDirectory(
            at: photos,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: stores,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: base) }
        try Data([0]).write(
            to: photos.appendingPathComponent("catalog-test.jpg")
        )

        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        library.recursiveScan = false
        library.open(folder: photos)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(library.isScanning)
        let id = try XCTUnwrap(library.selectionID)
        XCTAssertEqual(library.catalogSummary[.allPhotos], 1)

        library.addKeywords(["Tokyo", "Night"], for: id)
        XCTAssertEqual(library.catalogSummary[.withKeywords], 1)
        XCTAssertEqual(library.catalogSummary.keywordCounts["Tokyo"], 1)

        library.filter.keyword = "Tokyo"
        let saved = try XCTUnwrap(
            library.saveCurrentFilterAsSmartCollection(named: "Tokyo photos")
        )
        XCTAssertEqual(library.savedSmartCollections, [saved])

        library.showSavedSmartCollection(saved)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.activeSavedCollection, saved)
        XCTAssertEqual(library.filtered.map(\.filename), ["catalog-test.jpg"])

        library.showCatalog(.withKeywords)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.catalogCollection, .withKeywords)
        XCTAssertEqual(library.assets.count, 1)
        XCTAssertEqual(library.assets.first?.userState.keywords, ["Tokyo", "Night"])
    }

    @MainActor
    func testShowMapHydratesAnEmptyLibraryFromTheCatalog()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-map-catalog-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: photos,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: stores,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: base) }

        let photoURL = photos.appendingPathComponent("mapped.jpg")
        try Data([1, 2, 3, 4]).write(to: photoURL)
        let catalogStore = CatalogStore(directory: stores)
        try catalogStore.upsert(
            assets: [
                PhotoAsset(
                    id: "mapped",
                    url: photoURL,
                    path: photoURL.path,
                    filename: photoURL.lastPathComponent,
                    fileExtension: "jpg",
                    fileSize: 4,
                    creationDate: nil,
                    modificationDate: nil,
                    format: .jpeg
                ),
            ],
            rootURL: photos,
            recursive: false
        )

        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: catalogStore
        )
        XCTAssertTrue(library.assets.isEmpty)

        library.showMap()
        for _ in 0..<200 {
            if !library.isScanning, library.assets.count == 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(library.workspaceMode, .map)
        XCTAssertEqual(library.catalogCollection, .allPhotos)
        XCTAssertEqual(library.assets.map(\.id), ["mapped"])
    }

    @MainActor
    func testColorLabelPresetValidationActivationAndDeletion()
        throws
    {
        let stores = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-label-library-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: stores,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: stores) }

        let labelStore = PhotoColorLabelSetStore(directory: stores)
        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            colorLabelSetStore: labelStore,
            catalogStore: CatalogStore(directory: stores)
        )
        let invalid = PhotoColorLabelSet(
            name: "Invalid",
            red: "Same",
            yellow: "Same"
        )
        XCTAssertEqual(
            library.saveColorLabelSet(invalid),
            "Each color needs a unique label name."
        )

        let custom = PhotoColorLabelSet(
            name: "Newsroom",
            red: "Kill",
            yellow: "Hold",
            green: "Publish",
            blue: "Homepage",
            purple: "Archive"
        )
        XCTAssertNil(library.saveColorLabelSet(custom))
        XCTAssertEqual(library.activeColorLabelSetID, custom.id)
        XCTAssertEqual(
            library.colorLabelName(for: .green),
            "Publish"
        )

        let reopened = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            colorLabelSetStore:
                PhotoColorLabelSetStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        XCTAssertEqual(reopened.activeColorLabelSet, custom)
        XCTAssertNil(reopened.deleteColorLabelSet(custom.id))
        XCTAssertEqual(reopened.activeColorLabelSet, .standard)
        XCTAssertNotNil(
            reopened.deleteColorLabelSet(
                PhotoColorLabelSet.standardID
            )
        )
    }

    @MainActor
    func testColorLabelAppliesToMultiSelectionFiltersAndPersists()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-color-label-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }

        let firstURL = photos.appendingPathComponent("first.jpg")
        let secondURL = photos.appendingPathComponent("second.jpg")
        let firstBytes = Data([1, 2, 3, 4])
        let secondBytes = Data([5, 6, 7, 8])
        try firstBytes.write(to: firstURL)
        try secondBytes.write(to: secondURL)

        let catalogStore = CatalogStore(directory: stores)
        let colorLabelSetStore = PhotoColorLabelSetStore(
            directory: stores
        )
        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            colorLabelSetStore: colorLabelSetStore,
            catalogStore: catalogStore
        )
        let clientSet = PhotoColorLabelSet(
            name: "Client Workflow",
            red: "Remove",
            yellow: "Review",
            green: "Proof",
            blue: "Portfolio",
            purple: "Client Final"
        )
        XCTAssertNil(library.saveColorLabelSet(clientSet))
        XCTAssertEqual(library.activeColorLabelSet, clientSet)
        library.recursiveScan = false
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.assets.count, 2)

        let firstID = try XCTUnwrap(
            library.assets.first {
                $0.filename == "first.jpg"
            }?.id
        )
        let secondID = try XCTUnwrap(
            library.assets.first {
                $0.filename == "second.jpg"
            }?.id
        )
        library.select(firstID)
        library.select(secondID, extending: true)
        XCTAssertEqual(library.selectedIDs, [firstID, secondID])

        library.setColorLabel(.purple, for: secondID)
        XCTAssertTrue(
            library.assets.allSatisfy {
                $0.userState.colorLabel == .purple
            }
        )
        XCTAssertTrue(
            library.assets.allSatisfy {
                $0.userState.colorLabelMetadataValue
                    == "Client Final"
            }
        )
        XCTAssertEqual(
            library.catalogSummary.colorLabelCounts[.purple],
            2
        )

        library.filter.colorLabels = [.purple]
        XCTAssertEqual(
            Set(library.filtered.map(\.id)),
            [firstID, secondID]
        )
        let saved = try XCTUnwrap(
            library.saveCurrentFilterAsSmartCollection(
                named: "Purple selects"
            )
        )
        XCTAssertEqual(saved.filter.colorLabels, [.purple])

        let reopened = CatalogStore(directory: stores)
        XCTAssertEqual(
            Set(
                try reopened.entries(for: .allPhotos)
                    .map(\.userState.colorLabel)
            ),
            [.purple]
        )
        XCTAssertEqual(
            Set(
                try reopened.entries(for: .allPhotos)
                    .compactMap(
                        \.userState.colorLabelMetadataValue
                    )
            ),
            ["Client Final"]
        )
        XCTAssertEqual(
            PhotoColorLabelSetStore(directory: stores)
                .load().activeSet,
            clientSet
        )
        XCTAssertEqual(
            try reopened.savedSmartCollections().first?
                .filter.colorLabels,
            [.purple]
        )
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)
        XCTAssertNil(XMPSidecarService.existingSidecarURL(for: firstURL))
        XCTAssertNil(XMPSidecarService.existingSidecarURL(for: secondURL))
    }

    @MainActor
    func testManualPhotoStackUsesActivePhotoAndExpandsWithoutChangingBytes()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-stacks-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent("photos")
        let stores = base.appendingPathComponent("stores")
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let urls = ["first", "second", "outside"].map {
            photos.appendingPathComponent("\($0).jpg")
        }
        let bytes = [
            Data([1, 2, 3, 4]),
            Data([5, 6, 7, 8]),
            Data([9, 10, 11, 12]),
        ]
        for (url, data) in zip(urls, bytes) {
            try data.write(to: url)
        }

        let catalogStore = CatalogStore(directory: stores)
        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: catalogStore
        )
        library.recursiveScan = false
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        let firstID = try XCTUnwrap(
            library.assets.first {
                $0.filename == "first.jpg"
            }?.id
        )
        let secondID = try XCTUnwrap(
            library.assets.first {
                $0.filename == "second.jpg"
            }?.id
        )
        library.select(firstID)
        library.select(secondID, extending: true)
        XCTAssertEqual(library.selectionID, secondID)
        XCTAssertTrue(library.canStackSelectedPhotos)
        XCTAssertTrue(library.stackSelectedPhotos())
        XCTAssertEqual(library.photoStacks.count, 1)
        XCTAssertEqual(library.photoStacks[0].topPhotoID, secondID)
        XCTAssertTrue(library.photoStacks[0].isCollapsed)
        XCTAssertEqual(library.filtered.count, 2)

        library.togglePhotoStack(containing: secondID)
        XCTAssertFalse(library.photoStacks[0].isCollapsed)
        XCTAssertEqual(library.filtered.count, 3)

        library.movePhotoInStack(firstID, .top)
        XCTAssertEqual(library.photoStacks[0].topPhotoID, firstID)
        library.select(secondID)
        XCTAssertTrue(library.canSplitSelectedPhotoStack)
        XCTAssertTrue(library.splitSelectedPhotoStack())
        XCTAssertTrue(library.photoStacks.isEmpty)
        XCTAssertEqual(library.filtered.count, 3)
        XCTAssertTrue(try catalogStore.integrityCheck())
        for (url, data) in zip(urls, bytes) {
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }

    @MainActor
    func testCaptureTimeAutoStackIgnoresSelectionPersistsAndPreservesFiles()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-capture-stacks-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent("photos")
        let stores = base.appendingPathComponent("stores")
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }

        let records: [(String, URL, Data, TimeInterval)] = [
            (
                "first",
                photos.appendingPathComponent("first.jpg"),
                Data([1, 2, 3, 4]),
                0
            ),
            (
                "second",
                photos.appendingPathComponent("second.jpg"),
                Data([5, 6, 7, 8]),
                5
            ),
            (
                "outside",
                photos.appendingPathComponent("outside.jpg"),
                Data([9, 10, 11, 12]),
                40
            ),
        ]
        for (_, url, data, _) in records {
            try data.write(to: url)
        }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let catalogStore = CatalogStore(directory: stores)
        try catalogStore.upsert(
            assets: records.map { id, url, _, seconds in
                PhotoAsset(
                    id: id,
                    url: url,
                    path: url.path,
                    filename: url.lastPathComponent,
                    fileExtension: "jpg",
                    fileSize: 4,
                    creationDate: nil,
                    modificationDate: nil,
                    format: .jpeg,
                    metadata: PhotoMetadata(
                        captureDate:
                            start.addingTimeInterval(seconds)
                    )
                )
            },
            rootURL: photos,
            recursive: false
        )

        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: catalogStore
        )
        library.showCatalog(.allPhotos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(library.isScanning)
        library.select("outside")
        library.filter.searchText = "outside"
        XCTAssertEqual(library.filtered.map(\.id), ["outside"])
        XCTAssertTrue(library.canPresentCaptureTimeAutoStack)
        library.presentCaptureTimeAutoStack()
        XCTAssertTrue(library.isCaptureTimeAutoStackPresented)

        let preview = library.captureTimeAutoStackPreview(
            maximumGap: 5
        )
        XCTAssertEqual(
            preview.photoIDGroups,
            [["first", "second"]]
        )
        XCTAssertTrue(
            library.createCaptureTimePhotoStacks(maximumGap: 5)
        )
        XCTAssertFalse(library.isCaptureTimeAutoStackPresented)
        XCTAssertEqual(library.photoStacks.count, 1)
        XCTAssertEqual(
            library.photoStacks.first?.memberIDs,
            ["first", "second"]
        )
        XCTAssertEqual(library.catalogSummary.photoStackCount, 1)
        XCTAssertEqual(library.catalogSummary.stackedPhotoCount, 2)
        XCTAssertEqual(
            library.captureTimeAutoStackPreview(
                maximumGap: 3_600
            ).alreadyStackedPhotoCount,
            2
        )
        for (_, url, data, _) in records {
            XCTAssertEqual(try Data(contentsOf: url), data)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: url.deletingPathExtension()
                        .appendingPathExtension("xmp").path
                )
            )
        }

        let reopened = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        reopened.showCatalog(.allPhotos)
        for _ in 0..<300 where reopened.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(reopened.photoStacks.count, 1)
        XCTAssertEqual(
            reopened.photoStacks.first?.memberIDs,
            ["first", "second"]
        )
        XCTAssertTrue(try catalogStore.integrityCheck())
    }

    @MainActor
    func testQuickCollectionTogglesSelectionPersistsAndNeverDeletesFiles()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-quick-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let firstURL = photos.appendingPathComponent("first.jpg")
        let secondURL = photos.appendingPathComponent("second.jpg")
        let thirdURL = photos.appendingPathComponent("third.jpg")
        try Data([1, 2, 3, 4]).write(to: firstURL)
        try Data([5, 6, 7, 8]).write(to: secondURL)
        try Data([9, 10, 11, 12]).write(to: thirdURL)
        let sourceBytes = try Dictionary(
            uniqueKeysWithValues: [
                firstURL,
                secondURL,
                thirdURL,
            ].map {
                ($0, try Data(contentsOf: $0))
            }
        )

        let catalogStore = CatalogStore(directory: stores)
        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: catalogStore
        )
        library.recursiveScan = false
        library.sort = .filename
        library.sortAscending = true
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        let ids = Dictionary(
            uniqueKeysWithValues:
                library.assets.map { ($0.filename, $0.id) }
        )
        let firstID = try XCTUnwrap(ids["first.jpg"])
        let secondID = try XCTUnwrap(ids["second.jpg"])
        let thirdID = try XCTUnwrap(ids["third.jpg"])
        library.select(firstID)
        library.select(secondID, extending: true)

        XCTAssertTrue(
            library.toggleQuickCollection(for: secondID)
        )
        XCTAssertEqual(
            library.quickCollectionPhotoIDs,
            [firstID, secondID]
        )
        XCTAssertEqual(
            library.catalogSummary[.quickCollection],
            2
        )
        XCTAssertTrue(library.isInQuickCollection(firstID))
        XCTAssertTrue(library.isInQuickCollection(secondID))
        XCTAssertFalse(library.isInQuickCollection(thirdID))

        library.showCatalog(.quickCollection)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.catalogCollection, .quickCollection)
        XCTAssertEqual(
            Set(library.assets.map(\.filename)),
            ["first.jpg", "second.jpg"]
        )
        XCTAssertEqual(
            library.selectedIDs,
            [firstID, secondID]
        )
        XCTAssertTrue(
            library.toggleQuickCollectionForSelection()
        )
        XCTAssertTrue(library.quickCollectionPhotoIDs.isEmpty)
        XCTAssertTrue(library.assets.isEmpty)
        XCTAssertEqual(
            library.catalogSummary[.quickCollection],
            0
        )

        library.showCatalog(.allPhotos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        library.select(thirdID)
        XCTAssertTrue(
            library.toggleQuickCollectionForSelection()
        )
        XCTAssertEqual(library.quickCollectionPhotoIDs, [thirdID])

        let reopened = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        XCTAssertEqual(reopened.quickCollectionPhotoIDs, [thirdID])
        reopened.showCatalog(.quickCollection)
        for _ in 0..<300 where reopened.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            reopened.assets.map(\.filename),
            ["third.jpg"]
        )
        XCTAssertTrue(reopened.clearQuickCollection())
        XCTAssertTrue(reopened.assets.isEmpty)
        XCTAssertEqual(
            reopened.catalogSummary[.quickCollection],
            0
        )
        for (url, bytes) in sourceBytes {
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        XCTAssertTrue(try catalogStore.integrityCheck())
    }

    @MainActor
    func testRegularCollectionTargetOrderQuickConversionAndDeletionAreNonDestructive()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-collections-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let firstURL = photos.appendingPathComponent("first.jpg")
        let secondURL = photos.appendingPathComponent("second.jpg")
        let thirdURL = photos.appendingPathComponent("third.jpg")
        try Data([1, 2, 3, 4]).write(to: firstURL)
        try Data([5, 6, 7, 8]).write(to: secondURL)
        try Data([9, 10, 11, 12]).write(to: thirdURL)
        let sourceBytes = try Dictionary(
            uniqueKeysWithValues: [
                firstURL,
                secondURL,
                thirdURL,
            ].map {
                ($0, try Data(contentsOf: $0))
            }
        )

        let catalogStore = CatalogStore(directory: stores)
        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: catalogStore
        )
        library.recursiveScan = false
        library.sort = .filename
        library.sortAscending = true
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        let ids = Dictionary(
            uniqueKeysWithValues:
                library.assets.map { ($0.filename, $0.id) }
        )
        let firstID = try XCTUnwrap(ids["first.jpg"])
        let secondID = try XCTUnwrap(ids["second.jpg"])
        let thirdID = try XCTUnwrap(ids["third.jpg"])

        let rootSet = try XCTUnwrap(
            library.createCollectionSet(named: "Portfolio")
        )
        let childSet = try XCTUnwrap(
            library.createCollectionSet(
                named: "2026",
                parentSetID: rootSet.id
            )
        )
        library.select(firstID)
        library.select(secondID, extending: true)
        let selects = try XCTUnwrap(
            library.createPhotoCollection(
                named: "Selects",
                parentSetID: childSet.id
            )
        )
        XCTAssertEqual(selects.photoCount, 2)
        XCTAssertTrue(
            library.isInPhotoCollection(
                firstID,
                collectionID: selects.id
            )
        )
        XCTAssertTrue(
            library.isInPhotoCollection(
                secondID,
                collectionID: selects.id
            )
        )
        XCTAssertTrue(
            library.setTargetPhotoCollection(selects)
        )
        library.select(thirdID)
        XCTAssertTrue(
            library.toggleTargetCollectionForSelection()
        )
        XCTAssertTrue(
            library.quickCollectionPhotoIDs.isEmpty
        )
        XCTAssertTrue(
            library.isInPhotoCollection(
                thirdID,
                collectionID: selects.id
            )
        )

        library.showPhotoCollection(
            try XCTUnwrap(
                library.photoCollections.first {
                    $0.id == selects.id
                }
            )
        )
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            library.assets.map(\.filename),
            ["first.jpg", "second.jpg", "third.jpg"]
        )
        XCTAssertTrue(
            library.movePhotoInActiveCollection(
                thirdID,
                .beginning
            )
        )
        XCTAssertEqual(
            library.assets.map(\.filename),
            ["third.jpg", "first.jpg", "second.jpg"]
        )

        library.select(firstID)
        library.select(secondID, extending: true)
        XCTAssertTrue(
            library.toggleTargetCollectionForSelection()
        )
        XCTAssertEqual(
            library.assets.map(\.filename),
            ["third.jpg"]
        )
        XCTAssertFalse(
            library.isInPhotoCollection(
                firstID,
                collectionID: selects.id
            )
        )
        XCTAssertFalse(
            library.isInPhotoCollection(
                secondID,
                collectionID: selects.id
            )
        )

        XCTAssertTrue(library.setTargetPhotoCollection(nil))
        library.showCatalog(.allPhotos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        library.select(firstID)
        XCTAssertTrue(
            library.toggleTargetCollectionForSelection()
        )
        XCTAssertEqual(
            library.quickCollectionPhotoIDs,
            [firstID]
        )
        let quickArchive = try XCTUnwrap(
            library.saveQuickCollection(
                named: "Quick Archive",
                parentSetID: childSet.id,
                clearAfterSaving: true
            )
        )
        XCTAssertEqual(quickArchive.photoCount, 1)
        XCTAssertTrue(
            library.quickCollectionPhotoIDs.isEmpty
        )
        XCTAssertTrue(
            library.isInPhotoCollection(
                firstID,
                collectionID: quickArchive.id
            )
        )

        let reopened = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        XCTAssertEqual(reopened.collectionSets.count, 2)
        XCTAssertEqual(reopened.photoCollections.count, 2)
        XCTAssertNil(reopened.targetPhotoCollection)
        let reopenedSelects = try XCTUnwrap(
            reopened.photoCollections.first {
                $0.id == selects.id
            }
        )
        reopened.showPhotoCollection(reopenedSelects)
        for _ in 0..<300 where reopened.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(
            reopened.assets.map(\.filename),
            ["third.jpg"]
        )

        reopened.deleteCollectionSet(
            try XCTUnwrap(
                reopened.collectionSets.first {
                    $0.id == rootSet.id
                }
            )
        )
        for _ in 0..<300 where reopened.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(reopened.collectionSets.isEmpty)
        XCTAssertTrue(reopened.photoCollections.isEmpty)
        XCTAssertEqual(
            reopened.catalogSummary[.allPhotos],
            3
        )
        for (url, bytes) in sourceBytes {
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        XCTAssertTrue(
            try CatalogStore(directory: stores).integrityCheck()
        )
    }

    @MainActor
    func testExactDuplicateCollectionScansGroupsAndVerifiesAgain()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-duplicates-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }

        let first = photos.appendingPathComponent("first.jpg")
        let second = photos.appendingPathComponent("second.jpg")
        let unique = photos.appendingPathComponent("unique.jpg")
        try Data([1, 2, 3, 4]).write(to: first)
        try Data([1, 2, 3, 4]).write(to: second)
        try Data([4, 3, 2, 1]).write(to: unique)

        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        library.recursiveScan = false
        library.open(folder: photos)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        library.showCatalog(.exactDuplicates)
        for _ in 0..<500 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(library.isScanning)
        XCTAssertNil(library.duplicateScanProgress)
        XCTAssertEqual(library.catalogCollection, .exactDuplicates)
        XCTAssertEqual(
            Set(library.assets.map(\.filename)),
            ["first.jpg", "second.jpg"]
        )
        XCTAssertEqual(library.exactDuplicateGroups.count, 1)
        XCTAssertEqual(library.duplicateScanResult?.candidateCount, 3)
        XCTAssertEqual(library.duplicateScanResult?.newlyHashedCount, 3)
        XCTAssertEqual(library.duplicateScanResult?.cachedHashCount, 0)
        XCTAssertEqual(library.catalogSummary[.exactDuplicates], 2)
        XCTAssertEqual(library.catalogSummary.exactDuplicateGroupCount, 1)
        XCTAssertEqual(library.catalogSummary.duplicateReclaimableBytes, 4)
        XCTAssertEqual(library.catalogSummary.hashedPhotoCount, 3)

        let groupNumbers = library.assets.compactMap {
            library.duplicateGroupNumber(for: $0.id)
        }
        XCTAssertEqual(groupNumbers, [1, 1])
        XCTAssertEqual(
            library.assets.filter {
                library.isDuplicateAnchor($0.id)
            }.count,
            1
        )
        XCTAssertTrue(library.assets.allSatisfy {
            library.duplicateContentHash(for: $0.id)?.count == 64
        })

        library.verifyExactDuplicatesAgain()
        for _ in 0..<500 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.duplicateScanResult?.newlyHashedCount, 3)
        XCTAssertEqual(library.duplicateScanResult?.cachedHashCount, 0)
        XCTAssertEqual(try Data(contentsOf: first), Data([1, 2, 3, 4]))
        XCTAssertEqual(try Data(contentsOf: second), Data([1, 2, 3, 4]))
        XCTAssertEqual(try Data(contentsOf: unique), Data([4, 3, 2, 1]))
    }

    @MainActor
    func testAssistedCullingCollectionReviewsOverridesAndAppliesBatchActions()
        async throws
    {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-culling-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }

        let selectURL = photos.appendingPathComponent("select.jpg")
        let rejectURL = photos.appendingPathComponent("reject.jpg")
        try Data([1, 2, 3, 4]).write(to: selectURL)
        try Data([5, 6, 7, 8]).write(to: rejectURL)

        let catalogStore = CatalogStore(directory: stores)
        let analyzer = AssistedCullingAnalyzer(
            catalogStore: catalogStore,
            analysisProvider: { asset in
                let shouldReject = asset.filename == "reject.jpg"
                return AssistedCullingAnalysis(
                    analyzedAt: Date(
                        timeIntervalSince1970: 1_700_000_000
                    ),
                    subjectDetected: true,
                    subjectSharpness: 0.9,
                    globalSharpness: 0.85,
                    eyeSharpness: 0.8,
                    eyeOpenness: 0.9,
                    eyeState: .open,
                    faces: [
                        AssistedCullingFaceAnalysis(
                            id: 1,
                            boundingBox: CGRect(
                                x: 0.2,
                                y: 0.2,
                                width: 0.4,
                                height: 0.5
                            ),
                            eyeSharpness: 0.8,
                            eyeOpenness: 0.9,
                            eyeState: .open
                        ),
                    ],
                    meanLuminance: shouldReject ? 0.02 : 0.5,
                    shadowClipping: shouldReject ? 0.9 : 0,
                    highlightClipping: 0,
                    exposureIssueScore: shouldReject ? 0.95 : 0.05,
                    misfireScore: 0.1,
                    documentScore: 0.05,
                    textObservationCount: 0,
                    largestRectangleCoverage: 0,
                    visualFingerprint: Array(
                        repeating: shouldReject ? 0.9 : 0.5,
                        count: 64
                    )
                )
            }
        )
        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: catalogStore,
            assistedCullingAnalyzer: analyzer
        )
        library.recursiveScan = false
        library.open(folder: photos)
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        library.showCatalog(.assistedCulling)
        for _ in 0..<500 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertFalse(library.isScanning)
        XCTAssertNil(library.cullingScanProgress)
        XCTAssertEqual(library.catalogCollection, .assistedCulling)
        XCTAssertEqual(library.assets.count, 2)
        XCTAssertEqual(library.cullingScanResult?.candidateCount, 2)
        XCTAssertEqual(library.cullingScanResult?.analyzedCount, 2)
        XCTAssertEqual(
            library.cullingScanResult?.counts(
                criteria: library.cullingCriteria
            )[.select],
            1
        )
        XCTAssertEqual(
            library.cullingScanResult?.counts(
                criteria: library.cullingCriteria
            )[.reject],
            1
        )
        XCTAssertTrue(
            library.cullingScanResult?.suggestedStacks.isEmpty == true
        )
        library.cullingCriteria.stackSimilarityThreshold = 0.5
        XCTAssertEqual(
            library.cullingScanResult?.suggestedStacks.count,
            1
        )
        XCTAssertTrue(try catalogStore.photoStacks().isEmpty)
        XCTAssertTrue(library.createSuggestedCullingStacks())
        XCTAssertEqual(library.photoStacks.count, 1)
        XCTAssertEqual(
            library.photoStacks.first?.topPhotoID,
            library.assets.first {
                $0.filename == "select.jpg"
            }?.id
        )
        XCTAssertTrue(
            library.cullingScanResult?.suggestedStacks.isEmpty == true
        )
        XCTAssertEqual(library.catalogSummary.photoStackCount, 1)
        XCTAssertEqual(library.catalogSummary.stackedPhotoCount, 2)
        XCTAssertEqual(
            try Data(contentsOf: selectURL),
            Data([1, 2, 3, 4])
        )
        XCTAssertEqual(
            try Data(contentsOf: rejectURL),
            Data([5, 6, 7, 8])
        )
        library.cullingCriteria.suggestAutoStacks = false
        XCTAssertTrue(
            library.cullingScanResult?.suggestedStacks.isEmpty == true
        )
        library.cullingCriteria = .default

        library.cullingReviewFilter = .selects
        XCTAssertEqual(
            library.filtered.map(\.filename),
            ["select.jpg"]
        )
        library.cullingReviewFilter = .all

        let rejectID = try XCTUnwrap(
            library.assets.first {
                $0.filename == "reject.jpg"
            }?.id
        )
        library.setCullingManualDecision(.select, for: rejectID)
        XCTAssertEqual(
            library.cullingDecision(for: rejectID),
            .select
        )
        library.setCullingManualDecision(nil, for: rejectID)
        XCTAssertEqual(
            library.cullingDecision(for: rejectID),
            .reject
        )

        library.applyCullingFlags()
        XCTAssertTrue(
            library.assets.first {
                $0.filename == "select.jpg"
            }?.userState.flagged == true
        )
        XCTAssertTrue(
            library.assets.first {
                $0.filename == "reject.jpg"
            }?.userState.rejected == true
        )

        library.applyCullingRatings(
            selectRating: 5,
            rejectRating: 1
        )
        XCTAssertEqual(
            library.assets.first {
                $0.filename == "select.jpg"
            }?.userState.rating,
            5
        )
        XCTAssertEqual(
            library.assets.first {
                $0.filename == "reject.jpg"
            }?.userState.rating,
            1
        )

        library.applyCullingColorLabels()
        XCTAssertEqual(
            library.assets.first {
                $0.filename == "select.jpg"
            }?.userState.colorLabel,
            .green
        )
        XCTAssertEqual(
            library.assets.first {
                $0.filename == "reject.jpg"
            }?.userState.colorLabel,
            .red
        )
        let persistedStates = try catalogStore.userStates()
        XCTAssertEqual(
            persistedStates[
                library.assets.first {
                    $0.filename == "select.jpg"
                }?.id ?? ""
            ]?.colorLabel,
            .green
        )
        XCTAssertEqual(
            persistedStates[rejectID]?.colorLabel,
            .red
        )

        library.verifyAssistedCullingAgain()
        for _ in 0..<500 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.cullingScanResult?.analyzedCount, 2)
        XCTAssertEqual(library.cullingScanResult?.cachedCount, 0)
        XCTAssertEqual(
            try Data(contentsOf: selectURL),
            Data([1, 2, 3, 4])
        )
        XCTAssertEqual(
            try Data(contentsOf: rejectURL),
            Data([5, 6, 7, 8])
        )

        let catalogStates = try catalogStore.userStates()
        XCTAssertEqual(
            catalogStates.values.first {
                $0.rating == 5
            }?.pickStatus,
            .picked
        )
        XCTAssertEqual(
            catalogStates.values.first {
                $0.rating == 1
            }?.pickStatus,
            .rejected
        )
    }

    @MainActor
    func testKeywordManagerUpdatesLiveViewSmartCollectionAndJSONMirror()
        async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-keyword-manager-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let photo = photos.appendingPathComponent("tokyo.jpg")
        try Data([0, 1, 2, 3]).write(to: photo)

        let userStateStore = UserStateStore(directory: stores)
        let catalogStore = CatalogStore(directory: stores)
        let library = LibraryViewModel(
            userStateStore: userStateStore,
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: catalogStore
        )
        library.recursiveScan = false
        library.open(folder: photos)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        let id = try XCTUnwrap(library.selectionID)
        library.setRating(5, for: id)
        library.addKeywords(
            ["Places > Japan > Tokyo", "Travel"],
            for: id
        )
        library.filter.keyword = "Places|Japan"
        let saved = try XCTUnwrap(
            library.saveCurrentFilterAsSmartCollection(
                named: "Japan photographs"
            )
        )
        library.showSavedSmartCollection(saved)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }

        let change = CatalogKeywordChange.rename(
            sourcePath: "Places|Japan",
            newName: "Nihon"
        )
        let preview = try await library.previewCatalogKeywordChange(
            change
        )
        XCTAssertEqual(preview.affectedPhotoCount, 1)
        XCTAssertEqual(preview.affectedSmartCollectionCount, 1)
        _ = try await library.applyCatalogKeywordChange(change)

        XCTAssertFalse(library.isManagingKeywords)
        XCTAssertEqual(library.filter.keyword, "Places|Nihon")
        XCTAssertEqual(
            library.activeSavedCollection?.filter.keyword,
            "Places|Nihon"
        )
        XCTAssertEqual(
            library.savedSmartCollections.first?.filter.keyword,
            "Places|Nihon"
        )
        XCTAssertEqual(library.filtered.map(\.filename), ["tokyo.jpg"])
        XCTAssertEqual(
            library.assets.first?.userState.keywords,
            ["Places|Nihon|Tokyo", "Travel"]
        )
        XCTAssertEqual(library.assets.first?.userState.rating, 5)
        XCTAssertEqual(
            UserStateStore(directory: stores).get(id: id).keywords,
            ["Places|Nihon|Tokyo", "Travel"]
        )
        XCTAssertEqual(
            try catalogStore.userStates()[id]?.keywords,
            ["Places|Nihon|Tokyo", "Travel"]
        )
        XCTAssertNil(
            XMPSidecarService.existingSidecarURL(for: photo)
        )
        XCTAssertTrue(try catalogStore.integrityCheck())
    }

    @MainActor
    func testMissingPhotoRelinkAndCatalogRemovalFlow() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-relink-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let relocated = base.appendingPathComponent(
            "relocated",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, relocated, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let original = photos.appendingPathComponent("hero.jpg")
        let replacement = relocated.appendingPathComponent("hero.jpg")
        try Data([0, 1, 2, 3]).write(to: original)

        let userStateStore = UserStateStore(directory: stores)
        let library = LibraryViewModel(
            userStateStore: userStateStore,
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        library.recursiveScan = false
        library.open(folder: photos)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        let originalID = try XCTUnwrap(library.selectionID)
        library.setRating(4, for: originalID)
        library.addKeywords(
            ["Places > Japan > Tokyo"],
            for: originalID
        )

        try FileManager.default.removeItem(at: original)
        library.showCatalog(.missingFiles)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.assets.count, 1)
        XCTAssertTrue(try XCTUnwrap(library.assets.first).catalogMissing)

        try Data([0, 1, 2, 3]).write(to: replacement)
        XCTAssertTrue(
            library.relinkMissingPhoto(
                originalID,
                to: replacement
            )
        )
        XCTAssertTrue(library.assets.isEmpty)
        XCTAssertEqual(library.catalogSummary[.missingFiles], 0)
        XCTAssertEqual(library.catalogSummary[.allPhotos], 1)

        library.showCatalog(.allPhotos)
        for _ in 0..<200 where library.isScanning {
            try await Task.sleep(for: .milliseconds(10))
        }
        let relinked = try XCTUnwrap(library.assets.first)
        XCTAssertEqual(relinked.path, replacement.path)
        XCTAssertEqual(relinked.userState.rating, 4)
        XCTAssertEqual(
            relinked.userState.keywords,
            ["Places|Japan|Tokyo"]
        )
        XCTAssertFalse(relinked.catalogMissing)

        XCTAssertTrue(library.removeFromCatalog(relinked.id))
        XCTAssertTrue(library.assets.isEmpty)
        XCTAssertEqual(library.catalogSummary[.allPhotos], 0)
        XCTAssertNil(userStateStore.loadAll()[relinked.id])
    }

    @MainActor
    func testImportWorkflowShowsLastImportAndUpdatesCatalog() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-import-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let photo = photos.appendingPathComponent("imported.jpg")
        try Data([8, 6, 7, 5, 3, 0, 9]).write(to: photo)

        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: CatalogStore(directory: stores)
        )
        let checked = try await library.preflightImport(
            PhotoImportRequest(
                sourceURLs: [photo],
                recursive: false
            )
        )
        XCTAssertEqual(checked.readyCount, 1)
        let result = try await library.executeImport(checked)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(library.displayTitle, "Last Import")
        XCTAssertEqual(library.assets.map(\.filename), ["imported.jpg"])
        XCTAssertEqual(library.selectedAsset?.path, photo.path)
        XCTAssertEqual(library.catalogSummary[.allPhotos], 1)
        XCTAssertNil(library.importProgress)
    }

    @MainActor
    func testManualImportPeopleOptionCreatesSuggestionsWithoutNames()
        async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-library-import-people-\(UUID().uuidString)",
                isDirectory: true
            )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: base) }
        let photo = photos.appendingPathComponent("portrait.jpg")
        try Data([4, 6, 2, 6, 4, 3]).write(to: photo)
        let sourceHash = try FileContentHasher.sha256(for: photo)

        let catalog = CatalogStore(directory: stores)
        let analyzer = PeopleAnalyzer(
            catalogStore: catalog
        ) { _ in
            [
                PeopleFaceDetection(
                    boundingBox: CGRect(
                        x: 0.15,
                        y: 0.2,
                        width: 0.35,
                        height: 0.45
                    ),
                    confidence: 0.96,
                    captureQuality: 0.88,
                    featurePrintData: Data([8, 8])
                ),
            ]
        }
        let library = LibraryViewModel(
            userStateStore: UserStateStore(directory: stores),
            recentStore: RecentFolderStore(directory: stores),
            catalogStore: catalog,
            peopleAnalyzer: analyzer
        )
        let checked = try await library.preflightImport(
            PhotoImportRequest(
                sourceURLs: [photo],
                recursive: false
            )
        )
        let result = try await library.executeImport(
            checked,
            analyzePeopleAfterImport: true
        )

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.peopleAnalyzedCount, 1)
        XCTAssertEqual(result.peopleCachedCount, 0)
        XCTAssertEqual(result.peopleFaceCount, 1)
        XCTAssertEqual(result.peopleUnavailableCount, 0)
        XCTAssertEqual(try catalog.catalogFaces().count, 1)
        XCTAssertEqual(try catalog.catalogPeople(), [])
        XCTAssertEqual(library.catalogSummary.faceCount, 1)
        XCTAssertNil(library.importProgress)
        XCTAssertNil(library.importPeopleProgress)
        XCTAssertEqual(
            try FileContentHasher.sha256(for: photo),
            sourceHash
        )
    }
}

final class XMPSidecarServiceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(
                "rawdesk-xmp-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    func testCanonicalSidecarNamingAndUppercaseDiscovery() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("IMG.0001.CR2")
        let uppercase = directory.appendingPathComponent("IMG.0001.XMP")
        try Data([0]).write(to: photo)
        try Data("<x/>".utf8).write(to: uppercase)

        XCTAssertEqual(
            XMPSidecarService.canonicalSidecarURL(for: photo)
                .lastPathComponent,
            "IMG.0001.xmp"
        )
        XCTAssertEqual(
            XMPSidecarService.existingSidecarURL(for: photo),
            uppercase
        )
    }

    func testColorLabelsRoundTripRespectExternalChangesAndClear()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("LABEL.DNG")
        let originalBytes = Data([9, 8, 7, 6])
        try originalBytes.write(to: photo)
        let adjustments = PhotoAdjustments(exposure: 0.5)
        let original = PhotoUserState(
            colorLabel: .green,
            adjustments: adjustments
        )

        let firstWrite = try XMPSidecarService.write(
            state: original,
            for: photo
        )
        var xml = try String(
            contentsOf: firstWrite.url,
            encoding: .utf8
        )
        XCTAssertTrue(xml.contains("xmp:Label=\"Green\""))

        xml = xml.replacingOccurrences(
            of: "xmp:Label=\"Green\"",
            with: "xmp:Label=\"Blue\""
        )
        try Data(xml.utf8).write(
            to: firstWrite.url,
            options: [.atomic]
        )
        let external = try XMPSidecarService.read(for: photo)
        XCTAssertEqual(external.state.colorLabel, .blue)
        XCTAssertEqual(
            external.state.adjustments.exposure,
            adjustments.exposure
        )

        let preserved = try XMPSidecarService.write(
            state: original,
            for: photo
        )
        XCTAssertEqual(preserved.stateWritten.colorLabel, .blue)
        XCTAssertTrue(
            try String(
                contentsOf: preserved.url,
                encoding: .utf8
            ).contains("xmp:Label=\"Blue\"")
        )

        let purple = try XMPSidecarService.write(
            state: PhotoUserState(
                colorLabel: .purple,
                adjustments: adjustments
            ),
            for: photo
        )
        XCTAssertEqual(purple.stateWritten.colorLabel, .purple)
        XCTAssertTrue(
            try String(
                contentsOf: purple.url,
                encoding: .utf8
            ).contains("xmp:Label=\"Purple\"")
        )

        let cleared = try XMPSidecarService.write(
            state: PhotoUserState(adjustments: adjustments),
            for: photo
        )
        XCTAssertEqual(cleared.stateWritten.colorLabel, .none)
        XCTAssertFalse(
            try String(
                contentsOf: cleared.url,
                encoding: .utf8
            ).contains("xmp:Label")
        )
        XCTAssertEqual(try Data(contentsOf: photo), originalBytes)
    }

    func testUnknownExternalColorLabelIsPreservedUntilUserSetsOne()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("CUSTOM.CR2")
        let sidecar = directory.appendingPathComponent("CUSTOM.xmp")
        let originalBytes = Data([4, 3, 2, 1])
        try originalBytes.write(to: photo)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmp:Label="Client Approved"/>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try Data(xml.utf8).write(to: sidecar)

        let imported = try XMPSidecarService.read(for: photo)
        XCTAssertEqual(imported.state.colorLabel, .none)
        XCTAssertEqual(
            imported.state.colorLabelMetadataValue,
            "Client Approved"
        )
        XCTAssertTrue(
            imported.warnings.contains {
                $0.contains("Client Approved")
            }
        )

        let clientSet = PhotoColorLabelSet(
            name: "Client",
            red: "Needs Work",
            yellow: "Maybe",
            green: "Client Approved",
            blue: "Portfolio",
            purple: "Archive"
        )
        let mapped = try XMPSidecarService.read(
            for: photo,
            colorLabelSet: clientSet
        )
        XCTAssertEqual(mapped.state.colorLabel, .green)
        XCTAssertEqual(
            mapped.state.colorLabelMetadataValue,
            "Client Approved"
        )

        let preserved = try XMPSidecarService.write(
            state: .empty,
            for: photo
        )
        XCTAssertTrue(preserved.preservedExistingPacket)
        XCTAssertEqual(preserved.stateWritten.colorLabel, .none)
        XCTAssertTrue(
            try String(
                contentsOf: sidecar,
                encoding: .utf8
            ).contains("xmp:Label=\"Client Approved\"")
        )

        _ = try XMPSidecarService.write(
            state: PhotoUserState(colorLabel: .red),
            for: photo
        )
        let updated = try String(
            contentsOf: sidecar,
            encoding: .utf8
        )
        XCTAssertTrue(updated.contains("xmp:Label=\"Red\""))
        XCTAssertFalse(updated.contains("Client Approved"))
        XCTAssertEqual(try Data(contentsOf: photo), originalBytes)
    }

    func testCustomColorLabelNameRoundTripsThroughXMP() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("WORKFLOW.ARW")
        let originalBytes = Data([7, 1, 7, 1])
        try originalBytes.write(to: photo)
        let set = PhotoColorLabelSet(
            name: "Editorial",
            red: "Needs Retouch",
            yellow: "Hold",
            green: "Publish",
            blue: "Portfolio Hero",
            purple: "Archive"
        )
        var state = PhotoUserState()
        state.assignColorLabel(
            .blue,
            metadataValue: set[.blue]
        )

        let written = try XMPSidecarService.write(
            state: state,
            for: photo,
            colorLabelSet: set
        )
        XCTAssertTrue(
            try String(
                contentsOf: written.url,
                encoding: .utf8
            ).contains("xmp:Label=\"Portfolio Hero\"")
        )

        let imported = try XMPSidecarService.read(
            for: photo,
            colorLabelSet: set
        )
        XCTAssertEqual(imported.state.colorLabel, .blue)
        XCTAssertEqual(
            imported.state.colorLabelMetadataValue,
            "Portfolio Hero"
        )
        XCTAssertTrue(imported.usedExactRAWDeskPayload)
        XCTAssertEqual(try Data(contentsOf: photo), originalBytes)
    }

    func testRAWDeskStateRoundTripsExactlyAlongsideAdobeFields() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("IMG_0001.CR2")
        try Data([0]).write(to: photo)

        let pointColor = PointColorAdjustment(
            sample: PointColorSample(
                hue: 182,
                saturation: 73,
                luminance: 42
            ),
            hueShift: 12,
            saturationShift: -8,
            luminanceShift: 4,
            variance: 6
        )
        let mask = LocalAdjustmentMask(
            name: "Window",
            kind: .radial,
            centerX: 0.42,
            centerY: 0.31,
            size: 0.28,
            feather: 0.64,
            pointColors: [pointColor],
            adjustments: LocalToneAdjustments(
                exposure: 0.75,
                temperature: 8,
                clarity: 12
            )
        )
        let adjustments = PhotoAdjustments(
            developmentProfile: DevelopmentProfileSettings(
                profile: .cinematicTeal,
                amount: 135
            ),
            exposure: 1.25,
            contrast: 18,
            highlights: -32,
            shadows: 27,
            whites: 11,
            blacks: -9,
            temperature: -24,
            tint: 16,
            vibrance: 22,
            saturation: -7,
            toneCurve: ToneCurve(
                black: 0.12,
                shadows: 0.29,
                midtones: 0.54,
                highlights: 0.81,
                white: 0.97
            ),
            colorMixer: ColorMixer(
                red: HSLChannelAdjustment(
                    hue: 8,
                    saturation: 14,
                    luminance: -3
                ),
                blue: HSLChannelAdjustment(
                    hue: -11,
                    saturation: 19,
                    luminance: 7
                )
            ),
            pointColors: [pointColor],
            colorGrading: ColorGrading(
                shadows: ColorGradingWheel(
                    hue: 205,
                    saturation: 18,
                    luminance: -4
                ),
                midtones: ColorGradingWheel(
                    hue: 36,
                    saturation: 9,
                    luminance: 3
                ),
                highlights: ColorGradingWheel(
                    hue: 48,
                    saturation: 15,
                    luminance: 6
                ),
                global: ColorGradingWheel(
                    hue: 12,
                    saturation: 4,
                    luminance: 1
                ),
                blending: 63,
                balance: -14
            ),
            calibration: CalibrationAdjustments(
                shadowsTint: 5,
                redPrimaryHue: 7,
                redPrimarySaturation: 9,
                greenPrimaryHue: -4,
                greenPrimarySaturation: 6,
                bluePrimaryHue: -8,
                bluePrimarySaturation: 13
            ),
            localMasks: [mask],
            spotRemovals: [
                SpotRemoval(
                    name: "Dust",
                    kind: .heal,
                    targetX: 0.2,
                    targetY: 0.3
                )
            ],
            texture: 17,
            clarity: 21,
            dehaze: 8,
            vignette: -12,
            grainAmount: 14,
            grainSize: 31,
            grainRoughness: 62,
            sharpening: 47,
            sharpeningRadius: 1.2,
            sharpeningDetail: 38,
            sharpeningMasking: 19,
            noiseReduction: 23,
            noiseReductionDetail: 56,
            noiseReductionContrast: 7,
            colorNoiseReduction: 29,
            colorNoiseDetail: 61,
            colorNoiseSmoothness: 54,
            optics: OpticsAdjustments(
                distortion: 4,
                vignette: 9,
                redCyanShift: -2,
                blueYellowShift: 3,
                purpleDefringe: 16,
                greenDefringe: 11
            ),
            geometry: GeometryAdjustments(
                vertical: 8,
                horizontal: -3,
                aspect: 2,
                scale: 106,
                offsetX: 4,
                offsetY: -5,
                constrainCrop: true
            ),
            straighten: 1.4,
            crop: NormalizedCrop(
                x: 0.1,
                y: 0.12,
                width: 0.72,
                height: 0.68
            )
        )
        let state = PhotoUserState(
            rating: 5,
            rejected: true,
            favorite: true,
            note: "Keep the highlights",
            keywords: ["Tokyo", "Architecture"],
            adjustments: adjustments,
            versions: [
                EditVersion(
                    name: "Warm alternate",
                    adjustments: PhotoAdjustments(temperature: 18)
                )
            ]
        )

        let writeResult = try XMPSidecarService.write(
            state: state,
            for: photo
        )
        XCTAssertTrue(writeResult.wroteExactRAWDeskPayload)
        XCTAssertFalse(writeResult.preservedExistingPacket)

        let xml = try String(contentsOf: writeResult.url, encoding: .utf8)
        XCTAssertTrue(xml.contains(XMPSidecarService.cameraRawNamespace))
        XCTAssertTrue(xml.contains("crs:Exposure2012=\"1.25\""))
        XCTAssertTrue(xml.contains("crs:ToneCurvePV2012"))
        XCTAssertTrue(xml.contains("xmp:Rating=\"5\""))
        XCTAssertTrue(xml.contains("crs:Pick=\"-1\""))
        XCTAssertTrue(xml.contains("rawdesk:State"))

        let imported = try XMPSidecarService.read(for: photo)
        XCTAssertTrue(imported.usedExactRAWDeskPayload)
        XCTAssertEqual(imported.state, state)
        XCTAssertTrue(imported.warnings.isEmpty)
    }

    func testReadsLightroomStyleAttributesAndToneCurveWithoutErasingLocalEdits() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("LIGHTROOM.NEF")
        let sidecar = directory.appendingPathComponent("LIGHTROOM.xmp")
        try Data([0]).write(to: photo)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:xmp="http://ns.adobe.com/xap/1.0/"
              xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
              xmp:Rating="4"
              crs:Pick="-1"
              crs:ProcessVersion="11.0"
              crs:WhiteBalance="Custom"
              crs:Temperature="5750"
              crs:Tint="30"
              crs:Exposure2012="+1.20"
              crs:Contrast2012="15"
              crs:Highlights2012="-35"
              crs:Shadows2012="24"
              crs:Whites2012="8"
              crs:Blacks2012="-6"
              crs:Vibrance="17"
              crs:HueAdjustmentGreen="+7"
              crs:SaturationAdjustmentBlue="-12"
              crs:HasCrop="True"
              crs:CropLeft="0.1"
              crs:CropTop="0.2"
              crs:CropRight="0.9"
              crs:CropBottom="0.8"
              crs:CropAngle="-1.5">
              <crs:ToneCurvePV2012>
                <rdf:Seq>
                  <rdf:li>0, 0</rdf:li>
                  <rdf:li>128, 140</rdf:li>
                  <rdf:li>255, 255</rdf:li>
                </rdf:Seq>
              </crs:ToneCurvePV2012>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try Data(xml.utf8).write(to: sidecar)

        let localMask = LocalAdjustmentMask(
            name: "Existing local edit",
            kind: .linear
        )
        let base = PhotoUserState(
            favorite: true,
            adjustments: PhotoAdjustments(localMasks: [localMask])
        )
        let result = try XMPSidecarService.read(
            from: sidecar,
            merging: base
        )

        XCTAssertEqual(result.state.rating, 4)
        XCTAssertEqual(result.state.pickStatus, .rejected)
        XCTAssertTrue(result.state.favorite)
        XCTAssertEqual(result.state.adjustments.exposure, 1.2)
        XCTAssertEqual(result.state.adjustments.contrast, 15)
        XCTAssertEqual(result.state.adjustments.highlights, -35)
        XCTAssertEqual(result.state.adjustments.temperature, -30)
        XCTAssertEqual(result.state.adjustments.tint, 20)
        XCTAssertEqual(
            result.state.adjustments.colorMixer.green.hue,
            7
        )
        XCTAssertEqual(
            result.state.adjustments.colorMixer.blue.saturation,
            -12
        )
        XCTAssertEqual(result.state.adjustments.crop.x, 0.1)
        XCTAssertEqual(result.state.adjustments.crop.y, 0.2)
        XCTAssertEqual(result.state.adjustments.crop.width, 0.8)
        XCTAssertEqual(
            result.state.adjustments.crop.height,
            0.6,
            accuracy: 0.000_1
        )
        XCTAssertEqual(result.state.adjustments.straighten, -1.5)
        XCTAssertEqual(
            result.state.adjustments.toneCurve.midtones,
            140.0 / 255,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            result.state.adjustments.localMasks,
            [localMask.normalized]
        )
    }

    func testWritingPreservesUnknownCopyrightKeywordsAndCustomProperties() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("PRESERVE.ARW")
        let sidecar = directory.appendingPathComponent("PRESERVE.xmp")
        try Data([0]).write(to: photo)

        let original = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:example="https://example.test/xmp/"
              example:Token="keep-me">
              <dc:rights>
                <rdf:Alt>
                  <rdf:li xml:lang="x-default">Copyright Example</rdf:li>
                </rdf:Alt>
              </dc:rights>
              <dc:subject>
                <rdf:Bag>
                  <rdf:li>travel</rdf:li>
                  <rdf:li>night</rdf:li>
                </rdf:Bag>
              </dc:subject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try Data(original.utf8).write(to: sidecar)

        let result = try XMPSidecarService.write(
            state: PhotoUserState(
                rating: 3,
                adjustments: PhotoAdjustments(exposure: 0.75)
            ),
            for: photo
        )
        XCTAssertTrue(result.preservedExistingPacket)
        XCTAssertEqual(result.url, sidecar)

        let updated = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(updated.contains("keep-me"))
        XCTAssertTrue(updated.contains("Copyright Example"))
        XCTAssertTrue(updated.contains("travel"))
        XCTAssertTrue(updated.contains("night"))
        XCTAssertTrue(updated.contains("crs:Exposure2012=\"0.75\""))
        XCTAssertEqual(result.stateWritten.keywords, ["travel", "night"])
    }

    func testReadsAndWritesDublinCoreKeywords() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("KEYWORDS.CR2")
        let sidecar = directory.appendingPathComponent("KEYWORDS.xmp")
        try Data([0]).write(to: photo)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:subject>
                <rdf:Bag>
                  <rdf:li>Tokyo</rdf:li>
                  <rdf:li>Night Street</rdf:li>
                </rdf:Bag>
              </dc:subject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try Data(xml.utf8).write(to: sidecar)

        let imported = try XMPSidecarService.read(
            from: sidecar,
            merging: .empty
        )
        XCTAssertEqual(imported.state.keywords, ["Tokyo", "Night Street"])

        let state = PhotoUserState(
            rating: 4,
            keywords: ["Tokyo", "Portrait"]
        )
        let result = try XMPSidecarService.write(
            state: state,
            for: photo
        )
        XCTAssertEqual(result.stateWritten, state)
        let updated = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(updated.contains("dc:subject"))
        XCTAssertTrue(updated.contains(">Tokyo<"))
        XCTAssertTrue(updated.contains(">Portrait<"))
        XCTAssertFalse(updated.contains(">Night Street<"))
        XCTAssertEqual(
            try XMPSidecarService.read(for: photo).state.keywords,
            ["Tokyo", "Portrait"]
        )
    }

    func testReadsAndWritesLightroomHierarchicalKeywords() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("HIERARCHY.CR2")
        let sidecar = directory.appendingPathComponent("HIERARCHY.xmp")
        try Data([0]).write(to: photo)
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description
              xmlns:dc="http://purl.org/dc/elements/1.1/"
              xmlns:lr="http://ns.adobe.com/lightroom/1.0/">
              <dc:subject>
                <rdf:Bag>
                  <rdf:li>Tokyo</rdf:li>
                  <rdf:li>Portrait</rdf:li>
                </rdf:Bag>
              </dc:subject>
              <lr:hierarchicalSubject>
                <rdf:Bag>
                  <rdf:li>Places|Japan|Tokyo</rdf:li>
                  <rdf:li>People|Portrait</rdf:li>
                </rdf:Bag>
              </lr:hierarchicalSubject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try Data(xml.utf8).write(to: sidecar)

        let imported = try XMPSidecarService.read(
            from: sidecar,
            merging: .empty
        )
        XCTAssertEqual(
            imported.state.keywords,
            ["Places|Japan|Tokyo", "People|Portrait"]
        )

        let state = PhotoUserState(
            keywords: [
                "Places > Japan > Kyoto",
                "People > Family",
            ]
        )
        let result = try XMPSidecarService.write(
            state: state,
            for: photo
        )
        XCTAssertEqual(result.stateWritten, state)
        let updated = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(updated.contains("lr:hierarchicalSubject"))
        XCTAssertTrue(updated.contains(">Places|Japan|Kyoto<"))
        XCTAssertTrue(updated.contains(">People|Family<"))
        XCTAssertTrue(updated.contains(">Kyoto<"))
        XCTAssertTrue(updated.contains(">Family<"))
        XCTAssertFalse(updated.contains(">Tokyo<"))
        XCTAssertEqual(
            try XMPSidecarService.read(for: photo).state.keywords,
            ["Places|Japan|Kyoto", "People|Family"]
        )
    }

    func testSavePreservesExternallyChangedKeywordsUntilExplicitlyEdited() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("EXTERNAL.DNG")
        try Data([0]).write(to: photo)
        let originalState = PhotoUserState(
            keywords: ["Tokyo"],
            adjustments: PhotoAdjustments(exposure: 0.5)
        )
        let firstWrite = try XMPSidecarService.write(
            state: originalState,
            for: photo
        )
        var xml = try String(
            contentsOf: firstWrite.url,
            encoding: .utf8
        )
        xml = xml.replacingOccurrences(
            of: ">Tokyo<",
            with: ">Shinjuku<"
        )
        try Data(xml.utf8).write(
            to: firstWrite.url,
            options: [.atomic]
        )

        let preserved = try XMPSidecarService.write(
            state: originalState,
            for: photo
        )
        XCTAssertEqual(preserved.stateWritten.keywords, ["Shinjuku"])
        let preservedXML = try String(
            contentsOf: firstWrite.url,
            encoding: .utf8
        )
        XCTAssertTrue(preservedXML.contains(">Shinjuku<"))
        XCTAssertFalse(preservedXML.contains(">Tokyo<"))

        let cleared = try XMPSidecarService.write(
            state: PhotoUserState(
                adjustments: originalState.adjustments
            ),
            for: photo
        )
        XCTAssertTrue(cleared.stateWritten.keywords.isEmpty)
        let clearedXML = try String(
            contentsOf: firstWrite.url,
            encoding: .utf8
        )
        XCTAssertFalse(clearedXML.contains("dc:subject"))
    }

    func testExternalSharedFieldChangeOverridesOnlyThatExactPayloadField() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("EDIT.DNG")
        try Data([0]).write(to: photo)

        let originalCurve = ToneCurve(
            black: 0.123_456,
            shadows: 0.287_654,
            midtones: 0.543_219,
            highlights: 0.812_345,
            white: 0.976_543
        )
        let state = PhotoUserState(
            adjustments: PhotoAdjustments(
                exposure: 1.2,
                toneCurve: originalCurve,
                localMasks: [
                    LocalAdjustmentMask(
                        name: "Preserved mask",
                        kind: .radial
                    )
                ]
            )
        )
        let writeResult = try XMPSidecarService.write(
            state: state,
            for: photo
        )
        var xml = try String(contentsOf: writeResult.url, encoding: .utf8)
        XCTAssertTrue(xml.contains("crs:Exposure2012=\"1.2\""))
        xml = xml.replacingOccurrences(
            of: "crs:Exposure2012=\"1.2\"",
            with: "crs:Exposure2012=\"2.4\""
        )
        try Data(xml.utf8).write(to: writeResult.url, options: [.atomic])

        let imported = try XMPSidecarService.read(for: photo)
        XCTAssertEqual(imported.state.adjustments.exposure, 2.4)
        XCTAssertEqual(imported.state.adjustments.toneCurve, originalCurve)
        XCTAssertEqual(
            imported.state.adjustments.localMasks,
            state.adjustments.localMasks
        )
    }

    func testMalformedExistingPacketIsNotOverwritten() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("BROKEN.CR2")
        let sidecar = directory.appendingPathComponent("BROKEN.xmp")
        try Data([0]).write(to: photo)
        let malformed = Data("<x:xmpmeta".utf8)
        try malformed.write(to: sidecar)

        XCTAssertThrowsError(
            try XMPSidecarService.write(
                state: PhotoUserState(rating: 2),
                for: photo
            )
        )
        XCTAssertEqual(try Data(contentsOf: sidecar), malformed)
    }

    func testScannerAutoImportsXMPOnlyWhenNoAppLocalStateExists() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("AUTO.JPG")
        try Data([0]).write(to: photo)
        try XMPSidecarService.write(
            state: PhotoUserState(
                rating: 5,
                rejected: true,
                adjustments: PhotoAdjustments(exposure: 1.5)
            ),
            for: photo
        )

        let scanner = PhotoLibraryScanner()
        let first = await scanner.scan(
            rootURL: directory,
            recursive: false,
            userStates: [:]
        )
        let imported = try XCTUnwrap(first.assets.first)
        XCTAssertTrue(imported.xmpImportedOnScan)
        XCTAssertEqual(imported.userState.rating, 5)
        XCTAssertTrue(imported.userState.rejected)
        XCTAssertEqual(imported.userState.adjustments.exposure, 1.5)

        let localState = PhotoUserState(
            rating: 1,
            flagged: true,
            adjustments: PhotoAdjustments(exposure: -0.5)
        )
        let second = await scanner.scan(
            rootURL: directory,
            recursive: false,
            userStates: [imported.id: localState]
        )
        let preferred = try XCTUnwrap(second.assets.first)
        XCTAssertFalse(preferred.xmpImportedOnScan)
        XCTAssertEqual(preferred.userState, localState)
        XCTAssertNotNil(preferred.xmpSidecarURL)
    }

    func testLegacyPickStateDefaultsToNotRejected() throws {
        let json = """
        {
          "rating": 3,
          "flagged": true,
          "favorite": false,
          "note": "",
          "versions": []
        }
        """
        let state = try JSONDecoder().decode(
            PhotoUserState.self,
            from: Data(json.utf8)
        )
        XCTAssertTrue(state.flagged)
        XCTAssertFalse(state.rejected)
        XCTAssertEqual(state.pickStatus, .picked)
    }

    func testExactPayloadRoundTripsManualAndRemovedLocation()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("LOCATION.CR2")
        try Data([0]).write(to: photo)
        let location = try XCTUnwrap(
            PhotoLocation(
                latitude: 48.85837,
                longitude: 2.294481,
                altitude: 81
            )
        )

        let manual = PhotoUserState(
            rating: 3,
            locationOverride: location
        )
        try XMPSidecarService.write(
            state: manual,
            for: photo
        )
        let standardXML = try String(
            contentsOf:
                XMPSidecarService.canonicalSidecarURL(
                    for: photo
                ),
            encoding: .utf8
        )
        XCTAssertTrue(
            standardXML.contains(
                "exif:GPSLatitude=\"48,"
            )
        )
        XCTAssertTrue(
            standardXML.contains(
                "exif:GPSLongitude=\"2,"
            )
        )
        XCTAssertTrue(
            standardXML.contains(
                "exif:GPSAltitude=\"81000/1000\""
            )
        )
        let restored = try XMPSidecarService.read(for: photo)
        XCTAssertTrue(restored.usedExactRAWDeskPayload)
        XCTAssertEqual(restored.state.locationOverride, location)
        XCTAssertFalse(restored.state.locationIsRemoved)

        var removed = restored.state
        removed.removeLocation()
        try XMPSidecarService.write(
            state: removed,
            for: photo
        )
        let restoredRemoval = try XMPSidecarService.read(
            for: photo
        )
        XCTAssertNil(restoredRemoval.state.locationOverride)
        XCTAssertTrue(restoredRemoval.state.locationIsRemoved)
        let removedXML = try String(
            contentsOf:
                XMPSidecarService.canonicalSidecarURL(
                    for: photo
                ),
            encoding: .utf8
        )
        XCTAssertFalse(
            removedXML.contains("exif:GPSLatitude")
        )
    }

    func testReadsAdobeEXIFNamespaceGPSWithoutRAWDeskPayload()
        throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("EXTERNAL.xmp")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
              xmlns:exif="http://ns.adobe.com/exif/1.0/"
              exif:GPSVersionID="2.3.0.0"
              exif:GPSLatitude="33,52.129200S"
              exif:GPSLongitude="151,12.557760E"
              exif:GPSAltitude="7250/1000"
              exif:GPSAltitudeRef="1"/>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try Data(xml.utf8).write(to: sidecar)
        let result = try XMPSidecarService.read(from: sidecar)
        let location = try XCTUnwrap(
            result.state.locationOverride
        )
        XCTAssertEqual(
            location.latitude,
            -33.86882,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            location.longitude,
            151.209296,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(location.altitude),
            -7.25,
            accuracy: 0.000_001
        )
    }
}

final class LightroomWorkspaceUITests: XCTestCase {
    func testResponsivePanelRangesProtectTheLibraryCanvas() {
        XCTAssertEqual(
            RAWDeskResponsiveLayout.guaranteedCenterWidth(
                for: 1_296
            ),
            724
        )
        XCTAssertGreaterThanOrEqual(
            RAWDeskResponsiveLayout.guaranteedCenterWidth(
                for: 1_296
            ),
            720
        )
        XCTAssertGreaterThanOrEqual(
            RAWDeskResponsiveLayout.guaranteedCenterWidth(
                for: 1_100
            ),
            RAWDeskResponsiveLayout.minimumCenterWidth(
                for: 1_100
            )
        )
        XCTAssertEqual(
            RAWDeskResponsiveLayout
                .inspectorWidthRange(for: 1_296),
            300...320
        )
    }

    func testPrimaryWorkspaceDestinationsHaveClearNames() {
        XCTAssertEqual(
            WorkspaceDestination.allCases.map(\.name),
            ["Library", "Develop", "People", "Map"]
        )
        XCTAssertEqual(
            PhotoWorkspaceMode.develop.systemImage,
            "slider.horizontal.3"
        )
    }

    func testWorkspaceSnapshotRoundTripsLocally()
        throws {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        .appendingPathComponent(
            "rawdesk-workspace-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let store = RecentFolderStore(
            directory: directory
        )
        let root = directory.appendingPathComponent(
            "Sony RAW",
            isDirectory: true
        )
        store.recordWorkspace(
            rootURL: root,
            selectionID: "sony-arw-fixture",
            photoWorkspace: .develop
        )

        XCTAssertEqual(
            store.workspaceSnapshot(),
            RecentFolderStore.WorkspaceSnapshot(
                rootPath: root.path,
                selectionID: "sony-arw-fixture",
                photoWorkspace: .develop
            )
        )
    }

    @MainActor
    func testRestoreWithoutRecentFolderLoadsPersistedCatalog()
        async throws
    {
        let base = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        .appendingPathComponent(
            "rawdesk-catalog-restore-\(UUID().uuidString)",
            isDirectory: true
        )
        let photos = base.appendingPathComponent(
            "photos",
            isDirectory: true
        )
        let stores = base.appendingPathComponent(
            "stores",
            isDirectory: true
        )
        for directory in [photos, stores] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        defer {
            try? FileManager.default.removeItem(at: base)
        }

        let photoURL = photos.appendingPathComponent(
            "persisted.jpg"
        )
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(
            to: photoURL
        )
        let asset = PhotoAsset(
            id: "persisted-import",
            url: photoURL,
            path: photoURL.path,
            filename: photoURL.lastPathComponent,
            fileExtension: "jpg",
            fileSize: 4,
            creationDate: nil,
            modificationDate: nil,
            format: .jpeg
        )
        let catalogStore = CatalogStore(directory: stores)
        try catalogStore.upsert(
            assets: [asset],
            rootURL: photos,
            recursive: false
        )

        let library = LibraryViewModel(
            userStateStore: UserStateStore(
                directory: stores
            ),
            recentStore: RecentFolderStore(
                directory: stores
            ),
            catalogStore: catalogStore
        )
        XCTAssertEqual(
            library.catalogSummary[.allPhotos],
            1
        )
        XCTAssertEqual(
            library.restoreLastWorkspaceIfAvailable(),
            .library
        )
        for _ in 0..<300 where library.isScanning {
            try await Task.sleep(
                for: .milliseconds(10)
            )
        }

        XCTAssertFalse(library.isScanning)
        XCTAssertEqual(library.catalogCollection, .allPhotos)
        XCTAssertEqual(
            library.assets.map(\.id),
            ["persisted-import"]
        )
    }

    @MainActor
    func testImportPresentationCarriesDroppedSourcesAndClearsOnDismiss()
        throws
    {
        let directory = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        .appendingPathComponent(
            "rawdesk-import-presentation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let catalogStore = CatalogStore(
            directory: directory
        )
        let library = LibraryViewModel(
            userStateStore: UserStateStore(
                directory: directory
            ),
            recentStore: RecentFolderStore(
                directory: directory
            ),
            colorLabelSetStore:
                PhotoColorLabelSetStore(
                    directory: directory
                ),
            autoImportSettingsStore:
                AutoImportSettingsStore(
                    directory: directory
                ),
            savedMapLocationStore:
                SavedMapLocationStore(
                    directory: directory
                ),
            catalogStore: catalogStore
        )
        let dropped = [
            directory.appendingPathComponent("one.ARW"),
            directory.appendingPathComponent("two.CR2"),
        ]

        library.presentImport(sourceURLs: dropped)

        XCTAssertTrue(library.isImportPresented)
        XCTAssertEqual(
            library.pendingImportSourceURLs,
            dropped
        )

        library.dismissImport()

        XCTAssertFalse(library.isImportPresented)
        XCTAssertTrue(
            library.pendingImportSourceURLs.isEmpty
        )
    }
}
