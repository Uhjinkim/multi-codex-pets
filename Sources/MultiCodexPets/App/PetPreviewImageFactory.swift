import AppKit
import MultiCodexPetsCore

enum PetPreviewImageFactory {
  static func image(for pet: PetPackage) -> NSImage? {
    guard let frame = PetImageDecoder.image(for: pet,
      frame: AnimationFrame(rowIndex: 0, columnIndex: 0, frameDurationMs: 0))
    else { return nil }

    // Keep the original cell pixels; views downsample for their actual Retina size.
    let preview = NSImage(
      cgImage: frame,
      size: NSSize(width: PetAtlas.cellWidth, height: PetAtlas.cellHeight))
    preview.isTemplate = false
    return preview
  }
}
