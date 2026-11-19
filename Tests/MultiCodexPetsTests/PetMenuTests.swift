import AppKit
import MultiCodexPetsCore
import XCTest
@testable import MultiCodexPets

final class PetMenuTests: XCTestCase {
  private var suite: String!
  private var defaults: UserDefaults!
  private var app: AppDelegate!

  override func setUp() {
    _ = NSApplication.shared
    suite = UUID().uuidString
    defaults = UserDefaults(suiteName: suite)!
    app = AppDelegate(settings: AppSettings(defaults: defaults))
  }

  override func tearDown() {
    for window in NSApp.windows where window.title == localized("Multi Codex Pets Settings") { window.close() }
    app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    app = nil
    defaults.removePersistentDomain(forName: suite)
  }

  func testOpeningAndClosingSessionSelectionDoesNotChangeSavedRoutingOrBehavior() throws {
    var routing = SessionRouting()
    routing.mode = .single
    routing.singleSessionID = "original"
    app.settings.savedRouting = routing
    app = AppDelegate(settings: app.settings)
    app.settings.followsSessions = false
    app.settings.walksAround = false
    app.requestSessionChange("cat")
    XCTAssertEqual(app.requestedSettingsPetID, "cat")
    XCTAssertEqual(app.sessionRouting.mode, .single)
    XCTAssertEqual(app.settings.savedRouting.singleSessionID, "original")
    XCTAssertFalse(app.settings.followsSessions)
    for window in NSApp.windows where window.title == localized("Multi Codex Pets Settings") { window.close() }
    XCTAssertNil(app.requestedSettingsPetID)
    XCTAssertEqual(app.settings.savedRouting.mode, .single)
    app.selectSession("new", petID: "cat")
    XCTAssertEqual(app.sessionRouting.mode, .perPet)
    XCTAssertEqual(app.settings.savedRouting.sessionIDsByPet["cat"], "new")
    XCTAssertTrue(app.settings.followsSessions)
  }

  func testRefreshKeepsSelectionsWhenPackagesAreTemporarilyUnavailable() {
    app.settings.selectedPetIDs = ["temporarily-unavailable-package"]
    app.refreshPetsAction()
    XCTAssertEqual(app.settings.selectedPetIDs, ["temporarily-unavailable-package"])
    XCTAssertTrue(app.selectedPetPackages.isEmpty)
  }

  func testMenuOffersDirectActionsAndCursorOptionsOnlyForV2() throws {
    let v1 = app.petContextMenu(pet("v1", version: .v1))
    let v2 = app.petContextMenu(pet("v2", version: .v2))
    for title in ["Change Session…", "Pet Size", "Lock Position", "Mute This Pet", "Pet Settings…"] {
      XCTAssertNotNil(v2.item(withTitle: localized(title)))
    }
    for title in ["Sounds…", "Rename Pet…", "Name Label…", "Animations…",
      "Move to Display", "Open Sound Folder…", "Arrange Direction Frames…", "Open Agent App"] {
      XCTAssertNil(v2.item(withTitle: localized(title)))
    }
    XCTAssertNil(v2.item(withTitle: localized("Session")))
    XCTAssertNil(v1.item(withTitle: localized("Cursor Tracking")))
    let tracking = try XCTUnwrap(v2.item(withTitle: localized("Cursor Tracking"))?.submenu)
    XCTAssertEqual(tracking.items.filter { $0.state == .on }.map(\.title), [localized("Always")])
    let shakeIndex = try XCTUnwrap(tracking.items.firstIndex { $0.title == localized("When Shaken") })
    tracking.performActionForItem(at: shakeIndex)
    XCTAssertEqual(app.cursorTrackingMode(for: "v2"), .whenShaken)
    XCTAssertEqual(app.cursorTrackingMode(for: "other"), .always)
    XCTAssertTrue(app.settings.followsCursor)
    app.setFollowsCursor(false)
    XCTAssertEqual(app.cursorTrackingMode(for: "v2"), .whenShaken)
    XCTAssertEqual(app.cursorTrackingMode(for: "other"), .off)
    XCTAssertEqual(app.settings.petPreferences.count, 1)
  }

  private func pet(_ id: String, version: PetSpriteVersion) -> PetPackage {
    PetPackage(id: id, folderName: id, displayName: id, description: nil,
      spritesheetURL: URL(fileURLWithPath: "/missing"), packageDirectory: URL(fileURLWithPath: "/tmp"),
      spriteVersion: version)
  }

  func testGlobalAndPetVolumeAndMutePreserveOtherPetPreferences() {
    app.setVolume(0.5, role: .click)
    app.setVolume(0.8, role: .notification)
    app.setPetPreference("cat", cursorTrackingMode: .whenShaken, soundVolume: 0.4)
    XCTAssertEqual(app.soundVolume(for: "cat", role: .click), 0.2, accuracy: 0.001)
    XCTAssertEqual(app.soundVolume(for: "cat", role: .notification), 0.32, accuracy: 0.001)
    XCTAssertEqual(app.soundVolume(for: "dog", role: .click), 0.5)
    app.setPetPreference("cat", muted: true)
    XCTAssertEqual(app.soundVolume(for: "cat", role: .click), 0)
    XCTAssertEqual(app.soundVolume(for: "dog", role: .click), 0.5)
    app.setSoundsMuted(true)
    XCTAssertEqual(app.soundVolume(for: "dog", role: .click), 0)
    app.setSoundsMuted(false)
    XCTAssertEqual(app.soundVolume(for: "cat", role: .click), 0)
    app.setPetPreference("cat", muted: false)
    XCTAssertEqual(app.soundVolume(for: "cat", role: .click), 0.2, accuracy: 0.001)
    XCTAssertEqual(app.cursorTrackingMode(for: "cat"), .whenShaken)
    XCTAssertNil(app.settings.petPreferences["dog"])
  }
}
