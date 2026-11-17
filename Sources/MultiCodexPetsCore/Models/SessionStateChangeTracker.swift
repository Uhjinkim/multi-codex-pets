import Foundation

public struct SessionStateChangeTracker {
  private struct Observation {
    let sessionID: String
    var activity: AgentActivity
  }
  private var previous: [String: Observation] = [:]

  public init() {}

  public mutating func reset() { previous.removeAll() }

  public mutating func changedPets(assignments: [String: DetectedAgentSession], enabled: Bool)
    -> [String]
  {
    guard enabled else {
      reset()
      return []
    }
    var next: [String: Observation] = [:]
    var changed: [String] = []
    for (petID, session) in assignments {
      var observation = Observation(sessionID: session.id, activity: session.activity)
      if let old = previous[petID], old.sessionID == session.id {
        if session.activity == .unknown {
          observation.activity = old.activity
        } else if old.activity != .unknown, old.activity != session.activity {
          changed.append(petID)
        }
      }
      next[petID] = observation
    }
    previous = next
    return changed.sorted()
  }
}
