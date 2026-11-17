import Foundation

public struct SessionNotificationPolicy {
  private struct Key: Hashable {
    let petID: String
    let notificationKey: String
  }
  private var lastPlayed: [Key: Date] = [:]
  public init() {}
  public mutating func reset() { lastPlayed.removeAll() }

  public mutating func shouldNotify(
    petID: String, activity: AgentActivity,
    allowed: Set<AgentActivity>, cooldown: TimeInterval, now: Date = Date()
  ) -> Bool {
    guard activity != .unknown, allowed.contains(activity) else { return false }
    return shouldNotify(petID: petID, notificationKey: activity.rawValue, cooldown: cooldown, now: now)
  }

  public mutating func shouldNotify(
    petID: String, notificationKey: String, cooldown: TimeInterval, now: Date = Date()
  ) -> Bool {
    let key = Key(petID: petID, notificationKey: notificationKey)
    if let last = lastPlayed[key] {
      let elapsed = now.timeIntervalSince(last)
      if elapsed >= 0, elapsed < max(0, cooldown) { return false }
    }
    lastPlayed[key] = now
    return true
  }
}
