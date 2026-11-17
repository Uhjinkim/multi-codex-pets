import AppKit
import ImageIO
import MultiCodexPetsCore
import UniformTypeIdentifiers
import XCTest
@testable import MultiCodexPets

final class PetWindowTests: XCTestCase {
  func testV2LooksDuringIdleWaitingAndCompletionAndRestoresAfterActiveStates() throws {
    _ = NSApplication.shared
    try XCTSkipIf(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "System Reduce Motion takes priority")
    let pet = PetPackage(id: "gaze-test", folderName: "gaze-test", displayName: "Test", description: nil,
      spritesheetURL: URL(fileURLWithPath: "/missing"), packageDirectory: URL(fileURLWithPath: "/tmp"),
      spriteVersion: .v2)
    let controller = PetWindowController(pet: pet,
      initialFrame: NSRect(x: 100, y: 100, width: 80, height: 87), animationState: .idle, scale: 1)
    defer { controller.close() }
    controller.show()
    let view = try XCTUnwrap(controller.window?.contentView as? PetSpriteView)
    for state in AnimationState.allCases {
      view.setAnimationState(state)
      view.updateLookFrame(pointer: CGPoint(x: 600, y: 600), now: 0)
      XCTAssertEqual(view.lookFrame != nil, [.idle, .waiting, .waving].contains(state), "\(state)")
    }
    view.setAnimationState(.waiting)
    view.cursorTrackingMode = .off
    view.updateLookFrame(pointer: CGPoint(x: 600, y: 600), now: 0)
    XCTAssertNil(view.lookFrame)
    view.cursorTrackingMode = .whenShaken
    for (index, x) in [600.0, 660, 600, 660, 600].enumerated() {
      view.updateLookFrame(pointer: CGPoint(x: x, y: 600), now: Double(index) * 0.1)
      XCTAssertEqual(view.lookFrame != nil, index == 4)
    }
    view.setAnimationState(.running)
    view.updateLookFrame(pointer: CGPoint(x: 600, y: 600), now: 0.5)
    XCTAssertNil(view.lookFrame)
    view.setAnimationState(.waiting)
    view.updateLookFrame(pointer: CGPoint(x: 600, y: 600), now: 0.6)
    XCTAssertNil(view.lookFrame, "Active animation clears the temporary shake reaction")
    view.cursorTrackingMode = .always
    view.updateLookFrame(pointer: CGPoint(x: 600, y: 600), now: 0.7)
    XCTAssertNotNil(view.lookFrame)
  }

  func testRefreshReloadsReplacedImageAndPreservesPosition() throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("sheet.png")
    let pet = PetPackage(id: "refresh-test", folderName: "refresh-test", displayName: "Test",
      description: nil, spritesheetURL: file, packageDirectory: directory)
    let coordinator = PetCoordinator()
    defer { coordinator.hidePets() }
    coordinator.setFollowsCursor(false)
    try writeSheet(.red, to: file)
    coordinator.showPets([pet], state: .idle, scale: 1)
    let first = try window(for: pet)
    let frame = first.frame
    XCTAssertGreaterThan(try color(in: first).redComponent, 0.9)
    try writeSheet(.blue, to: file)
    // Refresh closes cached views before showing the reloaded packages.
    coordinator.hidePets()
    coordinator.showPets([pet], state: .idle, scale: 1)
    let next = try window(for: pet)
    XCTAssertFalse(first === next)
    XCTAssertEqual(next.frame, frame)
    XCTAssertGreaterThan(try color(in: next).blueComponent, 0.9)
  }

  func testUnchangedLabelReusesContentAndChangedStyleStillUpdates() throws {
    _ = NSApplication.shared
    let pet = PetPackage(id: "label-test", folderName: "label-test", displayName: "Test",
      description: nil, spritesheetURL: URL(fileURLWithPath: "/missing"),
      packageDirectory: URL(fileURLWithPath: "/tmp"))
    let controller = PetWindowController(pet: pet,
      initialFrame: NSRect(x: 100, y: 100, width: 80, height: 87), animationState: .idle, scale: 1)
    defer { controller.close() }
    var style = PetNameLabel()
    style.position = .above
    controller.setNameLabel("Test", style: style)
    controller.show()
    let label = try XCTUnwrap(controller.window?.childWindows?.first)
    let content = try XCTUnwrap(label.contentView)
    controller.setNameLabel("Test", style: style)
    XCTAssertTrue(label.contentView === content)
    style.fontSize = 20
    controller.setNameLabel("Test", style: style)
    XCTAssertFalse(label.contentView === content)
  }

  private func window(for pet: PetPackage) throws -> NSWindow {
    try XCTUnwrap(NSApp.windows.first { ($0.contentView as? PetSpriteView)?.pet.id == pet.id && $0.isVisible })
  }

  func testPerPetCursorAndVolumeOverridesSurviveGlobalChangesAndReopening() throws {
    _ = NSApplication.shared
    let coordinator = PetCoordinator()
    defer { coordinator.hidePets() }
    let pets = ["cat", "dog", "default"].map { id in
      PetPackage(id: id, folderName: id, displayName: id, description: nil,
        spritesheetURL: URL(fileURLWithPath: "/missing"), packageDirectory: URL(fileURLWithPath: "/tmp"),
        spriteVersion: .v2)
    }
    var cat = PetPreferences()
    cat.cursorTrackingMode = .whenShaken
    cat.soundVolume = 0.5
    var dog = PetPreferences()
    dog.cursorTrackingMode = .always
    let preferences = ["cat": cat, "dog": dog]
    coordinator.configure(preferences: preferences, clickVolume: 0.8)
    coordinator.showPets(pets, state: .idle, scale: 1)
    let catView = try XCTUnwrap(try window(for: pets[0]).contentView as? PetSpriteView)
    let dogView = try XCTUnwrap(try window(for: pets[1]).contentView as? PetSpriteView)
    XCTAssertEqual(catView.cursorTrackingMode, .whenShaken)
    XCTAssertEqual(catView.soundVolume, 0.4, accuracy: 0.001)
    XCTAssertEqual(dogView.soundVolume, 0.8, accuracy: 0.001)
    coordinator.setFollowsCursor(false)
    XCTAssertEqual(catView.cursorTrackingMode, .whenShaken)
    XCTAssertEqual(dogView.cursorTrackingMode, .always)
    coordinator.configure(preferences: preferences, clickVolume: 0.8, muted: true)
    XCTAssertTrue(catView.isMuted)
    XCTAssertTrue(dogView.isMuted)
    coordinator.hidePets()
    coordinator.showPets(pets, state: .idle, scale: 1)
    let restored = try XCTUnwrap(try window(for: pets[0]).contentView as? PetSpriteView)
    XCTAssertEqual(restored.cursorTrackingMode, .whenShaken)
    XCTAssertEqual(restored.soundVolume, 0.4, accuracy: 0.001)
    XCTAssertTrue(restored.isMuted)
    XCTAssertEqual((try window(for: pets[2]).contentView as? PetSpriteView)?.cursorTrackingMode, .off)
  }

  private func color(in window: NSWindow) throws -> NSColor {
    let view = try XCTUnwrap(window.contentView)
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
  }

  private func writeSheet(_ color: NSColor, to url: URL) throws {
    let context = try XCTUnwrap(CGContext(data: nil, width: PetAtlas.width, height: PetAtlas.height,
      bitsPerComponent: 8, bytesPerRow: PetAtlas.width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: PetAtlas.width, height: PetAtlas.height))
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }
}
