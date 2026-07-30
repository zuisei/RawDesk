import Foundation

enum RAWDeskStorageDirectory {
    static let overrideEnvironmentKey =
        "RAWDESK_SUPPORT_DIRECTORY_OVERRIDE"

    static func resolve(_ explicitDirectory: URL?) -> URL {
        if let explicitDirectory {
            return explicitDirectory.standardizedFileURL
        }
        if let overridePath = ProcessInfo.processInfo.environment[
            overrideEnvironmentKey
        ]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            let directory = URL(
                fileURLWithPath: overridePath,
                isDirectory: true
            ).standardizedFileURL
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        }
        if isTestProcess() {
            let directory = URL(
                fileURLWithPath: NSTemporaryDirectory(),
                isDirectory: true
            )
            .appendingPathComponent(
                "RAWDesk-Tests-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
            .standardizedFileURL
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        }
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent(
            "RAWDesk",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func isTestProcess(
        processName: String =
            ProcessInfo.processInfo.processName,
        arguments: [String] =
            ProcessInfo.processInfo.arguments,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil {
            return true
        }
        let normalizedName = processName.lowercased()
        if normalizedName.contains("xctest")
            || normalizedName.hasSuffix("tests") {
            return true
        }
        return arguments.contains {
            let argument = $0.lowercased()
            return argument.contains(".xctest/")
                || argument.hasSuffix(".xctest")
        }
    }
}
