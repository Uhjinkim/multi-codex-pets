import XCTest

@testable import MultiCodexPetsCore

final class PetNameLabelTests: XCTestCase {
  func testLabelStyleSurvivesSavingAndOlderPreferencesKeepLabelsHidden() throws {
    var preference = PetPreferences()
    var style = PetNameLabel()
    style.position = .above
    style.fontSize = 18
    style.colorHex = "12ABEF"
    preference.nameLabel = style
    preference.customName = "My pet"
    let restored = try JSONDecoder().decode(PetPreferences.self,
      from: JSONEncoder().encode(preference))
    XCTAssertEqual(restored.nameLabel?.position, .above)
    XCTAssertEqual(restored.nameLabel?.resolvedFontSize, 18)
    XCTAssertEqual(restored.nameLabel?.rgb, 0x12ABEF)
    XCTAssertEqual(restored.customName, "My pet")
    let legacy = try JSONDecoder().decode(PetPreferences.self,
      from: Data(#"{"positionLocked":false,"muted":false}"#.utf8))
    XCTAssertEqual((legacy.nameLabel ?? PetNameLabel()).position, .hidden)
  }

  func testInvalidFontSizesAndColorsUseSafeValues() {
    var style = PetNameLabel()
    for (input, expected) in [(Double.nan, 12.0), (.infinity, 12), (-1, 9), (100, 28)] {
      style.fontSize = input
      XCTAssertEqual(style.resolvedFontSize, expected)
    }
    for color in ["bad", "GGGGGG", "1234567", ""] {
      style.colorHex = color
      XCTAssertEqual(style.rgb, 0xFFFFFF)
    }
  }

  func testLabelsStayOutsidePetAndFlipAtScreenEdges() {
    let screen = CGRect(x: -1000, y: 0, width: 1000, height: 800)
    let pet = CGRect(x: -500, y: 100, width: 80, height: 87)
    let size = CGSize(width: 140, height: 24)
    var style = PetNameLabel()
    style.position = .above
    let above = style.frame(pet: pet, size: size, screen: screen)
    XCTAssertEqual(above.midX, pet.midX)
    XCTAssertGreaterThan(above.minY, pet.maxY)
    style.position = .below
    XCTAssertLessThan(style.frame(pet: pet, size: size, screen: screen).maxY, pet.minY)
    let rightPet = CGRect(x: -20, y: 100, width: 80, height: 87)
    let rightLabel = style.frame(pet: rightPet, size: size, screen: screen)
    XCTAssertTrue(screen.contains(rightLabel))
    XCTAssertLessThan(rightLabel.maxY, rightPet.minY)
    let bottomPet = CGRect(x: -20, y: 0, width: 80, height: 87)
    let flipped = style.frame(pet: bottomPet, size: size, screen: screen)
    XCTAssertTrue(screen.contains(flipped))
    XCTAssertGreaterThan(flipped.minY, bottomPet.maxY)
    style.position = .above
    let topPet = CGRect(x: -500, y: 713, width: 80, height: 87)
    let below = style.frame(pet: topPet, size: size, screen: screen)
    XCTAssertTrue(screen.contains(below))
    XCTAssertLessThan(below.maxY, topPet.minY)
  }
}
