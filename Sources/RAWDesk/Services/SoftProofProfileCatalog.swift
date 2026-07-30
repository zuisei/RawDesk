import Foundation
import CoreGraphics
import ColorSync
import CryptoKit

public enum SoftProofProfileCatalog {
    public enum CatalogError:
        Error,
        LocalizedError
    {
        case unreadable
        case tooLarge
        case invalidICC
        case unsupportedColorModel
        case unsupportedDestination
        case fingerprintMismatch
        case storageUnavailable

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                return "The ICC profile could not be read."
            case .tooLarge:
                return "The ICC profile is unexpectedly large."
            case .invalidICC:
                return "The file is not a valid ICC profile."
            case .unsupportedColorModel:
                return "RAWDesk supports RGB and CMYK proof profiles."
            case .unsupportedDestination:
                return "This ICC profile cannot be used as an output destination."
            case .fingerprintMismatch:
                return "The ICC profile has changed since it was selected."
            case .storageUnavailable:
                return "RAWDesk could not create its Proof Profiles folder."
            }
        }
    }

    private final class Cache:
        @unchecked Sendable
    {
        let lock = NSLock()
        var installed:
            [SoftProofProfile]?
    }

    private static let cache = Cache()
    private static let maximumProfileBytes =
        32 * 1024 * 1024

    public static func installedProfiles(
        refresh: Bool = false
    ) -> [SoftProofProfile] {
        cache.lock.lock()
        if !refresh, let installed = cache.installed {
            cache.lock.unlock()
            return installed
        }
        cache.lock.unlock()

        let infoBox = NSMutableArray()
        var seed: UInt32 = 0
        var iterationError:
            Unmanaged<CFError>?
        let waitKey =
            kColorSyncWaitForCacheReply
                .takeUnretainedValue()
        let options = [
            waitKey: kCFBooleanTrue!
        ] as CFDictionary
        ColorSyncIterateInstalledProfilesWithOptions(
            { profileInfo, userInfo in
                guard let profileInfo,
                      let userInfo else {
                    return true
                }
                Unmanaged<NSMutableArray>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                    .add(profileInfo)
                return true
            },
            &seed,
            Unmanaged
                .passUnretained(infoBox)
                .toOpaque(),
            options,
            &iterationError
        )
        if let iterationError {
            _ = iterationError.takeRetainedValue()
        }

        let descriptionKey =
            kColorSyncProfileDescription
                .takeUnretainedValue()
        let urlKey =
            kColorSyncProfileURL
                .takeUnretainedValue()
        let classKey =
            kColorSyncProfileClass
                .takeUnretainedValue()
        var unique:
            [String: SoftProofProfile] = [:]

        for case let info as NSDictionary in infoBox {
            guard let url = info[urlKey] as? URL else {
                continue
            }
            let name =
                info[descriptionKey] as? String
            let profileClass =
                info[classKey] as? String
            guard let profile = try? profile(
                at: url,
                preferredName: name,
                preferredClass: profileClass
            ), let fingerprint =
                profile.iccProfile?.fingerprint else {
                continue
            }
            if unique[fingerprint] == nil {
                unique[fingerprint] = profile
            }
        }

        let installed = unique.values.sorted {
            if $0.colorModel != $1.colorModel {
                return $0.colorModel.rawValue
                    < $1.colorModel.rawValue
            }
            return $0.name.localizedStandardCompare(
                $1.name
            ) == .orderedAscending
        }
        cache.lock.lock()
        cache.installed = installed
        cache.lock.unlock()
        return installed
    }

    public static func profile(
        at url: URL
    ) throws -> SoftProofProfile {
        try profile(
            at: url,
            preferredName: nil,
            preferredClass: nil
        )
    }

    public static func importProfile(
        at sourceURL: URL,
        directory: URL? = nil
    ) throws -> SoftProofProfile {
        let accessed =
            sourceURL
                .startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceURL
                    .stopAccessingSecurityScopedResource()
            }
        }

        let source = try profile(at: sourceURL)
        guard let sourceICC = source.iccProfile else {
            throw CatalogError.invalidICC
        }
        let targetDirectory: URL
        if let directory {
            targetDirectory = directory
        } else {
            targetDirectory =
                RAWDeskStorageDirectory
                .resolve(nil)
                .appendingPathComponent(
                    "Proof Profiles",
                    isDirectory: true
                )
        }
        do {
            try FileManager.default.createDirectory(
                at: targetDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw CatalogError.storageUnavailable
        }

        let destination = targetDirectory
            .appendingPathComponent(
                "\(sourceICC.fingerprint).icc"
            )
        if FileManager.default.fileExists(
            atPath: destination.path
        ) {
            let existing = try profile(
                at: destination,
                preferredName: sourceICC.name,
                preferredClass:
                    sourceICC.profileClass
            )
            guard existing.iccProfile?.fingerprint
                    == sourceICC.fingerprint else {
                throw CatalogError.fingerprintMismatch
            }
            return existing
        }
        do {
            try FileManager.default.copyItem(
                at: sourceURL,
                to: destination
            )
        } catch {
            throw CatalogError.storageUnavailable
        }
        return try profile(
            at: destination,
            preferredName: sourceICC.name,
            preferredClass: sourceICC.profileClass
        )
    }

    public static func colorSpace(
        for profile: SoftProofProfile
    ) throws -> CGColorSpace {
        if let builtIn = profile.builtIn {
            let colorSpace: CGColorSpace?
            switch builtIn {
            case .sRGB:
                colorSpace = CGColorSpace(
                    name: CGColorSpace.sRGB
                )
            case .displayP3:
                colorSpace = CGColorSpace(
                    name: CGColorSpace.displayP3
                )
            case .adobeRGB1998:
                colorSpace = CGColorSpace(
                    name: CGColorSpace.adobeRGB1998
                )
            case .genericCMYK:
                colorSpace = CGColorSpace(
                    name: CGColorSpace.genericCMYK
                )
            }
            guard let colorSpace else {
                throw CatalogError.invalidICC
            }
            return colorSpace
        }

        guard let icc = profile.iccProfile else {
            throw CatalogError.invalidICC
        }
        do {
            let data = try validatedData(
                at: icc.url,
                fingerprint: icc.fingerprint
            )
            guard let colorSpace = CGColorSpace(
                iccData: data as CFData
            ) else {
                throw CatalogError.invalidICC
            }
            return colorSpace
        } catch CatalogError.unreadable {
            // An installed profile may move while retaining the same
            // fingerprint, so look it up in the current ColorSync catalog.
        } catch {
            throw error
        }
        if let relocated = installedProfiles()
            .first(where: {
                $0.iccProfile?.fingerprint
                    == icc.fingerprint
            }),
           let relocatedICC =
            relocated.iccProfile {
            let data = try validatedData(
                at: relocatedICC.url,
                fingerprint: icc.fingerprint
            )
            guard let colorSpace = CGColorSpace(
                iccData: data as CFData
            ) else {
                throw CatalogError.invalidICC
            }
            return colorSpace
        }
        throw CatalogError.unreadable
    }

    private static func profile(
        at url: URL,
        preferredName: String?,
        preferredClass: String?
    ) throws -> SoftProofProfile {
        let data: Data
        do {
            data = try Data(
                contentsOf: url,
                options: .mappedIfSafe
            )
        } catch {
            throw CatalogError.unreadable
        }
        guard data.count <= maximumProfileBytes else {
            throw CatalogError.tooLarge
        }
        guard data.count >= 128,
              let colorSpace = CGColorSpace(
                iccData: data as CFData
              ) else {
            throw CatalogError.invalidICC
        }
        guard colorSpace.supportsOutput else {
            throw CatalogError
                .unsupportedDestination
        }
        let colorModel:
            SoftProofProfile.ColorModel
        switch colorSpace.model {
        case .rgb:
            colorModel = .rgb
        case .cmyk:
            colorModel = .cmyk
        default:
            throw CatalogError
                .unsupportedColorModel
        }

        let rawName = preferredName?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let name =
            rawName?.isEmpty == false
            ? rawName!
            : url
                .deletingPathExtension()
                .lastPathComponent
        let profileClass =
            preferredClass?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .nilIfEmpty
            ?? signature(
                in: data,
                range: 12..<16
            )
            ?? "spac"
        let fingerprint = SHA256
            .hash(data: data)
            .map {
                String(format: "%02x", $0)
            }
            .joined()
        return .icc(
            SoftProofProfile.ICCProfile(
                fingerprint: fingerprint,
                name: name,
                url: url,
                colorModel: colorModel,
                profileClass: profileClass
            )
        )
    }

    private static func validatedData(
        at url: URL,
        fingerprint: String
    ) throws -> Data {
        let data: Data
        do {
            data = try Data(
                contentsOf: url,
                options: .mappedIfSafe
            )
        } catch {
            throw CatalogError.unreadable
        }
        guard data.count <= maximumProfileBytes else {
            throw CatalogError.tooLarge
        }
        let digest = SHA256
            .hash(data: data)
            .map {
                String(format: "%02x", $0)
            }
            .joined()
        guard digest == fingerprint else {
            throw CatalogError
                .fingerprintMismatch
        }
        return data
    }

    private static func signature(
        in data: Data,
        range: Range<Int>
    ) -> String? {
        guard data.count >= range.upperBound else {
            return nil
        }
        return String(
            bytes: data[range],
            encoding: .ascii
        )?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
