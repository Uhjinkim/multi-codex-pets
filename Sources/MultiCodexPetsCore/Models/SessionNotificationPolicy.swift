import Foundation

public struct SessionNotificationPolicy {
  private struct Key: Hashable {
    let petID: String
    let activity: AgentActivity
  }
  private var lastPlayed: [Key: Date] = [:]
  public init() {}
  public mutating func reset() { lastPlayed.removeAll() }

  public mutating func shouldNotify(
    petID: String, activity: AgentActivity,
    allowed: Set<AgentActivity>, cooldown: TimeInterval, now: Date = Date()
  ) -> Bool {
    guard activity != .unknown, allowed.contains(activity) else { return false }
    let key = Key(petID: petID, activity: activity)
    if let last = lastPlayed[key] {
      let elapsed = now.timeIntervalSince(last)
      if elapsed >= 0, elapsed < max(0, cooldown) { return false }
    }
    lastPlayed[key] = now
    return true
  }
}
