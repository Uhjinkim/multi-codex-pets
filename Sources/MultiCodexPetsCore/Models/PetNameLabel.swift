import Foundation

public enum PetNameLabelPosition: String, CaseIterable, Codable {
  case hidden = "Hidden"
  case above = "Above Pet"
  case below = "Below Pet"
}

public struct PetNameLabel: Codable {
  public var position = PetNameLabelPosition.hidden
  public var fontSize: Double = 12
  public var colorHex = "FFFFFF"

  public init() {}

  public var resolvedFontSize: Double {
    fontSize.isFinite ? min(max(fontSize, 9), 28) : 12
  }

  public var rgb: UInt32 {
    colorHex.count == 6 ? UInt32(colorHex, radix: 16) ?? 0xFFFFFF : 0xFFFFFF
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
