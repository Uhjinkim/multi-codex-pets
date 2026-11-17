import Foundation

public struct SessionAnimations: Codable {
  public var overrides: [String: String] = [:]

  public init() {}

  public func animation(for activity: AgentActivity?) -> AnimationState {
    guard let activity else { return .idle }
    return overrides[activity.rawValue].flatMap(AnimationState.init(rawValue:))
      ?? activity.animationState
  }
}
