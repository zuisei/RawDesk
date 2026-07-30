import Foundation

public enum PhotoImportTemplateKind: Sendable {
    case filename
    case folder
}

public enum PhotoImportTemplateError:
    LocalizedError, Equatable, Sendable {
    case empty
    case tooLong
    case unmatchedOpeningBrace
    case unmatchedClosingBrace
    case unsupportedToken(String)
    case invalidSequenceFormat(String)
    case invalidDateFormat(String)
    case filenameContainsFolderSeparator
    case emptyFolderComponent
    case unsafeFolderComponent(String)
    case tooManyFolderLevels

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "The template cannot be empty."
        case .tooLong:
            return "A template can contain at most 512 characters."
        case .unmatchedOpeningBrace:
            return "The template contains an opening brace without a matching closing brace."
        case .unmatchedClosingBrace:
            return "The template contains a closing brace without a matching opening brace."
        case let .unsupportedToken(token):
            return "The template token {\(token)} is not supported."
        case let .invalidSequenceFormat(format):
            return "Sequence format \(format) must contain 1–9 zeros, such as 0000."
        case let .invalidDateFormat(format):
            return "Date format \(format) is not supported. Use date letters such as yyyyMMdd or yyyy-MM-dd."
        case .filenameContainsFolderSeparator:
            return "A filename template cannot contain /. Use a folder template to create subfolders."
        case .emptyFolderComponent:
            return "A folder template cannot start or end with / or contain an empty folder level."
        case let .unsafeFolderComponent(component):
            return "The folder component \(component) is unsafe."
        case .tooManyFolderLevels:
            return "A folder template can create at most eight levels."
        }
    }
}

public struct PhotoImportTemplateContext: Equatable, Sendable {
    public var sourceURL: URL
    public var captureDate: Date?
    public var fallbackDate: Date?
    public var cameraMake: String?
    public var cameraModel: String?
    public var sequence: Int

    public init(
        sourceURL: URL,
        captureDate: Date? = nil,
        fallbackDate: Date? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        sequence: Int = 1
    ) {
        self.sourceURL = sourceURL.standardizedFileURL
        self.captureDate = captureDate
        self.fallbackDate = fallbackDate
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.sequence = max(1, sequence)
    }
}

public enum PhotoImportTemplateRenderer {
    public static let defaultFilenameTemplate =
        "{date:yyyyMMdd}-{original}-{sequence:0000}"
    public static let defaultFolderTemplate =
        "{date:yyyy}/{date:yyyy-MM-dd}"

    public static let filenameTokenExamples = [
        "{original}",
        "{date:yyyyMMdd}",
        "{date:HHmmss}",
        "{camera}",
        "{make}",
        "{folder}",
        "{sequence:0000}",
    ]

    public static let folderTokenExamples = [
        "{date:yyyy}",
        "{date:yyyy-MM-dd}",
        "{camera}",
        "{make}",
        "{folder}",
        "{sequence:0000}",
    ]

    public static func validate(
        _ template: String,
        kind: PhotoImportTemplateKind
    ) throws {
        let context = PhotoImportTemplateContext(
            sourceURL: URL(
                fileURLWithPath:
                    "/Pictures/Studio/IMG_0001.CR2"
            ),
            captureDate: Date(timeIntervalSince1970: 1_767_268_800),
            fallbackDate: Date(timeIntervalSince1970: 1_767_268_800),
            cameraMake: "Canon",
            cameraModel: "EOS R5",
            sequence: 12
        )
        switch kind {
        case .filename:
            _ = try renderFilenameBase(
                template,
                context: context
            )
        case .folder:
            _ = try renderFolderComponents(
                template,
                context: context
            )
        }
    }

    public static func renderFilenameBase(
        _ template: String,
        context: PhotoImportTemplateContext
    ) throws -> String {
        guard !template.contains("/") else {
            throw PhotoImportTemplateError
                .filenameContainsFolderSeparator
        }
        let rendered = try render(
            template,
            context: context
        )
        return try safeComponent(rendered)
    }

    public static func renderFolderComponents(
        _ template: String,
        context: PhotoImportTemplateContext
    ) throws -> [String] {
        guard template.count <= 512 else {
            throw PhotoImportTemplateError.tooLong
        }
        guard !template.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PhotoImportTemplateError.empty
        }
        let rawComponents = template.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard rawComponents.count <= 8 else {
            throw PhotoImportTemplateError.tooManyFolderLevels
        }
        guard rawComponents.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }) else {
            throw PhotoImportTemplateError.emptyFolderComponent
        }
        return try rawComponents.map { rawComponent in
            let literal = String(rawComponent)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard literal != ".", literal != ".." else {
                throw PhotoImportTemplateError
                    .unsafeFolderComponent(literal)
            }
            let rendered = try render(
                literal,
                context: context
            )
            let component = try safeComponent(rendered)
            guard component != ".", component != ".." else {
                throw PhotoImportTemplateError
                    .unsafeFolderComponent(component)
            }
            return component
        }
    }

    private static func render(
        _ template: String,
        context: PhotoImportTemplateContext
    ) throws -> String {
        guard template.count <= 512 else {
            throw PhotoImportTemplateError.tooLong
        }
        guard !template.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw PhotoImportTemplateError.empty
        }

        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            if character == "{" {
                let next = template.index(after: index)
                if next < template.endIndex,
                   template[next] == "{" {
                    result.append("{")
                    index = template.index(after: next)
                    continue
                }
                guard let closing = template[
                    next..<template.endIndex
                ].firstIndex(of: "}") else {
                    throw PhotoImportTemplateError
                        .unmatchedOpeningBrace
                }
                let token = String(template[next..<closing])
                guard !token.contains("{") else {
                    throw PhotoImportTemplateError
                        .unmatchedOpeningBrace
                }
                result += try value(
                    for: token,
                    context: context
                )
                index = template.index(after: closing)
            } else if character == "}" {
                let next = template.index(after: index)
                if next < template.endIndex,
                   template[next] == "}" {
                    result.append("}")
                    index = template.index(after: next)
                    continue
                }
                throw PhotoImportTemplateError
                    .unmatchedClosingBrace
            } else {
                result.append(character)
                index = template.index(after: index)
            }
        }
        return result
    }

    private static func value(
        for rawToken: String,
        context: PhotoImportTemplateContext
    ) throws -> String {
        let token = rawToken.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        switch token {
        case "original":
            return safeTokenValue(
                context.sourceURL
                    .deletingPathExtension()
                    .lastPathComponent,
                fallback: "Photo"
            )
        case "camera":
            return safeTokenValue(
                context.cameraModel,
                fallback: "Unknown Camera"
            )
        case "make":
            return safeTokenValue(
                context.cameraMake,
                fallback: "Unknown Make"
            )
        case "folder":
            return safeTokenValue(
                context.sourceURL
                    .deletingLastPathComponent()
                    .lastPathComponent,
                fallback: "Imported"
            )
        case "sequence":
            return String(
                format: "%04d",
                context.sequence
            )
        case "date":
            return dateValue(
                format: "yyyy-MM-dd",
                context: context
            )
        case "time":
            return dateValue(
                format: "HHmmss",
                context: context
            )
        default:
            if token.hasPrefix("sequence:") {
                let format = String(
                    token.dropFirst("sequence:".count)
                )
                guard (1...9).contains(format.count),
                      format.allSatisfy({ $0 == "0" }) else {
                    throw PhotoImportTemplateError
                        .invalidSequenceFormat(format)
                }
                return String(
                    format: "%0\(format.count)d",
                    context.sequence
                )
            }
            if token.hasPrefix("date:") {
                let format = String(
                    token.dropFirst("date:".count)
                )
                return try formattedDateValue(
                    format: format,
                    context: context
                )
            }
            throw PhotoImportTemplateError
                .unsupportedToken(token)
        }
    }

    private static func formattedDateValue(
        format: String,
        context: PhotoImportTemplateContext
    ) throws -> String {
        guard !format.isEmpty,
              format.count <= 32,
              format.allSatisfy({
                  "yMdHhmsS_-.".contains($0)
              }) else {
            throw PhotoImportTemplateError
                .invalidDateFormat(format)
        }
        return dateValue(
            format: format,
            context: context
        )
    }

    private static func dateValue(
        format: String,
        context: PhotoImportTemplateContext
    ) -> String {
        guard let date = context.captureDate
                ?? context.fallbackDate else {
            return "Unknown Date"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone =
            TimeZone(secondsFromGMT: 0) ?? .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func safeTokenValue(
        _ rawValue: String?,
        fallback: String
    ) -> String {
        let value = rawValue?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return sanitized(value?.isEmpty == false ? value! : fallback)
    }

    private static func safeComponent(
        _ rawValue: String
    ) throws -> String {
        let value = sanitized(rawValue)
            .trimmingCharacters(
                in: CharacterSet(charactersIn: ". ")
            )
        guard !value.isEmpty else {
            throw PhotoImportTemplateError.empty
        }
        return truncated(value, maximumUTF8Bytes: 180)
    }

    private static func sanitized(_ rawValue: String) -> String {
        let replaced = String(rawValue.map { character in
            if character == "/"
                || character == ":"
                || character == "\\"
                || character.unicodeScalars.contains(
                    where: CharacterSet.controlCharacters.contains
                ) {
                return "-"
            }
            return character
        })
        return replaced
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func truncated(
        _ value: String,
        maximumUTF8Bytes: Int
    ) -> String {
        var result = ""
        var byteCount = 0
        for character in value {
            let bytes = String(character).utf8.count
            guard byteCount + bytes <= maximumUTF8Bytes else {
                break
            }
            result.append(character)
            byteCount += bytes
        }
        return result
    }
}
