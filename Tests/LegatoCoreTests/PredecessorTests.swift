import Foundation
import Testing
@testable import LegatoCore

/// Updating from Seamtype (before 0.2.0): its settings folder becomes Legato's.
@Suite struct PredecessorTests {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("legato-predecessor-\(UUID().uuidString)")
    var old: URL { base.appendingPathComponent("Seamtype") }
    var new: URL { base.appendingPathComponent("Legato") }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test func movesSeamtypesFolder() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try write("{\"japanese\":true}", to: old.appendingPathComponent("settings.json"))
        try write("memory", to: old.appendingPathComponent("azooKey/memory.txt"))
        SupportDirectory.movePredecessor(in: base)
        #expect(read(new.appendingPathComponent("settings.json")) == "{\"japanese\":true}")
        #expect(read(new.appendingPathComponent("azooKey/memory.txt")) == "memory")
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func keepsLegatosFolderWhenBothExist() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try write("old", to: old.appendingPathComponent("settings.json"))
        try write("new", to: new.appendingPathComponent("settings.json"))
        SupportDirectory.movePredecessor(in: base)
        #expect(read(new.appendingPathComponent("settings.json")) == "new")
        #expect(read(old.appendingPathComponent("settings.json")) == "old")
    }

    @Test func nothingToMoveOnAFreshInstall() {
        defer { try? FileManager.default.removeItem(at: base) }
        SupportDirectory.movePredecessor(in: base)
        #expect(!FileManager.default.fileExists(atPath: new.path))
    }
}
