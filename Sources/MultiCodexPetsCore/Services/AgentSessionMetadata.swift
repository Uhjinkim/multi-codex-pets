import Foundation
import SQLite3

/// Reads session metadata only. Provider files are never changed.
public final class AgentSessionMetadata {
  private let codexActivityReader = CodexActivityReader()
  public private(set) var diagnostics: [String] = []
  private let home: URL
  private let claudeHome: URL

  public init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.home = home
    claudeHome =
      environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
      ?? home.appendingPathComponent(".claude")
  }

  public func enrich(_ processes: [DetectedAgentSession], openFiles: [Int: [String]] = [:])
    -> [DetectedAgentSession]
  {
    diagnostics.removeAll()
    codexActivityReader.retain(paths: Set(openFiles.values.flatMap { $0 }))
    var result: [DetectedAgentSession] = []
    var seen = Set<String>()
    for process in processes {
      let sessions: [DetectedAgentSession]
      switch process.agent {
      case .claude: sessions = claudeSessions(process)
      case .codex: sessions = codexSessions(process, paths: openFiles[process.pid ?? -1] ?? [])
      case .antigravity: sessions = antigravitySessions(process)
      case .orca: sessions = []
      }
      for session in sessions.isEmpty ? [process] : sessions where seen.insert(session.id).inserted
      {
        result.append(session)
      }
    }
    return result.sorted {
      if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
      if $0.activity != $1.activity {
        return AgentActivity.allCases.firstIndex(of: $0.activity)!
          < AgentActivity.allCases.firstIndex(of: $1.activity)!
      }
      return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
    }
  }

  private func claudeSessions(_ process: DetectedAgentSession) -> [DetectedAgentSession] {
    guard let pid = process.pid,
      let data = try? Data(contentsOf: claudeHome.appendingPathComponent("sessions/\(pid).json")),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      (json["pid"] as? Int) == pid, let id = json["sessionId"] as? String
    else {
      diagnostics.append("Claude session metadata is unavailable for some processes.")
      return []
    }
    return [
      DetectedAgentSession(
        id: "claude:\(id)", pid: pid, agent: .claude,
        hostedByOrca: process.hostedByOrca, title: json["name"] as? String,
        activity: Self.activity(json["status"] as? String), rawActivity: json["status"] as? String)
    ]
  }

  private func codexSessions(_ process: DetectedAgentSession, paths: [String])
    -> [DetectedAgentSession]
  {
    let rollouts = Set(paths.filter { $0.contains("/sessions/") && $0.hasSuffix(".jsonl") })
    return rollouts.compactMap { path in
      // The open rollout is evidence of association; recency alone never assigns a title to a PID.
      let url = URL(fileURLWithPath: path)
      guard let sessionsRange = path.range(of: "/sessions/", options: .backwards) else {
        return nil
      }
      let base = URL(fileURLWithPath: String(path[..<sessionsRange.lowerBound]))
      let candidates =
        ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil))
        ?? [])
        .compactMap { url -> (URL, Int)? in
          let name = url.lastPathComponent
          guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
            let version = Int(name.dropFirst(6).dropLast(7))
          else { return nil }
          return (url, version)
        }.sorted { $0.1 > $1.1 }
      var rows: [[String]] = []
      for (database, _) in candidates {
        rows = Self.query(
          database,
          sql:
            "SELECT id, COALESCE(NULLIF(name, ''), title) FROM threads WHERE rollout_path = ? LIMIT 1",
          values: [path])
        if rows.isEmpty {
          rows = Self.query(
            database, sql: "SELECT id, title FROM threads WHERE rollout_path = ? LIMIT 1",
            values: [path])
        }
        if !rows.isEmpty { break }
      }
      guard let row = rows.first, row.count == 2 else {
        diagnostics.append("Codex title database is unavailable or its schema has changed.")
        return nil
      }
      return DetectedAgentSession(
        id: "codex:\(row[0])", pid: process.pid, agent: .codex,
        hostedByOrca: process.hostedByOrca, title: row[1],
        activity: codexActivityReader.activity(at: url))
    }
  }

  public static func orcaSessions(_ data: Data) -> [DetectedAgentSession]? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      json["ok"] as? Bool == true,
      let result = json["result"] as? [String: Any],
      let workspaces = result["worktrees"] as? [[String: Any]]
    else { return nil }
    var sessions: [DetectedAgentSession] = []
    for workspace in workspaces where workspace["isArchived"] as? Bool != true {
      guard let workspaceID = workspace["worktreeId"] as? String,
        let agents = workspace["agents"] as? [[String: Any]]
      else { continue }
      for row in agents {
        guard let pane = row["paneKey"] as? String,
          let provider = row["agentType"] as? String,
          let agent = AgentSession.allCases.first(where: {
            $0.rawValue.lowercased() == provider.lowercased()
          })
        else { continue }
        let activity = row["activity"] as? [String: Any]
        guard activity?["listed"] as? Bool != false else { continue }
        let title =
          row["conversationName"] as? String
          ?? row["displayName"] as? String ?? activity?["title"] as? String
        var status = activity?["status"] as? String
        if status == nil {
          status = row["state"] as? String
          if status == "working", row["workingMode"] as? String == "monitoring" {
            status = "monitoring"
          } else if status == "done" {
            let mainAgent = row["mainAgent"] as? [String: Any]
            switch mainAgent?["outcome"] as? String {
            case "failure": status = "failed"
            case "cancellation": status = "interrupted"
            case "unconfirmed": status = "unconfirmed"
            default:
              if row["interrupted"] as? Bool == true { status = "interrupted" }
            }
          }
        }
        sessions.append(
          DetectedAgentSession(
            id: "orca:\(workspaceID):\(pane)", agent: agent,
            hostedByOrca: true, title: title,
            activity: Self.activity(status), rawActivity: status))
      }
    }
    return sessions
  }

  private func antigravitySessions(_ process: DetectedAgentSession) -> [DetectedAgentSession] {
    let db = home.appendingPathComponent(".gemini/antigravity/conversation_summaries.db")
    let rows = Self.query(
      db,
      sql: """
        SELECT conversation_id, title, status FROM conversation_summaries
        WHERE killed = 0 AND not_fully_idle = 1
        """)
    return rows.filter { $0.count == 3 }.map { row in
      DetectedAgentSession(
        id: "antigravity:\(row[0])", pid: process.pid, agent: .antigravity,
        hostedByOrca: process.hostedByOrca, title: row[1], activity: Self.activity(row[2]),
        rawActivity: row[2])
    }
  }

  public static func activity(_ value: String?) -> AgentActivity {
    switch value?.lowercased() {
    case "running", "generating", "working", "busy", "in_progress", "thinking", "tool_running",
      "cascade_run_status_running":
      return .running
    case "monitoring": return .monitoring
    case "interrupted": return .interrupted
    case "unconfirmed", "unverifiable": return .unverified
    case "approval", "blocked", "awaiting_approval", "permission", "permission_prompt", "needs-approval",
      "needs_approval":
      return .approval
    case "idle", "waiting", "waiting_for_input", "needs-input", "needs_input",
      "cascade_run_status_idle":
      return .waiting
    case "completed", "done", "success": return .completed
    case "error", "failed", "failure": return .failed
    default: return .unknown
    }
  }

  public static func codexActivity(_ url: URL) -> AgentActivity {
    CodexActivityReader().activity(at: url)
  }

  private static func query(_ url: URL, sql: String, values: [String] = []) -> [[String]] {
    var db: OpaquePointer?
    guard
      sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK
    else {
      if let db { sqlite3_close(db) }
      return []
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 100)
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() {
      _ = value.withCString {
        sqlite3_bind_text(
          statement, Int32(index + 1), $0, -1,
          unsafeBitCast(-1, to: sqlite3_destructor_type.self))
      }
    }
    var rows: [[String]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      rows.append(
        (0..<sqlite3_column_count(statement)).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        })
    }
    return rows
  }
}
