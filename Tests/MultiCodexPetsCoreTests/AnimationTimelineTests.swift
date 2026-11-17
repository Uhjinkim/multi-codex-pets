import CoreGraphics
import MultiCodexPetsCore
import XCTest

final class AnimationTimelineTests: XCTestCase {
  func testAnimationRowsMatchCodexPetContract() {
    XCTAssertEqual(AnimationTimeline.frames(for: .idle).map(\.columnIndex), [0, 1, 2, 3, 4, 5])
    XCTAssertEqual(AnimationTimeline.frames(for: .runningRight).map(\.rowIndex).uniqued(), [1])
    XCTAssertEqual(AnimationTimeline.frames(for: .runningLeft).map(\.rowIndex).uniqued(), [2])
    XCTAssertEqual(AnimationTimeline.frames(for: .waving).count, 4)
    XCTAssertEqual(AnimationTimeline.frames(for: .jumping).count, 5)
    XCTAssertEqual(AnimationTimeline.frames(for: .failed).count, 8)
    XCTAssertEqual(AnimationTimeline.frames(for: .waiting).count, 6)
    XCTAssertEqual(AnimationTimeline.frames(for: .running).count, 6)
    XCTAssertEqual(AnimationTimeline.frames(for: .review).count, 6)
  }

  func testBothLayoutsCropStandardFramesFromTopOfSheet() {
    for version in [PetSpriteVersion.v1, .v2] {
      for state in AnimationState.allCases {
        for frame in AnimationTimeline.frames(for: state) {
          let rect = version.sourceRect(for: frame)
          XCTAssertEqual(Int(rect.minX), frame.columnIndex * 192)
          XCTAssertEqual(Int(rect.minY), version.height - (frame.rowIndex + 1) * 208)
          XCTAssertEqual(rect.width, 192)
          XCTAssertEqual(rect.height, 208)
          XCTAssertGreaterThanOrEqual(rect.minY, 0)
          XCTAssertLessThanOrEqual(Int(rect.maxY), version.height)
        }
      }
    }
  }

  func testV2LookDirectionsRunClockwiseFromUp() {
    let center = CGPoint(x: -500, y: 300)
    for direction in 0..<16 {
      let angle = Double(direction) * .pi / 8
      let pointer = CGPoint(x: center.x + sin(angle) * 100, y: center.y + cos(angle) * 100)
      let frame = PetSpriteVersion.v2.lookFrame(pointer: pointer, center: center, deadzone: 20)
      XCTAssertEqual(frame?.rowIndex, 9 + direction / 8)
      XCTAssertEqual(frame?.columnIndex, direction % 8)
    }
  }

  func testLookTrackingDeadzoneAndV1Fallback() {
    let center = CGPoint.zero
    for pointer in [center, CGPoint(x: 20, y: 0), CGPoint(x: 0, y: -19)] {
      XCTAssertNil(PetSpriteVersion.v2.lookFrame(pointer: pointer, center: center, deadzone: 20))
    }
    XCTAssertNil(
      PetSpriteVersion.v1.lookFrame(
        pointer: CGPoint(x: 100, y: 100), center: center, deadzone: 20
      ))
    XCTAssertNil(
      PetSpriteVersion.v2.lookFrame(
        pointer: CGPoint(x: CGFloat.nan, y: 0), center: center, deadzone: 20
      ))
    for degrees in [-11.0, 11.0, 349.0, 371.0] {
      let angle = degrees * .pi / 180
      let frame = PetSpriteVersion.v2.lookFrame(
        pointer: CGPoint(x: sin(angle) * 100, y: cos(angle) * 100), center: center, deadzone: 20
      )
      XCTAssertEqual(frame?.rowIndex, 9)
      XCTAssertEqual(frame?.columnIndex, 0)
    }
  }

  func testReducedMotionUsesFirstFrameOnly() {
    XCTAssertEqual(AnimationTimeline.frames(for: .review, reducedMotion: true).count, 1)
    XCTAssertEqual(AnimationTimeline.frames(for: .review, reducedMotion: true).first?.rowIndex, 8)
  }
}

extension Array where Element: Equatable {
  fileprivate func uniqued() -> [Element] {
    reduce(into: []) { result, element in
      if result.last != element {
        result.append(element)
      }
    }
  }
}
