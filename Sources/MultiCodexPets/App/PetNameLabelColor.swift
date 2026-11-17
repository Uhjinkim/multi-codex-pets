import AppKit
import MultiCodexPetsCore

extension PetNameLabel {
  var backgroundColor: NSColor {
    NSColor(srgbRed: CGFloat((backgroundRGB >> 16) & 255) / 255,
      green: CGFloat((backgroundRGB >> 8) & 255) / 255,
      blue: CGFloat(backgroundRGB & 255) / 255, alpha: resolvedBackgroundOpacity)
  }

  var color: NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
      green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }
}
