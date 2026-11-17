import XCTest

@testable import MultiCodexPetsCore

final class DragDirectionTrackerTests: XCTestCase {
  func testReversesWithoutCrossingTheOriginalClickPosition() {
    var tracker = DragDirectionTracker(startX: 100)
    XCTAssertEqual(tracker.update(x: 160), .runningRight)
    XCTAssertEqual(tracker.update(x: 154), .runningLeft)
    XCTAssertEqual(tracker.update(x: 161), .runningRight)
  }

  func testSmallEventsAccumulateAndJitterKeepsDirection() {
    var tracker = DragDirectionTracker(startX: 100)
    for x: CGFloat in [101, 102, 103, 104] { XCTAssertNil(tracker.update(x: x)) }
    XCTAssertEqual(tracker.update(x: 105), .runningRight)
    for x: CGFloat in [106, 107, 108, 109, 110, 109, 108, 107, 106] {
      XCTAssertEqual(tracker.update(x: x), .runningRight)
    }
    XCTAssertEqual(tracker.update(x: 105), .runningLeft)
  }

  func testLeftwardReversalAndVerticalMovementAreStable() {
    var tracker = DragDirectionTracker(startX: 100)
    XCTAssertNil(tracker.update(x: 100))
    XCTAssertEqual(tracker.update(x: 60), .runningLeft)
    XCTAssertEqual(tracker.update(x: 60), .runningLeft)
    XCTAssertEqual(tracker.update(x: 66), .runningRight)
    XCTAssertEqual(tracker.update(x: .nan), .runningRight)
    XCTAssertEqual(tracker.update(x: .infinity), .runningRight)
    tracker = DragDirectionTracker(startX: 500)
    XCTAssertNil(tracker.update(x: 500))
  }
}
