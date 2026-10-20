// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "Araso",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ArasoCore", targets: ["ArasoCore"]),
        .executable(name: "Araso", targets: ["Araso"]),
        .executable(name: "araso-cli", targets: ["araso-cli"]),
    ],
    dependencies: [
        // Kana-kanji conversion. Code MIT, dictionary Apache-2.0. No Zenzai (neural) trait.
        .package(url: "https://github.com/azooKey/AzooKeyKanaKanjiConverter", .upToNextMinor(from: "0.8.0")),
    ],
    targets: [
        .target(name: "ArasoCore", dependencies: [
            // The dictionary is shipped in Araso.app/Contents/Resources and passed by path
            // (see JapaneseConverter), not through an SPM resource bundle.
            .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
        ]),
        .executableTarget(name: "Araso", dependencies: ["ArasoCore"]),
        .executableTarget(name: "araso-cli", dependencies: ["ArasoCore"]),
        .testTarget(name: "ArasoCoreTests", dependencies: ["ArasoCore"]),
    ],
    swiftLanguageModes: [.v5]
)
