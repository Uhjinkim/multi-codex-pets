import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import MultiCodexPetsCore

final class PetImageDecoderTests: XCTestCase {
  func testDecodedSheetAndThumbnailHaveOwnedPixelsAndCorrectOrientation() throws {
    let data = try sheet()
    let pet = package(data: data)
    let decoded = try XCTUnwrap(PetImageDecoder.image(for: pet))
    XCTAssertEqual(decoded.width, PetAtlas.width)
    XCTAssertEqual(decoded.height, PetAtlas.height)
    XCTAssertEqual(CFDataGetLength(try XCTUnwrap(decoded.dataProvider?.data)),
      decoded.bytesPerRow * decoded.height)
    let top = try XCTUnwrap(PetImageDecoder.image(for: pet,
      frame: .init(rowIndex: 0, columnIndex: 0, frameDurationMs: 0)))
    XCTAssertEqual(top.width, PetAtlas.cellWidth)
    XCTAssertEqual(top.height, PetAtlas.cellHeight)
    let topPixels = try XCTUnwrap(top.dataProvider?.data) as Data
    XCTAssertEqual(topPixels.count, PetAtlas.cellWidth * PetAtlas.cellHeight * 4)
    XCTAssertEqual(Array(topPixels.prefix(4)), [255, 0, 0, 255])
    let bottom = try XCTUnwrap(PetImageDecoder.image(for: pet,
      frame: .init(rowIndex: 8, columnIndex: 0, frameDurationMs: 0)))
    XCTAssertEqual(Array((try XCTUnwrap(bottom.dataProvider?.data) as Data).prefix(4)), [0, 0, 255, 255])
  }

  func testLoadsFilesAndRejectsInvalidSheetsAndFrames() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: file) }
    let data = try sheet()
    try data.write(to: file)
    XCTAssertNotNil(PetImageDecoder.image(for: package(data: nil, url: file)))
    XCTAssertNil(PetImageDecoder.image(for: package(data: Data("bad".utf8))))
    XCTAssertNil(PetImageDecoder.image(for: package(data: data, version: .v2)))
    for (row, column) in [(-1, 0), (9, 0), (0, -1), (0, 8)] {
      XCTAssertNil(PetImageDecoder.image(for: package(data: data),
        frame: .init(rowIndex: row, columnIndex: column, frameDurationMs: 0)))
    }
  }

  private func sheet() throws -> Data {
    let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try XCTUnwrap(CGContext(data: nil, width: PetAtlas.width, height: PetAtlas.height,
      bitsPerComponent: 8, bytesPerRow: PetAtlas.width * 4,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(colorSpace: colorSpace, components: [0, 0, 1, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: PetAtlas.width, height: PetAtlas.height))
    context.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 0, 0, 1])!)
    context.fill(CGRect(x: 0, y: PetAtlas.height - PetAtlas.cellHeight,
      width: PetAtlas.cellWidth, height: PetAtlas.cellHeight))
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data,
      UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func package(data: Data?, url: URL = URL(fileURLWithPath: "/missing"),
    version: PetSpriteVersion = .v1) -> PetPackage {
    PetPackage(id: "test", folderName: "test", displayName: "Test", description: nil,
      spritesheetURL: url, spritesheetData: data, packageDirectory: url.deletingLastPathComponent(),
      spriteVersion: version)
  }
}
