import CoreGraphics
import Foundation
import ImageIO

public enum PetImageDecoder {
  public static func image(for pet: PetPackage, frame: AnimationFrame? = nil) -> CGImage? {
    return autoreleasepool { () -> CGImage? in
      let source: CGImageSource?
      if let data = pet.spritesheetData {
        source = CGImageSourceCreateWithData(data as CFData, nil)
      } else {
        source = CGImageSourceCreateWithURL(pet.spritesheetURL as CFURL, nil)
      }
      guard let source, let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
        sheet.width == PetAtlas.width, sheet.height == pet.spriteVersion.height
      else { return nil }
      if let frame { return cell(in: sheet, frame: frame) }
      return bitmapCopy(sheet)
    }
  }

  public static func cell(in sheet: CGImage, frame: AnimationFrame) -> CGImage? {
    guard sheet.width == PetAtlas.width,
      frame.columnIndex >= 0, frame.columnIndex < PetAtlas.columns,
      frame.rowIndex >= 0, frame.rowIndex < sheet.height / PetAtlas.cellHeight,
      let cell = sheet.cropping(to: CGRect(
        x: frame.columnIndex * PetAtlas.cellWidth, y: frame.rowIndex * PetAtlas.cellHeight,
        width: PetAtlas.cellWidth, height: PetAtlas.cellHeight))
    else { return nil }
    return bitmapCopy(cell)
  }

  private static func bitmapCopy(_ image: CGImage) -> CGImage? {
    guard let context = CGContext(data: nil, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: image.width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    // Own decoded pixels so each draw neither invokes a codec nor converts the whole atlas.
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
  }

}
