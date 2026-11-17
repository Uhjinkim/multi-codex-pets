import Foundation
import SQLite3
import XCTest

@testable import MultiCodexPetsCore

final class AgentSessionMetadataTests: XCTestCase {
  private var home: URL!

  override func setUpWithError() throws {
    home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: home)
  }

  func testClaudeTitleAndStateMatchOnlyLivePID() throws {
    let file = home.appendingPathComponent(".claude/sessions/42.json")
    try write(["pid": 42, "sessionId": "chat-a", "name": "Fix login", "status": "idle"], to: file)
    let loader = AgentSessionMetadata(home: home, environment: [:])
    let sessions = loader.enrich([.init(id: 42, agent: .claude), .init(id: 43, agent: .claude)])
    let session = try XCTUnwrap(sessions.first { $0.pid == 42 })
    XCTAssertEqual(session.id, "claude:chat-a")
    XCTAssertEqual(session.title, "Fix login")
    XCTAssertEqual(session.activity, .waiting)
    XCTAssertNil(sessions.first { $0.pid == 43 }?.title)
    XCTAssertEqual(loader.enrich([]), [])
    try write(["pid": 99, "sessionId": "wrong", "name": "Wrong"], to: file)
    XCTAssertNil(loader.enrich([.init(id: 42, agent: .claude)]).first?.title)
  }

  func testMultipleCodexThreadsOnOnePIDKeepStableIdentities() throws {
    let base = home.appendingPathComponent(".codex")
    try database(
      base.appendingPathComponent("state_5.sqlite"),
      sql: """
        CREATE TABLE threads (id TEXT, title TEXT, rollout_path TEXT);
        INSERT INTO threads VALUES ('a','First','\(base.path)/sessions/a.jsonl');
        INSERT INTO threads VALUES ('b','Second','\(base.path)/sessions/b.jsonl');
        """)
    let a = base.appendingPathComponent("sessions/a.jsonl")
    let b = base.appendingPathComponent("sessions/b.jsonl")
    try write(["type": "event_msg", "payload": ["type": "task_started"]], to: a)
    try write(["type": "event_msg", "payload": ["type": "task_complete"]], to: b)
    let loader = AgentSessionMetadata(home: home, environment: [:])
    let sessions = loader.enrich([.init(id: 7, agent: .codex)], openFiles: [7: [a.path, b.path]])
    XCTAssertEqual(Set(sessions.map(\.id)), ["codex:a", "codex:b"])
    XCTAssertEqual(sessions.first { $0.id == "codex:a" }?.activity, .running)
    XCTAssertEqual(sessions.first { $0.id == "codex:b" }?.activity, .completed)
    try database(
      base.appendingPathComponent("state_5.sqlite"),
      sql:
        "ALTER TABLE threads ADD COLUMN name TEXT; UPDATE threads SET name = 'Renamed conversation' WHERE id = 'a';"
    )
    let renamed = loader.enrich([.init(id: 7, agent: .codex)], openFiles: [7: [a.path]])
    XCTAssertEqual(renamed.first?.title, "Renamed conversation")
    // The most recent saved thread must never be guessed for an unrelated process.
    XCTAssertNil(loader.enrich([.init(id: 8, agent: .codex)]).first?.title)
  }

  func testOrcaCLISeparatesTitlesAndStatesWithoutInventingPIDs() throws {
    let data = try JSONSerialization.data(withJSONObject: [
      "ok": true,
      "result": [
        "worktrees": [
          [
            "worktreeId": "workspace", "isArchived": false,
            "agents": [
              [
                "paneKey": "chat:a", "agentType": "codex", "conversationName": "Orca task",
                "activity": ["listed": true, "status": "done"],
              ],
              [
                "paneKey": "chat:b", "agentType": "claude", "conversationName": "Review task",
                "activity": ["listed": true, "status": "needs-approval"],
              ],
              ["paneKey": "chat:hidden", "agentType": "claude", "activity": ["listed": false]],
            ],
          ]
        ]
      ],
    ])
    let sessions = try XCTUnwrap(AgentSessionMetadata.orcaSessions(data))
    XCTAssertEqual(sessions.count, 2)
    XCTAssertEqual(sessions.first?.id, "orca:workspace:chat:a")
    XCTAssertEqual(sessions.first?.kind, .orca)
    XCTAssertEqual(sessions.first?.title, "Orca task")
    XCTAssertEqual(sessions.first?.activity, .completed)
    XCTAssertNil(sessions.first?.pid)
    XCTAssertEqual(sessions.last?.activity, .approval)
    XCTAssertNil(AgentSessionMetadata.orcaSessions(Data("{\"ok\":false}".utf8)))
  }

  func testOrcaSupportsAllListStatusesAndPreservesUnknownStates() throws {
    let cases: [(String, AgentActivity)] = [
      ("waiting", .waiting), ("blocked", .approval), ("permission", .approval),
      ("failed", .failed), ("unconfirmed", .unverified), ("working", .running),
      ("monitoring", .monitoring), ("interrupted", .interrupted),
      ("unverifiable", .unverified), ("done", .completed), ("idle", .waiting),
      ("future-state", .unknown),
    ]
    for (status, expected) in cases {
      let session = try orcaSession([
        "state": "working", "workingMode": "monitoring",
        "activity": ["listed": true, "status": status],
      ])
      XCTAssertEqual(session.activity, expected, status)
      XCTAssertEqual(session.rawActivity, status)
    }
    XCTAssertEqual(AgentActivity.monitoring.animationState, .review)
    XCTAssertEqual(AgentActivity.interrupted.animationState, .waiting)
    XCTAssertEqual(AgentActivity.unverified.animationState, .idle)
  }

  func testOrcaFallsBackToWorkingModeAndTurnOutcomeWithoutListActivity() throws {
    XCTAssertEqual(try orcaSession([
      "state": "working", "workingMode": "monitoring",
    ]).activity, .monitoring)
    for (outcome, expected) in [
      ("success", AgentActivity.completed), ("failure", .failed),
      ("cancellation", .interrupted), ("unconfirmed", .unverified),
    ] {
      XCTAssertEqual(try orcaSession([
        "state": "done", "mainAgent": ["state": "done", "outcome": outcome],
      ]).activity, expected, outcome)
    }
    XCTAssertEqual(try orcaSession([
      "state": "done", "interrupted": true,
    ]).activity, .interrupted)
  }

  private func orcaSession(_ fields: [String: Any]) throws -> DetectedAgentSession {
    var agent = fields
    agent["paneKey"] = "chat:test"
    agent["agentType"] = "codex"
    let data = try JSONSerialization.data(withJSONObject: [
      "ok": true, "result": ["worktrees": [["worktreeId": "test", "agents": [agent]]]],
    ])
    return try XCTUnwrap(AgentSessionMetadata.orcaSessions(data)?.first)
  }

  func testAntigravityActiveConversationsAreDeduplicatedAndIdleHistoryExcluded() throws {
    let db = home.appendingPathComponent(".gemini/antigravity/conversation_summaries.db")
    try database(
      db,
      sql: """
        CREATE TABLE conversation_summaries (conversation_id TEXT, title TEXT, status TEXT,
          killed INTEGER, not_fully_idle INTEGER);
        INSERT INTO conversation_summaries VALUES ('a','Build UI','CASCADE_RUN_STATUS_RUNNING',0,1);
        INSERT INTO conversation_summaries VALUES ('old','Old title','CASCADE_RUN_STATUS_IDLE',0,0);
        INSERT INTO conversation_summaries VALUES ('dead','Stopped','CASCADE_RUN_STATUS_RUNNING',1,1);
        """)
    let sessions = AgentSessionMetadata(home: home, environment: [:]).enrich([
      .init(id: 1, agent: .antigravity), .init(id: 2, agent: .antigravity),
    ])
    XCTAssertEqual(sessions.count, 1)
    XCTAssertEqual(sessions.first?.title, "Build UI")
    XCTAssertEqual(sessions.first?.activity, .running)
  }

  func testUnknownStatesAndPartialLogsNeverBecomeGenerating() throws {
    XCTAssertEqual(AgentSessionMetadata.activity("new-provider-state"), .unknown)
    let log = home.appendingPathComponent("log.jsonl")
    try Data("{partial".utf8).write(to: log)
    XCTAssertEqual(AgentSessionMetadata.codexActivity(log), .unknown)
    try Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n{partial".utf8)
      .write(to: log)
    XCTAssertEqual(AgentSessionMetadata.codexActivity(log), .completed)
  }

  func testRoutingUsesActivityAndKeepsUnavailableAssignmentsIdle() {
    var routing = SessionRouting()
    let sessions = [DetectedAgentSession(id: "codex:a", agent: .codex, activity: .approval)]
    routing.mode = .single
    routing.singleSessionID = "codex:a"
    XCTAssertEqual(routing.states(for: ["pet"], sessions: sessions), [.review])
    XCTAssertEqual(routing.states(for: ["pet"], sessions: []), [.idle])
    XCTAssertEqual(AgentActivity.unknown.animationState, .idle)
    XCTAssertEqual(AgentActivity.failed.animationState, .failed)
  }

  func testProcessOnlyEntriesAreDiagnosticsButUnknownConversationsStayAssignable() {
    let background = DetectedAgentSession(id: 23161, agent: .codex)
    let conversation = DetectedAgentSession(id: "codex:chat", agent: .codex, title: "Task")
    XCTAssertFalse(background.hasConversationIdentity)
    XCTAssertTrue(conversation.hasConversationIdentity)
    XCTAssertEqual(conversation.activity, .unknown)
    XCTAssertEqual([background, conversation].filter(\.hasConversationIdentity), [conversation])
  }

  func testCodexLifecycleSurvivesLongTurnsAndIncrementalUpdates() throws {
    let log = home.appendingPathComponent("long.jsonl")
    var data = Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\"}}\n".utf8)
    data.append(Data(repeating: 120, count: 400_000))
    data.append(10)
    try data.write(to: log)
    let reader = CodexActivityReader()
    XCTAssertEqual(reader.activity(at: log), .running)
    XCTAssertEqual(reader.activity(at: log), .running)
    let handle = try FileHandle(forWritingTo: log)
    try handle.seekToEnd()
    try handle.write(
      contentsOf: Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"}}\n".utf8))
    try handle.close()
    XCTAssertEqual(reader.activity(at: log), .completed)
    try Data("{}\n".utf8).write(to: log)
    XCTAssertEqual(reader.activity(at: log), .unknown)
  }

  func testFindsNewerCodexDatabaseVersions() throws {
    let base = home.appendingPathComponent(".codex")
    let rollout = base.appendingPathComponent("sessions/chat.jsonl")
    try write(["type": "event_msg", "payload": ["type": "task_started"]], to: rollout)
    try database(
      base.appendingPathComponent("state_6.sqlite"),
      sql:
        "CREATE TABLE threads (id TEXT, title TEXT, rollout_path TEXT); INSERT INTO threads VALUES ('new','New version','\(rollout.path)');"
    )
    let sessions = AgentSessionMetadata(home: home, environment: [:]).enrich(
      [.init(id: 1, agent: .codex)], openFiles: [1: [rollout.path]])
    XCTAssertEqual(sessions.first?.title, "New version")
    XCTAssertEqual(sessions.first?.activity, .running)
  }

  private func write(_ json: [String: Any], to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var data = try JSONSerialization.data(withJSONObject: json)
    data.append(10)
    try data.write(to: url)
  }

  private func database(_ url: URL, sql: String) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
  }
}
