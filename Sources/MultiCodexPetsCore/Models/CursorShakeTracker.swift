import Foundation

// shortcut: detects shake motion, not macOS enlargement; use a system event if a public one becomes available.
public struct CursorShakeTracker {
  private var reference: CGPoint?
  private var direction = CGPoint.zero
  private var reversals: [TimeInterval] = []
  private var lastUpdate: TimeInterval?
  private var lookUntil = -TimeInterval.infinity

  public init() {}

  public mutating func update(point: CGPoint, now: TimeInterval) -> Bool {
    guard point.x.isFinite, point.y.isFinite, now.isFinite else {
      self = Self()
      return false
    }
    if let lastUpdate, now < lastUpdate || now - lastUpdate > 0.25 { self = Self() }
    lastUpdate = now
    guard let reference else {
      self.reference = point
      return false
    }
    let delta = CGPoint(x: point.x - reference.x, y: point.y - reference.y)
    let distance = hypot(delta.x, delta.y)
    if distance > 400 {
      self = Self()
      self.reference = point
      lastUpdate = now
      return false
    }
    if distance >= 24 {
      if delta.x * direction.x + delta.y * direction.y < 0 {
        reversals.removeAll { now - $0 > 0.6 }
        reversals.append(now)
        if reversals.count >= 3 {
          lookUntil = now + 2
          reversals.removeAll()
        }
      }
      direction = delta
      self.reference = point
    }
    return now < lookUntil
  }
}
