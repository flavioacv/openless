// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenLessMeetingRuntime",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenLessMeetings", type: .static, targets: ["OpenLessMeetings"]),
        .executable(name: "MeetingMediaProbe", targets: ["MeetingMediaProbe"]),
    ],
    dependencies: [
        .package(url: "https://github.com/altic-dev/FluidAudio.git", revision: "386f7195670b77f2954c7ee143ec63fcb50b6c3b"),
    ],
    targets: [
        .target(name: "FluidAEC3Bridge", dependencies: [],
                path: "vendor/webrtc-aec3/Sources/FluidAEC3Bridge", publicHeadersPath: "include"),
        .target(name: "OpenLessMeetings", dependencies: ["FluidAudio", "FluidAEC3Bridge"],
                path: "src/meetings", sources: ["media.swift", "models.swift", "inference.swift", "live.swift", "echo.swift",
                    "aec/MeetingAECModels.swift", "aec/MeetingAECStreamJoiner.swift", "aec/MeetingAECPCMAdapter.swift", "aec/MeetingAECProcessor.swift"]),
        .executableTarget(name: "MeetingMediaProbe", dependencies: ["OpenLessMeetings"],
                          path: "tests", sources: ["meeting_media_probe.swift"]),
        .testTarget(name: "MeetingNativeTests", dependencies: ["OpenLessMeetings"], path: "tests/native"),
    ],
    swiftLanguageModes: [.v5]
)
