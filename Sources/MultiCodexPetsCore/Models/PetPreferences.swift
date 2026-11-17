import Foundation

public struct PetPreferences: Codable {
  public var frame: CGRect?
  public var screenID: UInt32?
  public var positionLocked = false
  public var muted = false
  public var customName: String?
  public var nameLabel: PetNameLabel?

  public init() {}

  public mutating func setCustomName(_ value: String) {
    let name = value.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }.joined(separator: " ")
    customName = name.isEmpty ? nil : name
  }

  public func displayName(fallback: String) -> String {
    customName ?? fallback
  }
}

public enum PetPlacement {
  public static func fitted(_ frame: CGRect, to screen: CGRect) -> CGRect {
    CGRect(
      x: max(screen.minX, min(frame.minX, screen.maxX - frame.width)),
      y: max(screen.minY, min(frame.minY, screen.maxY - frame.height)),
      width: frame.width, height: frame.height)
  }
}
