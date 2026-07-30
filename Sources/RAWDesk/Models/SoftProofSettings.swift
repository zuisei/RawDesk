import Foundation

public struct SoftProofProfile:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public enum BuiltIn:
        String,
        CaseIterable,
        Codable,
        Hashable,
        Sendable
    {
        case sRGB
        case displayP3
        case adobeRGB1998
        case genericCMYK
    }

    public enum ColorModel:
        String,
        Codable,
        Hashable,
        Sendable
    {
        case rgb
        case cmyk

        public var name: String {
            rawValue.uppercased()
        }
    }

    public struct ICCProfile:
        Codable,
        Equatable,
        Hashable,
        Sendable
    {
        public let fingerprint: String
        public let name: String
        public let url: URL
        public let colorModel: ColorModel
        public let profileClass: String

        public init(
            fingerprint: String,
            name: String,
            url: URL,
            colorModel: ColorModel,
            profileClass: String
        ) {
            self.fingerprint = fingerprint
            self.name = name
            self.url = url
            self.colorModel = colorModel
            self.profileClass = profileClass
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case icc
    }

    private enum Kind: String, Codable {
        case icc
    }

    private let builtInValue: BuiltIn?
    private let iccValue: ICCProfile?

    private init(
        builtIn: BuiltIn? = nil,
        icc: ICCProfile? = nil
    ) {
        builtInValue = builtIn
        iccValue = icc
    }

    public static let sRGB = SoftProofProfile(
        builtIn: .sRGB
    )
    public static let displayP3 = SoftProofProfile(
        builtIn: .displayP3
    )
    public static let adobeRGB1998 = SoftProofProfile(
        builtIn: .adobeRGB1998
    )
    public static let genericCMYK = SoftProofProfile(
        builtIn: .genericCMYK
    )
    public static let builtIns: [SoftProofProfile] =
        BuiltIn.allCases.map {
            SoftProofProfile(builtIn: $0)
        }

    public static func icc(
        _ profile: ICCProfile
    ) -> SoftProofProfile {
        SoftProofProfile(icc: profile)
    }

    public var id: String {
        if let builtInValue {
            return "builtin:\(builtInValue.rawValue)"
        }
        return "icc:\(iccValue?.fingerprint ?? "missing")"
    }

    public var builtIn: BuiltIn? {
        builtInValue
    }

    public var iccProfile: ICCProfile? {
        iccValue
    }

    public var name: String {
        if let iccValue {
            return iccValue.name
        }
        switch builtInValue {
        case .sRGB:
            return "sRGB IEC61966-2.1"
        case .displayP3:
            return "Display P3"
        case .adobeRGB1998:
            return "Adobe RGB (1998)"
        case .genericCMYK:
            return "Generic CMYK"
        case nil:
            return "Unavailable Profile"
        }
    }

    public var shortName: String {
        if let iccValue {
            guard iccValue.name.count > 18 else {
                return iccValue.name
            }
            return String(iccValue.name.prefix(17))
                + "…"
        }
        switch builtInValue {
        case .sRGB:
            return "sRGB"
        case .displayP3:
            return "P3"
        case .adobeRGB1998:
            return "Adobe RGB"
        case .genericCMYK:
            return "CMYK"
        case nil:
            return "Missing"
        }
    }

    public var systemImage: String {
        if let iccValue {
            if iccValue.profileClass == "prtr"
                || iccValue.colorModel == .cmyk {
                return "printer"
            }
            if iccValue.profileClass == "mntr" {
                return "display"
            }
            return "photo"
        }
        switch builtInValue {
        case .sRGB:
            return "globe"
        case .displayP3:
            return "display"
        case .adobeRGB1998:
            return "photo"
        case .genericCMYK:
            return "printer"
        case nil:
            return "questionmark.square.dashed"
        }
    }

    public var colorModel: ColorModel {
        if let iccValue {
            return iccValue.colorModel
        }
        return builtInValue == .genericCMYK
            ? .cmyk
            : .rgb
    }

    public var supportsPaperAndInk: Bool {
        builtInValue == .genericCMYK
            || iccValue?.profileClass == "prtr"
    }

    public var summary: String {
        if let iccValue {
            let role =
                iccValue.profileClass == "prtr"
                ? "Output"
                : iccValue.profileClass == "mntr"
                    ? "Display"
                    : "Color"
            return "\(role) ICC · \(iccValue.colorModel.name)"
        }
        return "Built-in · \(colorModel.name)"
    }

    public init(from decoder: Decoder) throws {
        if let rawValue = try? decoder
            .singleValueContainer()
            .decode(String.self),
           let builtIn = BuiltIn(rawValue: rawValue) {
            self.init(builtIn: builtIn)
            return
        }

        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        guard try container.decode(
            Kind.self,
            forKey: .kind
        ) == .icc else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription:
                    "Unsupported soft-proof profile kind."
            )
        }
        self.init(
            icc: try container.decode(
                ICCProfile.self,
                forKey: .icc
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        if let builtInValue {
            var container =
                encoder.singleValueContainer()
            try container.encode(builtInValue.rawValue)
            return
        }
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )
        try container.encode(
            Kind.icc,
            forKey: .kind
        )
        try container.encode(
            iccValue,
            forKey: .icc
        )
    }
}

public enum SoftProofRenderingIntent:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case perceptual
    case relativeColorimetric

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .perceptual:
            return "Perceptual"
        case .relativeColorimetric:
            return "Relative"
        }
    }
}

public struct SoftProofSettings:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case profile
        case renderingIntent
        case showDestinationGamutWarning
        case showMonitorGamutWarning
        case simulatePaperAndInk
    }

    public var isEnabled: Bool
    public var profile: SoftProofProfile
    public var renderingIntent:
        SoftProofRenderingIntent
    public var showDestinationGamutWarning: Bool
    public var showMonitorGamutWarning: Bool
    public var simulatePaperAndInk: Bool

    public init(
        isEnabled: Bool = false,
        profile: SoftProofProfile = .sRGB,
        renderingIntent:
            SoftProofRenderingIntent = .perceptual,
        showDestinationGamutWarning: Bool = false,
        showMonitorGamutWarning: Bool = false,
        simulatePaperAndInk: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.profile = profile
        self.renderingIntent = renderingIntent
        self.showDestinationGamutWarning =
            showDestinationGamutWarning
        self.showMonitorGamutWarning =
            showMonitorGamutWarning
        self.simulatePaperAndInk =
            simulatePaperAndInk
                && profile.supportsPaperAndInk
    }

    public static let disabled = SoftProofSettings()

    public var normalized: SoftProofSettings {
        SoftProofSettings(
            isEnabled: isEnabled,
            profile: profile,
            renderingIntent: renderingIntent,
            showDestinationGamutWarning:
                showDestinationGamutWarning,
            showMonitorGamutWarning:
                showMonitorGamutWarning,
            simulatePaperAndInk:
                simulatePaperAndInk
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        self.init(
            isEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .isEnabled
            ) ?? false,
            profile: try container.decodeIfPresent(
                SoftProofProfile.self,
                forKey: .profile
            ) ?? .sRGB,
            renderingIntent:
                try container.decodeIfPresent(
                    SoftProofRenderingIntent.self,
                    forKey: .renderingIntent
                ) ?? .perceptual,
            showDestinationGamutWarning:
                try container.decodeIfPresent(
                    Bool.self,
                    forKey:
                        .showDestinationGamutWarning
                ) ?? false,
            showMonitorGamutWarning:
                try container.decodeIfPresent(
                    Bool.self,
                    forKey:
                        .showMonitorGamutWarning
                ) ?? false,
            simulatePaperAndInk:
                try container.decodeIfPresent(
                    Bool.self,
                    forKey: .simulatePaperAndInk
                ) ?? false
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(
            keyedBy: CodingKeys.self
        )
        try container.encode(
            isEnabled,
            forKey: .isEnabled
        )
        try container.encode(
            profile,
            forKey: .profile
        )
        try container.encode(
            renderingIntent,
            forKey: .renderingIntent
        )
        try container.encode(
            showDestinationGamutWarning,
            forKey:
                .showDestinationGamutWarning
        )
        try container.encode(
            showMonitorGamutWarning,
            forKey: .showMonitorGamutWarning
        )
        try container.encode(
            simulatePaperAndInk,
            forKey: .simulatePaperAndInk
        )
    }
}
