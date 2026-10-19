// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Legato",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LegatoCore", targets: ["LegatoCore"]),
        .executable(name: "Legato", targets: ["Legato"]),
        .executable(name: "legato-cli", targets: ["legato-cli"]),
    ],
    dependencies: [
        // Kana-kanji conversion. Code MIT, dictionary Apache-2.0. No Zenzai (neural) trait.
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", .upToNextMinor(from: "0.8.0")),
    ],
    targets: [
        .target(name: "LegatoCore", dependencies: [
            // The dictionary is shipped in Legato.app/Contents/Resources and passed by path
            // (see JapaneseConverter), not through an SPM resource bundle.
            .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
        ]),
        .executableTarget(name: "Legato", dependencies: ["LegatoCore"]),
        .executableTarget(name: "legato-cli", dependencies: ["LegatoCore"]),
        .testTarget(name: "LegatoCoreTests", dependencies: ["LegatoCore"]),
    ],
    swiftLanguageModes: [.v5]
)
