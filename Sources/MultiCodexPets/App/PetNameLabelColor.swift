import AppKit
import MultiCodexPetsCore

extension PetNameLabel {
  var color: NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
      green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }
}
