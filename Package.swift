// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Seamtype",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SeamtypeCore", targets: ["SeamtypeCore"]),
        .executable(name: "Seamtype", targets: ["Seamtype"]),
        .executable(name: "seamtype-cli", targets: ["seamtype-cli"]),
    ],
    dependencies: [
        // Kana-kanji conversion. Code MIT, dictionary Apache-2.0. No Zenzai (neural) trait.
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", .upToNextMinor(from: "0.8.0")),
    ],
    targets: [
        .target(name: "SeamtypeCore", dependencies: [
            // The dictionary is shipped in Seamtype.app/Contents/Resources and passed by path
            // (see JapaneseConverter), not through an SPM resource bundle.
            .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
        ]),
        .executableTarget(name: "Seamtype", dependencies: ["SeamtypeCore"]),
        .executableTarget(name: "seamtype-cli", dependencies: ["SeamtypeCore"]),
        .testTarget(name: "SeamtypeCoreTests", dependencies: ["SeamtypeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
