import XCTest
@testable import MultiCodexPetsCore

final class CursorShakeTrackerTests: XCTestCase {
  func testShakeInEitherAxisLooksForTwoSecondsThenExpires() {
    for vertical in [false, true] {
      var tracker = CursorShakeTracker()
      for (index, position) in [0.0, 60, 0, 60, 0].enumerated() {
        let point = CGPoint(x: vertical ? 0 : position, y: vertical ? position : 0)
        XCTAssertEqual(tracker.update(point: point, now: Double(index) * 0.1), index == 4)
      }
      for step in 5...23 {
        XCTAssertTrue(tracker.update(point: .zero, now: Double(step) * 0.1))
      }
      XCTAssertFalse(tracker.update(point: .zero, now: 2.41))
    }
  }

  func testJitterStraightMovementAndSlowReversalsDoNotTrigger() {
    for positions in [[0.0, 10, 0, 10, 0, 10], [0.0, 40, 80, 120, 160, 200]] {
      var tracker = CursorShakeTracker()
      for (index, x) in positions.enumerated() {
        XCTAssertFalse(tracker.update(point: CGPoint(x: x, y: 0), now: Double(index) * 0.1))
      }
    }
    var tracker = CursorShakeTracker()
    for index in 0..<40 {
      let x = (index / 5).isMultiple(of: 2) ? 0.0 : 60.0
      XCTAssertFalse(tracker.update(point: CGPoint(x: x, y: 0), now: Double(index) * 0.1))
    }
  }

  func testScreenJumpsPausesInvalidSamplesAndBackwardClockResetDetection() {
    for (point, now) in [(CGPoint(x: 1200, y: 0), 0.35), (.zero, 5.0),
      (.zero, -1.0), (CGPoint(x: Double.nan, y: 0), 0.35)] {
      var tracker = CursorShakeTracker()
      for (index, x) in [0.0, 60, 0, 60].enumerated() {
        XCTAssertFalse(tracker.update(point: CGPoint(x: x, y: 0), now: Double(index) * 0.1))
      }
      XCTAssertFalse(tracker.update(point: point, now: now))
    }
  }
}
