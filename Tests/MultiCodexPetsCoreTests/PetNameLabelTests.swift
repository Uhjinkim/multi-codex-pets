import XCTest

@testable import MultiCodexPetsCore

final class PetNameLabelTests: XCTestCase {
  func testLabelStyleSurvivesSavingAndOlderPreferencesKeepLabelsHidden() throws {
    var preference = PetPreferences()
    var style = PetNameLabel()
    style.position = .above
    style.fontSize = 18
    style.colorHex = "12ABEF"
    style.backgroundColorHex = "345678"
    style.backgroundOpacity = 0.4
    preference.nameLabel = style
    preference.customName = "My pet"
    let restored = try JSONDecoder().decode(PetPreferences.self,
      from: JSONEncoder().encode(preference))
    XCTAssertEqual(restored.nameLabel?.position, .above)
    XCTAssertEqual(restored.nameLabel?.resolvedFontSize, 18)
    XCTAssertEqual(restored.nameLabel?.rgb, 0x12ABEF)
    XCTAssertEqual(restored.nameLabel?.backgroundRGB, 0x345678)
    XCTAssertEqual(restored.nameLabel?.resolvedBackgroundOpacity, 0.4)
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

  func testExistingLabelStylesKeepTheirNamesFontsAndOriginalBackground() throws {
    let data = Data(#"{"position":"Above Pet","fontSize":18,"colorHex":"12ABEF"}"#.utf8)
    let style = try JSONDecoder().decode(PetNameLabel.self, from: data)
    XCTAssertEqual(style.position, .above)
    XCTAssertEqual(style.resolvedFontSize, 18)
    XCTAssertEqual(style.rgb, 0x12ABEF)
    XCTAssertEqual(style.backgroundRGB, 0)
    XCTAssertEqual(style.resolvedBackgroundOpacity, 0.65)
  }

  func testBackgroundValuesClampAndInvalidColorsUseBlack() {
    var style = PetNameLabel()
    for (value, expected) in [(Double.nan, 0.65), (.infinity, 0.65), (-1, 0), (2, 1), (0.25, 0.25)] {
      style.backgroundOpacity = value
      XCTAssertEqual(style.resolvedBackgroundOpacity, expected)
    }
    for hex in ["bad", "GGGGGG", "1234567", ""] {
      style.backgroundColorHex = hex
      XCTAssertEqual(style.backgroundRGB, 0)
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
