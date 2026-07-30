import Foundation

public struct PhotoAsset: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: URL
    public let path: String
    public let filename: String
    public let fileExtension: String
    public let fileSize: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
    public let format: FileFormat
    public let catalogMissing: Bool

    public var loadState: ImageLoadState
    public var rawDecodeSource:
        RAWImageLoader.DecodeSource?
    public var metadata: PhotoMetadata?
    public var userState: PhotoUserState
    public var xmpSidecarURL: URL?
    public var xmpImportedOnScan: Bool

    public var isRaw: Bool { format.isRaw }
    public var isSonyARW: Bool { format == .sonyARW }
    public var isCanonCR2: Bool { format == .canonCR2 }
    public var effectiveLocation: PhotoLocation? {
        userState.effectiveLocation(
            embedded: metadata?.location
        )
    }
    public var locationSource: PhotoLocationSource {
        userState.locationSource(
            embedded: metadata?.location
        )
    }

    public init(
        id: String,
        url: URL,
        path: String,
        filename: String,
        fileExtension: String,
        fileSize: Int64,
        creationDate: Date?,
        modificationDate: Date?,
        format: FileFormat,
        catalogMissing: Bool = false,
        loadState: ImageLoadState = .idle,
        rawDecodeSource:
            RAWImageLoader.DecodeSource? = nil,
        metadata: PhotoMetadata? = nil,
        userState: PhotoUserState = .empty,
        xmpSidecarURL: URL? = nil,
        xmpImportedOnScan: Bool = false
    ) {
        self.id = id
        self.url = url
        self.path = path
        self.filename = filename
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.format = format
        self.catalogMissing = catalogMissing
        self.loadState = loadState
        self.rawDecodeSource = rawDecodeSource
        self.metadata = metadata
        self.userState = userState
        self.xmpSidecarURL = xmpSidecarURL
        self.xmpImportedOnScan = xmpImportedOnScan
    }

}
