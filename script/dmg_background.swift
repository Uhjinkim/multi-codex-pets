import AppKit

guard CommandLine.arguments.count == 3 else {
  fatalError("Usage: swift dmg_background.swift <output.png> <app-bundle>")
}
let width = 720
let height = 460
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2, pixelsHigh: height * 2,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let ink = NSColor(red: 0.15, green: 0.22, blue: 0.22, alpha: 1)
let secondary = NSColor(red: 0.34, green: 0.39, blue: 0.38, alpha: 1)
func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight,
  color: NSColor, width: CGFloat = 620, centered: Bool = false) {
  let style = NSMutableParagraphStyle()
  style.alignment = centered ? .center : .left
  (value as NSString).draw(in: NSRect(x: x, y: CGFloat(height) - top - size * 1.6,
    width: width, height: size * 1.6), withAttributes: [
      .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
      .paragraphStyle: style])
}
text("Multi Codex Pets", x: 48, top: 36, size: 29, weight: .semibold, color: ink)
text("작은 친구들을 데스크톱으로.", x: 48, top: 85, size: 17, weight: .medium, color: ink)
text("앱을 Applications 폴더로 드래그해서 설치하세요.", x: 48, top: 121, size: 14,
  weight: .regular, color: secondary)
let iconURL = URL(fileURLWithPath: CommandLine.arguments[2])
  .appendingPathComponent("Contents/Resources/CompanionPets-v1.icns")
guard let icon = NSImage(contentsOf: iconURL) else { fatalError("Missing installer app icon") }
icon.draw(in: NSRect(x: 606, y: 354, width: 66, height: 66))
NSColor(red: 0.88, green: 0.91, blue: 0.87, alpha: 1).setFill()
for x: CGFloat in [105, 455] {
  NSBezierPath(roundedRect: NSRect(x: x, y: 112, width: 160, height: 178),
    xRadius: 20, yRadius: 20).fill()
}
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 314, y: 208))
arrow.line(to: NSPoint(x: 406, y: 208))
arrow.move(to: NSPoint(x: 391, y: 223))
arrow.line(to: NSPoint(x: 406, y: 208))
arrow.line(to: NSPoint(x: 391, y: 193))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
ink.setStroke()
arrow.stroke()
text("Drag to install", x: 275, top: 278, size: 12, weight: .medium, color: secondary,
  width: 170, centered: true)
text("설치 후 메뉴 막대의 발바닥 아이콘에서 만나요.", x: 40, top: 375,
  size: 14, weight: .medium, color: ink, width: 640, centered: true)
text("Your pets, sounds and settings stay with you when you update.", x: 40, top: 405,
  size: 11, weight: .regular, color: secondary, width: 640, centered: true)
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
assert(bitmap.pixelsWide == 1440 && bitmap.pixelsHigh == 920)
