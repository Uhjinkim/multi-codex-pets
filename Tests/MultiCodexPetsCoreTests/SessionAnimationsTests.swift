import XCTest

@testable import MultiCodexPetsCore

final class SessionAnimationsTests: XCTestCase {
  func testDefaultsPreserveEveryStatusAndMissingSessionsStayIdle() {
    let settings = SessionAnimations()
    for activity in AgentActivity.allCases {
      XCTAssertEqual(settings.animation(for: activity), activity.animationState)
    }
    XCTAssertEqual(settings.animation(for: nil), .idle)
  }

  func testOverridesSurviveSavingAndInvalidAnimationsUseDefaults() throws {
    var settings = SessionAnimations()
    settings.overrides = [
      AgentActivity.running.rawValue: AnimationState.jumping.rawValue,
      AgentActivity.unknown.rawValue: AnimationState.review.rawValue,
      AgentActivity.completed.rawValue: "future-animation",
    ]
    let restored = try JSONDecoder().decode(
      SessionAnimations.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(restored.animation(for: .running), .jumping)
    XCTAssertEqual(restored.animation(for: .unknown), .review)
    XCTAssertEqual(restored.animation(for: .completed), .waving)
    XCTAssertEqual(restored.animation(for: .failed), .failed)
    XCTAssertEqual(restored.animation(for: nil), .idle)
  }
}
