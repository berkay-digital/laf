// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ParakeetServer",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "6f7938938f1580d1abee28dd980b5f79da5f794c")],
    targets: [
        .executableTarget(name: "parakeet-server", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")], path: "Sources/ParakeetServer"),
    ]
)
