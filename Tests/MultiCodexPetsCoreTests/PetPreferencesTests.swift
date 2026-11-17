import XCTest

@testable import MultiCodexPetsCore

final class PetPreferencesTests: XCTestCase {
  func testRestoresFrameDisplayAndInteractionPreferences() throws {
    var preference = PetPreferences()
    preference.frame = CGRect(x: -400, y: 80, width: 100, height: 110)
    preference.screenID = 42
    preference.positionLocked = true
    preference.muted = true
    let restored = try JSONDecoder().decode(
      PetPreferences.self, from: JSONEncoder().encode(preference))
    XCTAssertEqual(restored.frame, preference.frame)
    XCTAssertEqual(restored.screenID, 42)
    XCTAssertTrue(restored.positionLocked)
    XCTAssertTrue(restored.muted)
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    XCTAssertTrue(screen.contains(PetPlacement.fitted(restored.frame!, to: screen)))
    let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    XCTAssertTrue(
      left.contains(PetPlacement.fitted(CGRect(x: 100, y: 2000, width: 100, height: 110), to: left))
    )
  }

  func testCustomNamesNormalizePersistAndRestoreWithoutLosingPreferences() throws {
    var preference = PetPreferences()
    preference.positionLocked = true
    preference.muted = true
    preference.setCustomName("  나의\n  펫 🐾  ")
    XCTAssertEqual(preference.displayName(fallback: "Original"), "나의 펫 🐾")
    var restored = try JSONDecoder().decode(
      PetPreferences.self, from: JSONEncoder().encode(preference))
    XCTAssertEqual(restored.customName, "나의 펫 🐾")
    restored.setCustomName(" \n ")
    XCTAssertNil(restored.customName)
    XCTAssertEqual(restored.displayName(fallback: "Original"), "Original")
    XCTAssertTrue(restored.positionLocked)
    XCTAssertTrue(restored.muted)
  }

  func testPreferencesSavedBeforeRenamingKeepTheirOriginalNameAndSettings() throws {
    let saved = Data(#"{"positionLocked":true,"muted":false,"screenID":42}"#.utf8)
    let restored = try JSONDecoder().decode(PetPreferences.self, from: saved)
    XCTAssertEqual(restored.displayName(fallback: "Original"), "Original")
    XCTAssertEqual(restored.screenID, 42)
    XCTAssertTrue(restored.positionLocked)
  }

  func testConversationAssignmentsRoundTripWithoutRebindingMissingConversations() throws {
    var routing = SessionRouting()
    routing.mode = .perPet
    routing.sessionIDsByPet = ["cat": "codex:conversation", "dog": "idle"]
    let saved = try JSONEncoder().encode(routing)
    let restored = try JSONDecoder().decode(SessionRouting.self, from: saved)
    let session = DetectedAgentSession(id: "codex:conversation", agent: .codex, activity: .approval)
    XCTAssertEqual(restored.states(for: ["cat", "dog"], sessions: [session]), [.review, .idle])
    XCTAssertEqual(
      restored.states(
        for: ["cat", "dog"], sessions: [.init(id: "codex:other", agent: .codex, activity: .running)]
      ), [.idle, .idle])
  }
}
