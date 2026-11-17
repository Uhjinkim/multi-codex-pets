import Foundation
import MultiCodexPetsCore
import XCTest

final class PetSoundLibraryTests: XCTestCase {
  func testFindsOnlyAudioFilesForChosenPetInFilenameOrder() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let library = PetSoundLibrary(codexHome: home)
    let folder = try XCTUnwrap(library.directory(forPetID: "codex-default-cat"))
    XCTAssertEqual(
      folder, home.appendingPathComponent("pet-sounds/codex-default-cat", isDirectory: true))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in ["b.mp3", "a.WAV", "c.m4a", "d.aiff", "e.aif", "f.caf", "notes.txt", ".hidden.wav"]
    {
      try Data().write(to: folder.appendingPathComponent(name))
    }
    try FileManager.default.createDirectory(
      at: folder.appendingPathComponent("directory.wav"), withIntermediateDirectories: true)
    XCTAssertEqual(
      library.soundURLs(forPetID: "codex-default-cat").map(\.lastPathComponent),
      ["a.WAV", "b.mp3", "c.m4a", "d.aiff", "e.aif", "f.caf"])
    XCTAssertTrue(library.soundURLs(forPetID: "other-pet").isEmpty)
  }

  func testRejectsInvalidPetIDs() {
    let library = PetSoundLibrary()
    for id in ["", ".", "..", "../outside", "/tmp", "a/b", "a\0b"] {
      XCTAssertNil(library.directory(forPetID: id))
      XCTAssertTrue(library.soundURLs(forPetID: id).isEmpty)
    }
  }
  func testImportSelectsSoundWithoutOverwritingExistingFiles() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let library = PetSoundLibrary(codexHome: home)
    let source = home.appendingPathComponent("click.wav")
    try Data("new".utf8).write(to: source)
    let folder = try XCTUnwrap(library.directory(forPetID: "pet"))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let old = folder.appendingPathComponent("click.wav")
    try Data("old".utf8).write(to: old)
    let imported = try library.importSound(from: source, forPetID: "pet")
    XCTAssertNotEqual(imported, old)
    XCTAssertEqual(try Data(contentsOf: old), Data("old".utf8))
    XCTAssertEqual(try Data(contentsOf: source), Data("new".utf8))
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet").first?.resolvingSymlinksInPath(),
      imported.resolvingSymlinksInPath())
    let existing = try library.importSound(from: old, forPetID: "pet")
    XCTAssertEqual(existing, old)
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet").first?.resolvingSymlinksInPath(),
      old.resolvingSymlinksInPath())
    XCTAssertEqual(library.soundURLs(forPetID: "pet").count, 2)
    try FileManager.default.removeItem(at: old)
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet").first?.resolvingSymlinksInPath(),
      imported.resolvingSymlinksInPath())
  }

  func testImportRejectsUnsupportedFilesAndKeepsHiddenSourcePlayable() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let library = PetSoundLibrary(codexHome: home)
    let bad = home.appendingPathComponent("notes.txt")
    try Data().write(to: bad)
    XCTAssertThrowsError(try library.importSound(from: bad, forPetID: "pet"))
    XCTAssertThrowsError(try library.importSound(from: bad, forPetID: "../escape"))
    let hidden = home.appendingPathComponent(".click.wav")
    try Data().write(to: hidden)
    let imported = try library.importSound(from: hidden, forPetID: "pet")
    XCTAssertFalse(imported.lastPathComponent.hasPrefix("."))
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet").first?.resolvingSymlinksInPath(),
      imported.resolvingSymlinksInPath())
  }

  func testClickAndNotificationPoolsAreIndependentAndPersisted() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let library = PetSoundLibrary(codexHome: home)
    let a = home.appendingPathComponent("a.wav")
    let b = home.appendingPathComponent("b.wav")
    try Data().write(to: a)
    try Data().write(to: b)
    let click = try library.importSound(from: a, forPetID: "pet")
    let alert = try library.importSound(from: b, forPetID: "pet", role: .notification)
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet", role: .click).map(\.lastPathComponent),
      [click.lastPathComponent])
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet", role: .notification).map(\.lastPathComponent),
      [alert.lastPathComponent])
    try library.setUsage(
      true, filename: click.lastPathComponent, forPetID: "pet", role: .notification)
    try library.setUsage(true, filename: alert.lastPathComponent, forPetID: "pet", role: .click)
    let reopened = PetSoundLibrary(codexHome: home)
    XCTAssertEqual(reopened.soundURLs(forPetID: "pet", role: .click).count, 2)
    XCTAssertEqual(reopened.soundURLs(forPetID: "pet", role: .notification).count, 2)
    try reopened.setUsage(false, filename: click.lastPathComponent, forPetID: "pet", role: .click)
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet", role: .click).map(\.lastPathComponent),
      [alert.lastPathComponent])
    XCTAssertEqual(library.soundURLs(forPetID: "pet").count, 2)
    XCTAssertThrowsError(
      try library.setUsage(true, filename: "../escape.wav", forPetID: "pet", role: .notification))
  }

  func testLegacyAndDroppedAudioDefaultsToClickOnly() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let library = PetSoundLibrary(codexHome: home)
    let folder = try XCTUnwrap(library.directory(forPetID: "pet"))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data().write(to: folder.appendingPathComponent("legacy.wav"))
    XCTAssertEqual(library.soundURLs(forPetID: "pet", role: .click).count, 1)
    XCTAssertTrue(library.soundURLs(forPetID: "pet", role: .notification).isEmpty)
    try library.setUsage(true, filename: "legacy.wav", forPetID: "pet", role: .notification)
    try Data().write(to: folder.appendingPathComponent("dropped.wav"))
    XCTAssertEqual(library.soundURLs(forPetID: "pet", role: .click).count, 2)
    XCTAssertEqual(library.soundURLs(forPetID: "pet", role: .notification).count, 1)
  }

  func testStateSpecificAlertPoolAndLegacyConfigurationMigration() throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let library = PetSoundLibrary(codexHome: home)
    let folder = try XCTUnwrap(library.directory(forPetID: "pet"))
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in ["bell.wav", "error.wav"] {
      try Data().write(to: folder.appendingPathComponent(name))
    }
    try Data("{\"excludedFromClick\":[],\"notifications\":[\"bell.wav\"]}".utf8)
      .write(to: folder.appendingPathComponent(".sound-roles.json"))
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet", role: .notification, activity: .completed).map(
        \.lastPathComponent), ["bell.wav"])
    try library.setUsage(
      true, filename: "error.wav", forPetID: "pet", role: .notification, activity: .failed)
    try library.setUsage(
      false, filename: "bell.wav", forPetID: "pet", role: .notification, activity: .failed)
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet", role: .notification, activity: .failed).map(
        \.lastPathComponent), ["error.wav"])
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet", role: .notification, activity: .completed).map(
        \.lastPathComponent), ["bell.wav"])
    try library.useDefaultNotificationPool(forPetID: "pet", activity: .failed)
    XCTAssertEqual(
      library.soundURLs(forPetID: "pet", role: .notification, activity: .failed).map(
        \.lastPathComponent), ["bell.wav"])
  }

}
