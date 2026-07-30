// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RAWDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RAWDesk", targets: ["RAWDesk"])
    ],
    targets: [
        .executableTarget(
            name: "RAWDesk",
            path: "Sources/RAWDesk",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "RAWDeskTests",
            dependencies: ["RAWDesk"],
            path: "Tests/RAWDeskTests"
        )
    ]
)
