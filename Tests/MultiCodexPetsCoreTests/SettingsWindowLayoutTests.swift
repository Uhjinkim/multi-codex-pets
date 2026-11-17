import XCTest

@testable import MultiCodexPetsCore

final class SettingsWindowLayoutTests: XCTestCase {
  func testSmallDisplayFitsWithoutShrinkingControls() {
    let layout = SettingsWindowLayout(visibleSize: CGSize(width: 800, height: 600))
    XCTAssertLessThanOrEqual(layout.contentSize.width, 752)
    XCTAssertLessThanOrEqual(layout.contentSize.height, 520)
    XCTAssertLessThanOrEqual(layout.minimumContentSize.width, layout.contentSize.width)
    XCTAssertLessThanOrEqual(layout.minimumContentSize.height, layout.contentSize.height)
    XCTAssertEqual(layout.scale, 1)
  }

  func testLargerDisplaysIncreaseWindowAndReadableControlSizes() {
    let laptop = SettingsWindowLayout(visibleSize: CGSize(width: 1440, height: 900))
    let desktop = SettingsWindowLayout(visibleSize: CGSize(width: 2560, height: 1440))
    XCTAssertGreaterThan(desktop.contentSize.width, laptop.contentSize.width)
    XCTAssertGreaterThan(desktop.contentSize.height, laptop.contentSize.height)
    XCTAssertGreaterThan(desktop.scale, laptop.scale)
    XCTAssertLessThanOrEqual(desktop.contentSize.width, 820)
    XCTAssertLessThanOrEqual(desktop.contentSize.height, 920)
    XCTAssertLessThanOrEqual(desktop.scale, 1.15)
  }
  func testNarrowWindowKeepsLargeDisplayControlsReadable() {
    let layout = SettingsWindowLayout(visibleSize: CGSize(width: 2560, height: 1440))
    XCTAssertEqual(layout.contentSize.width, 820)
    XCTAssertEqual(layout.minimumContentSize.width, 680)
    XCTAssertEqual(layout.scale, 1.15, accuracy: 0.001)
  }

}
