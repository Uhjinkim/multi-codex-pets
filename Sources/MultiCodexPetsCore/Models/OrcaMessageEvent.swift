import Foundation

public struct OrcaMessageEvent: Equatable {
  public static let soundKey = "orca-message-sent"
  public let id: String
  public let senderSessionID: String
  public let type: String
}

public struct OrcaMessageTracker {
  private struct Envelope: Decodable {
    let ok: Bool
    let result: Result
    struct Result: Decodable { let messages: [Message] }
  }
  private struct Message: Decodable {
    let id: String
    let sequence: Int64
    let type: String
    let from_handle: String
    let to_handle: String
    let sender_pane_key: String?
  }
  private var lastSequence: Int64?

  public init() {}
  public mutating func reset() { lastSequence = nil }

  public mutating func observe(_ data: Data?, sessions: [DetectedAgentSession]) -> [OrcaMessageEvent]? {
    guard let data, let envelope = try? JSONDecoder().decode(Envelope.self, from: data), envelope.ok else {
      reset()
      return nil
    }
    let rows = envelope.result.messages
    let latest = rows.map(\.sequence).max() ?? 0
    let previous = lastSequence
    lastSequence = latest
    guard let previous, latest >= previous else { return [] }
    var seen = Set<String>()
    return rows.sorted { $0.sequence < $1.sequence }.compactMap { row in
      guard row.sequence > previous, !row.id.isEmpty, seen.insert(row.id).inserted,
        ["status", "handoff", "dispatch", "question"].contains(row.type),
        !row.to_handle.isEmpty, row.from_handle != row.to_handle else { return nil }
      let candidates: [DetectedAgentSession]
      if let pane = row.sender_pane_key, !pane.isEmpty {
        candidates = sessions.filter { $0.hostedByOrca && $0.id.hasSuffix(":" + pane) }
      } else if row.from_handle.hasPrefix("orca_session_id:") {
        let identity = row.from_handle.dropFirst("orca_session_id:".count)
        guard !identity.isEmpty else { return nil }
        candidates = sessions.filter {
          $0.hostedByOrca && $0.id.contains(":structured-agent-session-\(identity):")
        }
      } else { return nil }
      guard candidates.count == 1, let sender = candidates.first else { return nil }
      return OrcaMessageEvent(id: row.id, senderSessionID: sender.id, type: row.type)
    }
  }
}
