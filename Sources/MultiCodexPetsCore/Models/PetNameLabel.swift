import Foundation

public enum PetNameLabelPosition: String, CaseIterable, Codable {
  case hidden = "Hidden"
  case above = "Above Pet"
  case below = "Below Pet"
}

public struct PetNameLabel: Codable, Equatable {
  public var position = PetNameLabelPosition.hidden
  public var fontSize: Double = 12
  public var colorHex = "FFFFFF"
  public var backgroundColorHex: String?
  public var backgroundOpacity: Double?

  public init() {}

  public var resolvedFontSize: Double {
    fontSize.isFinite ? min(max(fontSize, 9), 28) : 12
  }

  public var rgb: UInt32 {
    colorHex.count == 6 ? UInt32(colorHex, radix: 16) ?? 0xFFFFFF : 0xFFFFFF
  }

  public var backgroundRGB: UInt32 {
    guard let hex = backgroundColorHex, hex.count == 6 else { return 0 }
    return UInt32(hex, radix: 16) ?? 0
  }

  public var resolvedBackgroundOpacity: Double {
    guard let value = backgroundOpacity, value.isFinite else { return 0.65 }
    return min(max(value, 0), 1)
  }

  public func frame(pet: CGRect, size: CGSize, screen: CGRect) -> CGRect {
    let above = CGRect(x: pet.midX - size.width / 2, y: pet.maxY + 3,
      width: size.width, height: size.height)
    let below = CGRect(x: above.minX, y: pet.minY - size.height - 3,
      width: size.width, height: size.height)
    let preferred = position == .above ? above : below
    let alternate = position == .above ? below : above
    let fitsVertically = preferred.minY >= screen.minY && preferred.maxY <= screen.maxY
    return PetPlacement.fitted(fitsVertically ? preferred : alternate, to: screen)
  }
}
