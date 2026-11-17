import XCTest
@testable import MultiCodexPetsCore

final class OrcaMessageTrackerTests: XCTestCase {
  private let sender = DetectedAgentSession(
    id: "orca:workspace:structured-agent-session-cat:conversation", agent: .codex,
    hostedByOrca: true, title: "Cat", activity: .running)

  func testBaselineAndDuplicatePollsAreSilentAndCompletionIsNotAMessageAlert() throws {
    var tracker = OrcaMessageTracker()
    let old = row(1)
    XCTAssertEqual(tracker.observe(try data([old]), sessions: [sender]), [])
    let batch = try data([row(5, type: "worker_done"), row(4, type: "heartbeat"), row(3, type: "handoff"), row(2), old])
    let events = try XCTUnwrap(tracker.observe(batch, sessions: [sender]))
    XCTAssertEqual(events.map(\.id), ["message-2", "message-3"])
    XCTAssertEqual(events.map(\.senderSessionID), [sender.id, sender.id])
    XCTAssertEqual(events.map(\.type), ["status", "handoff"])
    XCTAssertEqual(tracker.observe(batch, sessions: [sender]), [])
    XCTAssertEqual(sender.activity, .running)
  }

  func testEmptyHistoryStillDetectsFirstNewMessageAndRepeatedRowsOnlyAlertOnce() throws {
    var tracker = OrcaMessageTracker()
    XCTAssertEqual(tracker.observe(try data([]), sessions: [sender]), [])
    XCTAssertEqual(tracker.observe(try data([row(1), row(1)]), sessions: [sender])?.count, 1)
  }

  func testFailureRecoveryAndExplicitResetDoNotReplayMessages() throws {
    var tracker = OrcaMessageTracker()
    _ = tracker.observe(try data([row(1)]), sessions: [sender])
    XCTAssertNil(tracker.observe(nil, sessions: [sender]))
    XCTAssertEqual(tracker.observe(try data([row(2), row(1)]), sessions: [sender]), [])
    XCTAssertNil(tracker.observe(Data("bad json".utf8), sessions: [sender]))
    XCTAssertEqual(tracker.observe(try data([row(3)]), sessions: [sender]), [])
    tracker.reset()
    XCTAssertEqual(tracker.observe(try data([row(4)]), sessions: [sender]), [])
    XCTAssertEqual(tracker.observe(try data([row(5)]), sessions: [sender])?.map(\.id), ["message-5"])
    XCTAssertEqual(tracker.observe(try data([row(1)]), sessions: [sender]), [])
  }

  func testExactPaneIdentityWorksForTerminalSendersAndAmbiguousOrUnknownSendersAreIgnored() throws {
    var tracker = OrcaMessageTracker()
    _ = tracker.observe(try data([]), sessions: [sender])
    var terminal = row(1, from: "term_123")
    terminal["sender_pane_key"] = "structured-agent-session-cat:conversation"
    XCTAssertEqual(tracker.observe(try data([terminal]), sessions: [sender])?.count, 1)
    let duplicatePane = DetectedAgentSession(id: "orca:other:structured-agent-session-cat:conversation",
      agent: .codex, hostedByOrca: true)
    terminal["sequence"] = 2
    terminal["id"] = "message-2"
    XCTAssertEqual(tracker.observe(try data([terminal]), sessions: [sender, duplicatePane]), [])
    let wrong = [row(3, from: "orca_session_id:ca"), row(4, from: "term_unknown"),
      row(5, from: "orca_session_id:cat", to: "orca_session_id:cat"),
      row(6, from: "orca_session_id:cat", to: "")]
    XCTAssertEqual(tracker.observe(try data(wrong), sessions: [sender]), [])
  }

  func testAConversationAppearingLaterDoesNotReplayItsOldMessages() throws {
    var tracker = OrcaMessageTracker()
    _ = tracker.observe(try data([]), sessions: [])
    XCTAssertEqual(tracker.observe(try data([row(1)]), sessions: []), [])
    XCTAssertEqual(tracker.observe(try data([row(1)]), sessions: [sender]), [])
    XCTAssertEqual(tracker.observe(try data([row(2)]), sessions: [sender])?.count, 1)
  }

  private func row(_ sequence: Int, type: String = "status", from: String = "orca_session_id:cat",
    to: String = "run:coordinator") -> [String: Any] {
    ["id": "message-\(sequence)", "sequence": sequence, "type": type,
      "from_handle": from, "to_handle": to]
  }

  private func data(_ rows: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["ok": true, "result": ["messages": rows]])
  }
}
