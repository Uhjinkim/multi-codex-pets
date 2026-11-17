import Foundation

public enum AgentSession: String, CaseIterable {
  case codex = "Codex"
  case claude = "Claude"
  case orca = "Orca"
  case antigravity = "Antigravity"

  public var animationState: AnimationState {
    switch self {
    case .codex: return .running
    case .claude: return .review
    case .orca: return .waving
    case .antigravity: return .jumping
    }
  }

  /// Reads `ps -axo pid=,ppid=,comm=` output, without prompts or command arguments.
  public static func detected(in processListing: String) -> [AgentSession] {
    let found = Set(sessions(in: processListing).map(\.kind))
    return allCases.filter { found.contains($0) }
  }

  public static func sessions(in processListing: String) -> [DetectedAgentSession] {
    let processes = processListing.split(separator: "\n").compactMap {
      line -> (Int, Int, String)? in
      let fields = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
      guard fields.count == 3, let pid = Int(fields[0]), let parent = Int(fields[1]) else {
        return nil
      }
      return (pid, parent, String(fields[2]))
    }
    var parents: [Int: Int] = [:]
    var orcaPIDs = Set<Int>()
    for (pid, parent, executable) in processes {
      parents[pid] = parent
      if executable.lowercased().contains("/orca.app/contents/")
        || URL(fileURLWithPath: executable).lastPathComponent.lowercased() == "orca"
        || ["orca-terminal-host", "orca agents"].contains(
          URL(fileURLWithPath: executable).lastPathComponent.lowercased())
      {
        orcaPIDs.insert(pid)
      }
    }

    var found: [DetectedAgentSession] = []
    for (pid, parent, executable) in processes {
      let name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
      let provider: AgentSession
      if executable.contains("/Applications/Claude.app/Contents/MacOS/") { continue }
      switch name {
      case "codex": provider = .codex
      case "claude": provider = .claude
      case "antigravity", "language_server_macos_arm", "language_server_macos":
        provider = .antigravity
      default:
        if executable.contains("/claude/versions/") {
          provider = .claude
        } else {
          continue
        }
      }
      var ancestor = parent
      var visited: Set<Int> = [pid]
      var isOrcaSession = false
      while ancestor > 1, visited.insert(ancestor).inserted {
        if orcaPIDs.contains(ancestor) {
          isOrcaSession = true
          break
        }
        ancestor = parents[ancestor] ?? 0
      }
      found.append(DetectedAgentSession(id: pid, agent: provider, hostedByOrca: isOrcaSession))
    }
    return found.sorted {
      if $0.kind != $1.kind {
        return allCases.firstIndex(of: $0.kind)! < allCases.firstIndex(of: $1.kind)!
      }
      return $0.id < $1.id
    }
  }
}

public enum AgentActivity: String, CaseIterable {
  case running = "Generating"
  case monitoring = "Monitoring Background Tasks"
  case interrupted = "Interrupted"
  case unverified = "Status Unverified"
  case approval = "Awaiting Approval"
  case waiting = "Waiting for Input"
  case completed = "Completed"
  case failed = "Failed"
  case unknown = "Status Unknown"

  public var animationState: AnimationState {
    switch self {
    case .running: return .running
    case .monitoring: return .review
    case .interrupted: return .waiting
    case .unverified: return .idle
    case .approval: return .review
    case .waiting: return .waiting
    case .completed: return .waving
    case .failed: return .failed
    case .unknown: return .idle
    }
  }
}

public struct DetectedAgentSession: Equatable, Identifiable {
  public let id: String
  public let pid: Int?
  public let agent: AgentSession
  public let hostedByOrca: Bool
  public let title: String?
  public let activity: AgentActivity
  public let rawActivity: String?

  public init(id: Int, agent: AgentSession, hostedByOrca: Bool = false) {
    self.init(id: "process:\(id)", pid: id, agent: agent, hostedByOrca: hostedByOrca)
  }

  public init(
    id: String, pid: Int? = nil, agent: AgentSession, hostedByOrca: Bool = false,
    title: String? = nil, activity: AgentActivity = .unknown, rawActivity: String? = nil
  ) {
    self.id = id
    self.pid = pid
    self.agent = agent
    self.hostedByOrca = hostedByOrca
    self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    self.activity = activity
    self.rawActivity = rawActivity
  }

  public var hasConversationIdentity: Bool { !id.hasPrefix("process:") }
  public var kind: AgentSession { hostedByOrca ? .orca : agent }
  public var animationState: AnimationState { activity.animationState }
  public var displayName: String {
    let name = title ?? "Untitled \(agent.rawValue) session"
    return "\(activity.rawValue) · \(name)"
  }
}

extension String {
  fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}

public struct SessionRouting: Codable {
  public enum Mode: String, CaseIterable, Codable {
    case automatic = "Distribute Automatically"
    case single = "Use One Session"
    case perPet = "Assign per Pet"
  }

  public var mode: Mode = .automatic
  public var singleSessionID: String?
  // Persist provider conversation identities; never restore a process-only PID assignment.
  public var sessionIDsByPet: [String: String] = [:]

  public init() {}

  public func states(for petIDs: [String], sessions: [DetectedAgentSession]) -> [AnimationState] {
    resolvedSessions(for: petIDs, sessions: sessions).map { $0?.animationState ?? .idle }
  }

  public func resolvedSessions(for petIDs: [String], sessions: [DetectedAgentSession])
    -> [DetectedAgentSession?]
  {
    let kinds = AgentSession.allCases.filter { kind in sessions.contains { $0.kind == kind } }
    return petIDs.enumerated().map { index, petID in
      let automatic = kinds.isEmpty ? nil : sessions.first { $0.kind == kinds[index % kinds.count] }
      switch mode {
      case .automatic: return automatic
      case .single: return sessions.first { $0.id == singleSessionID }
      case .perPet:
        guard let id = sessionIDsByPet[petID] else { return automatic }
        return sessions.first { $0.id == id }
      }
    }
  }
}
