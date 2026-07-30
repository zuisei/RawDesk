import Foundation

public struct PhotoMetadata: Codable, Equatable, Sendable {
    public var readerVersion: Int?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var iso: Int?
    public var shutterSpeed: Double?
    public var aperture: Double?
    public var focalLength: Double?
    public var captureDate: Date?
    public var exposureBias: Double?
    public var colorProfile: String?
    public var location: PhotoLocation?
    public var error: String?

    public init(
        readerVersion: Int? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        iso: Int? = nil,
        shutterSpeed: Double? = nil,
        aperture: Double? = nil,
        focalLength: Double? = nil,
        captureDate: Date? = nil,
        exposureBias: Double? = nil,
        colorProfile: String? = nil,
        location: PhotoLocation? = nil,
        error: String? = nil
    ) {
        self.readerVersion = readerVersion
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.aperture = aperture
        self.focalLength = focalLength
        self.captureDate = captureDate
        self.exposureBias = exposureBias
        self.colorProfile = colorProfile
        self.location = location
        self.error = error
    }
}
