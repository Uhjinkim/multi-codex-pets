import Foundation
import MultiCodexPetsCore
import XCTest

final class PetPackageLoaderTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    if let temporaryDirectory {
      try? FileManager.default.removeItem(at: temporaryDirectory)
    }
  }

  func testLoadsValidPetPackage() throws {
    try writePet(
      folderName: "alpha",
      manifest: """
        {
          "id": "alpha",
          "displayName": "Alpha",
          "description": "A test pet.",
          "spritesheetPath": "spritesheet.webp"
        }
        """
    )

    let packages = PetPackageLoader(codexHome: temporaryDirectory).loadPackages()

    XCTAssertEqual(packages.count, 1)
    XCTAssertEqual(packages[0].id, "alpha")
    XCTAssertEqual(packages[0].displayName, "Alpha")
    XCTAssertEqual(packages[0].description, "A test pet.")
    XCTAssertEqual(packages[0].source, .custom)
  }

  func testLoadsPackagesThroughLinkedPetsDirectory() throws {
    try writePet(folderName: "alpha", manifest: "{}")
    let manager = FileManager.default
    let linkedHome = temporaryDirectory.appendingPathComponent("account", isDirectory: true)
    try manager.createDirectory(at: linkedHome, withIntermediateDirectories: true)
    try manager.createSymbolicLink(at: linkedHome.appendingPathComponent("pets"),
      withDestinationURL: temporaryDirectory.appendingPathComponent("pets"))

    XCTAssertEqual(PetPackageLoader(codexHome: linkedHome).loadPackages().map(\.id), ["alpha"])
  }

  func testExcludesIDsAlreadyUsedByBuiltInPets() throws {
    for name in ["alpha", "codex-default-rocky"] {
      try writePet(folderName: name, manifest: "{}")
    }
    let loader = PetPackageLoader(codexHome: temporaryDirectory)
    XCTAssertEqual(loader.loadPackages().count, 2)
    XCTAssertEqual(loader.loadPackages(excludingIDs: ["codex-default-rocky"]).map(\.id), ["alpha"])
  }

  func testRejectsSpritesheetPathOutsidePackageDirectory() throws {
    try writePet(
      folderName: "escape",
      manifest: """
        {
          "displayName": "Escape",
          "spritesheetPath": "../spritesheet.webp"
        }
        """
    )

    let packages = PetPackageLoader(codexHome: temporaryDirectory).loadPackages()

    XCTAssertTrue(packages.isEmpty)
  }

  func testLoadsBothLayoutsAndValidatesDeclaredVersion() throws {
    for (name, height, version) in [
      ("v1", 1872, 1), ("v2", 2288, 2), ("inferred-v2", 2288, 0),
      ("mismatch", 1872, 2), ("unknown", 2288, 3), ("invalid", 2080, 0),
    ] {
      let declaration = version == 0 ? "" : ", \"spriteVersionNumber\": \(version)"
      try writePet(
        folderName: name,
        manifest: "{\"displayName\": \"\(name)\"\(declaration)}",
        height: height
      )
    }
    let packages = PetPackageLoader(codexHome: temporaryDirectory).loadPackages()
    XCTAssertEqual(packages.map(\.id), ["inferred-v2", "v1", "v2"])
    XCTAssertEqual(packages.map(\.spriteVersion), [.v2, .v1, .v2])
  }

  private func writePet(folderName: String, manifest: String, height: Int = 1_872) throws {
    let packageDirectory =
      temporaryDirectory
      .appendingPathComponent("pets", isDirectory: true)
      .appendingPathComponent(folderName, isDirectory: true)
    try FileManager.default.createDirectory(
      at: packageDirectory,
      withIntermediateDirectories: true
    )
    try manifest.write(
      to: packageDirectory.appendingPathComponent("pet.json"),
      atomically: true,
      encoding: .utf8
    )
    try TestImageData.webP(width: 1_536, height: height)
      .write(to: packageDirectory.appendingPathComponent("spritesheet.webp"))
  }
}
