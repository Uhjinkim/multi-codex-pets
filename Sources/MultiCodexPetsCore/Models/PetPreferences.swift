import Foundation

public struct PetPreferences: Codable {
  public var frame: CGRect?
  public var screenID: UInt32?
  public var positionLocked = false
  public var muted = false
  public var customName: String?
  public var nameLabel: PetNameLabel?
  public var cursorTrackingMode: PetCursorTrackingMode?
  public var soundVolume: Float?
  public var scale: Double?
  public var directionLayout: SavedPetDirectionLayout?

  public var resolvedSoundVolume: Float {
    guard let soundVolume, soundVolume.isFinite else { return 1 }
    return min(max(soundVolume, 0), 1)
  }

  public init() {}

  public func resolvedScale(default defaultScale: Double) -> Double {
    let value = scale ?? defaultScale
    return min(max(value.isFinite ? value : 1, 0.5), 2)
  }

  public mutating func setCustomName(_ value: String) {
    let name = value.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }.joined(separator: " ")
    customName = name.isEmpty ? nil : name
  }

  public func displayName(fallback: String) -> String {
    customName ?? fallback
  }
}

public enum PetCursorTrackingMode: String, Codable, CaseIterable {
  case off = "Off"
  case always = "Always"
  case whenShaken = "When Shaken"
}

public enum PetPlacement {
  public static func fitted(_ frame: CGRect, to screen: CGRect) -> CGRect {
    CGRect(
      x: max(screen.minX, min(frame.minX, screen.maxX - frame.width)),
      y: max(screen.minY, min(frame.minY, screen.maxY - frame.height)),
      width: frame.width, height: frame.height)
  }
}
