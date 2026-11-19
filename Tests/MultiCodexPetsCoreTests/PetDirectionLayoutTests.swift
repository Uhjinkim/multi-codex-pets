import MultiCodexPetsCore
import XCTest

final class PetDirectionLayoutTests: XCTestCase {
  func testRunningAndGazeCorrectionsSurviveSavingAndKeepOtherFramesIntact() throws {
    var layout = PetDirectionLayout()
    layout.swapRunningRows()
    layout.swap(16 + 4, 16 + 12)
    layout.mirror(16 + 12)
    layout.swap(0, 16)

    let preferences = try JSONDecoder().decode(
      PetDirectionLayout.self, from: JSONEncoder().encode(layout))
    let run = preferences.resolve(PetDirectionLayout.frame(at: 3))
    XCTAssertEqual(run.frame.rowIndex, 2)
    XCTAssertEqual(run.frame.columnIndex, 3)
    XCTAssertFalse(run.mirrored)
    let left = preferences.resolve(PetDirectionLayout.frame(at: 28))
    XCTAssertEqual(left.frame.rowIndex, 9)
    XCTAssertEqual(left.frame.columnIndex, 4)
    XCTAssertTrue(left.mirrored)

    let idle = try XCTUnwrap(AnimationTimeline.frames(for: .idle).first)
    XCTAssertEqual(preferences.resolve(idle).frame, idle)
  }

  func testRejectsInvalidSavedMapping() {
    XCTAssertThrowsError(try JSONDecoder().decode(
      PetDirectionLayout.self, from: Data("[{\"source\":99,\"mirrored\":false}]".utf8)))
  }
}
