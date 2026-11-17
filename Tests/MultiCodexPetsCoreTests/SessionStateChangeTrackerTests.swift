import XCTest

@testable import MultiCodexPetsCore

final class SessionStateChangeTrackerTests: XCTestCase {
  private func session(_ state: AgentActivity, id: String = "a", title: String = "Task")
    -> DetectedAgentSession
  {
    .init(id: id, agent: .codex, title: title, activity: state)
  }

  func testInitialConnectionAndDuplicatePollsAreSilentButEachKnownChangeNotifies() {
    var tracker = SessionStateChangeTracker()
    XCTAssertEqual(tracker.changedPets(assignments: ["pet": session(.running)], enabled: true), [])
    XCTAssertEqual(tracker.changedPets(assignments: ["pet": session(.running)], enabled: true), [])
    XCTAssertEqual(
      tracker.changedPets(assignments: ["pet": session(.approval)], enabled: true), ["pet"])
    XCTAssertEqual(
      tracker.changedPets(assignments: ["pet": session(.completed)], enabled: true), ["pet"])
    XCTAssertEqual(
      tracker.changedPets(
        assignments: ["pet": session(.completed, title: "Renamed")], enabled: true), [])
  }

  func testReassignmentDisappearanceAndDisabledModeRebaseline() {
    var tracker = SessionStateChangeTracker()
    _ = tracker.changedPets(assignments: ["pet": session(.running)], enabled: true)
    XCTAssertEqual(
      tracker.changedPets(assignments: ["pet": session(.completed, id: "b")], enabled: true), [])
    XCTAssertEqual(tracker.changedPets(assignments: [:], enabled: true), [])
    XCTAssertEqual(
      tracker.changedPets(assignments: ["pet": session(.failed, id: "b")], enabled: true), [])
    XCTAssertEqual(
      tracker.changedPets(assignments: ["pet": session(.running, id: "b")], enabled: false), [])
    XCTAssertEqual(
      tracker.changedPets(assignments: ["pet": session(.completed, id: "b")], enabled: true), [])
    tracker.reset()
    XCTAssertEqual(tracker.changedPets(assignments: ["pet": session(.running)], enabled: true), [])
  }

  func testUnknownStateDoesNotChimeAndKeepsLastKnownObservation() {
    var tracker = SessionStateChangeTracker()
    _ = tracker.changedPets(assignments: ["pet": session(.unknown)], enabled: true)
    XCTAssertEqual(tracker.changedPets(assignments: ["pet": session(.running)], enabled: true), [])
    XCTAssertEqual(tracker.changedPets(assignments: ["pet": session(.unknown)], enabled: true), [])
    XCTAssertEqual(tracker.changedPets(assignments: ["pet": session(.running)], enabled: true), [])
    _ = tracker.changedPets(assignments: ["pet": session(.unknown)], enabled: true)
    XCTAssertEqual(
      tracker.changedPets(assignments: ["pet": session(.completed)], enabled: true), ["pet"])
  }

  func testOnlyAssignedPetsAndTheirOwnSessionsAreObserved() {
    var routing = SessionRouting()
    routing.mode = .perPet
    routing.sessionIDsByPet = ["one": "a", "two": "idle", "three": "b"]
    let pets = ["one", "two", "three"]
    func assignments(_ sessions: [DetectedAgentSession]) -> [String: DetectedAgentSession] {
      var result: [String: DetectedAgentSession] = [:]
      for (pet, session) in zip(pets, routing.resolvedSessions(for: pets, sessions: sessions)) {
        result[pet] = session
      }
      return result
    }
    var tracker = SessionStateChangeTracker()
    _ = tracker.changedPets(
      assignments: assignments([session(.running), session(.waiting, id: "b")]), enabled: true)
    XCTAssertEqual(
      tracker.changedPets(
        assignments: assignments([
          session(.completed), session(.waiting, id: "b"), session(.failed, id: "unassigned"),
        ]), enabled: true), ["one"])
  }
}
