import XCTest

@testable import MultiCodexPetsCore

final class SessionNotificationPolicyTests: XCTestCase {
  func testFiltersAndCooldownDoNotSuppressOtherImportantStatesOrPets() {
    var policy = SessionNotificationPolicy()
    let allowed: Set<AgentActivity> = [.completed, .approval, .failed]
    let now = Date(timeIntervalSince1970: 100)
    XCTAssertFalse(
      policy.shouldNotify(petID: "one", activity: .running, allowed: allowed, cooldown: 5, now: now)
    )
    XCTAssertTrue(
      policy.shouldNotify(
        petID: "one", activity: .completed, allowed: allowed, cooldown: 5, now: now))
    XCTAssertFalse(
      policy.shouldNotify(
        petID: "one", activity: .completed, allowed: allowed, cooldown: 5,
        now: now.addingTimeInterval(2)))
    XCTAssertTrue(
      policy.shouldNotify(
        petID: "one", activity: .approval, allowed: allowed, cooldown: 5,
        now: now.addingTimeInterval(2)))
    XCTAssertTrue(
      policy.shouldNotify(
        petID: "two", activity: .completed, allowed: allowed, cooldown: 5,
        now: now.addingTimeInterval(2)))
    XCTAssertTrue(
      policy.shouldNotify(
        petID: "one", activity: .completed, allowed: allowed, cooldown: 5,
        now: now.addingTimeInterval(5)))
  }

  func testClockChangeAndResetDoNotLeaveAlertsPermanentlySuppressed() {
    var policy = SessionNotificationPolicy()
    let now = Date(timeIntervalSince1970: 100)
    _ = policy.shouldNotify(
      petID: "one", activity: .failed, allowed: [.failed], cooldown: 60, now: now)
    XCTAssertTrue(
      policy.shouldNotify(
        petID: "one", activity: .failed, allowed: [.failed], cooldown: 60,
        now: now.addingTimeInterval(-10)))
    policy.reset()
    XCTAssertTrue(
      policy.shouldNotify(
        petID: "one", activity: .failed, allowed: [.failed], cooldown: 60, now: now))
  }
}
