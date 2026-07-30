import Foundation

public struct EditVersion: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public let adjustments: PhotoAdjustments
    public let softProofSettings:
        SoftProofSettings?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        adjustments: PhotoAdjustments,
        softProofSettings:
            SoftProofSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.adjustments = adjustments.normalized
        self.softProofSettings =
            softProofSettings?.normalized
    }
}
