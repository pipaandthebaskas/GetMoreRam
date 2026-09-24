// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "StosSign",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "StosSign_API", targets: ["StosSign_API"]),
        .library(name: "StosSign_Auth", targets: ["StosSign_Auth"]),
        .library(name: "StosSign_Common", targets: ["StosSign_Common"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", exact: "1.10.0"),
        .package(url: "https://github.com/adam-fowler/swift-srp.git", revision: "ce202c48f8ca68f44b71732f945eb8221d6fe135")
    ],
    targets: [
        .target(name: "StosSign_Common"),
        .target(name: "StosSign_API", dependencies: ["StosSign_Common"]),
        .target(name: "StosSign_Auth", dependencies: ["StosSign_API", "StosSign_Common",
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "CryptoSwift", package: "CryptoSwift"),
            .product(name: "SRP", package: "swift-srp")]),
        .testTarget(name: "StosSignTests", dependencies: ["StosSign_API", "StosSign_Common"])
    ])
