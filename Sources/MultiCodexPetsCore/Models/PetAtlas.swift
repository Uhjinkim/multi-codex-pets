import CoreGraphics
import Foundation

public enum PetAtlas {
  public static let columns = 8
  public static let rows = 9
  public static let cellWidth = 192
  public static let cellHeight = 208
  public static let width = columns * cellWidth
  public static let height = rows * cellHeight
}

public enum PetSpriteVersion: Int, Equatable {
  case v1 = 1
  case v2 = 2

  public var rows: Int { self == .v1 ? 9 : 11 }
  public var height: Int { rows * PetAtlas.cellHeight }

  public init?(dimensions: ImageDimensions) {
    guard dimensions.width == PetAtlas.width else { return nil }
    switch dimensions.height {
    case PetSpriteVersion.v1.height: self = .v1
    case PetSpriteVersion.v2.height: self = .v2
    default: return nil
    }
  }

  /// Screen coordinates: positive Y points up, and direction zero is 12 o'clock.
  public func lookFrame(pointer: CGPoint, center: CGPoint, deadzone: CGFloat) -> AnimationFrame? {
    guard self == .v2 else { return nil }
    let dx = pointer.x - center.x
    let dy = pointer.y - center.y
    guard dx.isFinite, dy.isFinite, hypot(dx, dy) > max(0, deadzone) else { return nil }

    let angle = atan2(dx, dy)
    let direction = (Int((angle / (.pi / 8)).rounded()) + 16) % 16
    return AnimationFrame(
      rowIndex: 9 + direction / PetAtlas.columns,
      columnIndex: direction % PetAtlas.columns,
      frameDurationMs: 0
    )
  }

  public func sourceRect(for frame: AnimationFrame) -> CGRect {
    let x = frame.columnIndex * PetAtlas.cellWidth
    let rowBottom = (frame.rowIndex + 1) * PetAtlas.cellHeight
    let y = self.height - rowBottom
    return CGRect(
      x: CGFloat(x),
      y: CGFloat(y),
      width: CGFloat(PetAtlas.cellWidth),
      height: CGFloat(PetAtlas.cellHeight)
    )
  }
}
