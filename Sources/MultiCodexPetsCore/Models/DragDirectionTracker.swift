import Foundation

public struct DragDirectionTracker {
  private var referenceX: CGFloat
  public private(set) var state: AnimationState?

  public init(startX: CGFloat) {
    referenceX = startX
  }

  public mutating func update(x: CGFloat) -> AnimationState? {
    guard x.isFinite else { return state }
    let distance = x - referenceX
    if distance > 4 {
      state = .runningRight
      referenceX = x
    } else if distance < -4 {
      state = .runningLeft
      referenceX = x
    } else if state == .runningRight {
      referenceX = max(referenceX, x)
    } else if state == .runningLeft {
      referenceX = min(referenceX, x)
    }
    return state
  }
}
