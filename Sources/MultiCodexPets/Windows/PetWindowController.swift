import AppKit
import MultiCodexPetsCore

final class PetWindowController: NSWindowController, NSWindowDelegate {
  private var nameLabelWindow: NSWindow?
  private var nameLabel = PetNameLabel()
  private var petName = ""
  private let petView: PetSpriteView
  var onFrameChanged: ((NSRect) -> Void)?
  var isPositionLocked: Bool { petView.positionLocked }

  var pet: PetPackage {
    petView.pet
  }

  var currentFrame: NSRect? {
    window?.frame
  }

  var isUserDragging: Bool {
    petView.isDragging
  }

  init(
    pet: PetPackage,
    initialFrame: NSRect,
    animationState: AnimationState,
    scale: Double
  ) {
    self.petView = PetSpriteView(pet: pet, animationState: animationState)

    let window = NSWindow(
      contentRect: initialFrame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.isReleasedWhenClosed = false
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.acceptsMouseMovedEvents = true
    window.contentView = petView

    super.init(window: window)
    window.delegate = self
    petView.onDragEnded = { [weak self] in self?.onFrameChanged?($0) }
    setScale(scale)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  static func windowSize(scale: Double) -> NSSize {
    let baseWidth: CGFloat = 80
    let baseHeight = baseWidth * CGFloat(PetAtlas.cellHeight) / CGFloat(PetAtlas.cellWidth)
    return NSSize(width: baseWidth * scale, height: baseHeight * scale)
  }

  func show() {
    window?.orderFrontRegardless()
    updateNameLabel()
  }

  func setAnimationState(_ state: AnimationState, randomizeInitialFrame: Bool = false) {
    petView.setAnimationState(state, randomizeInitialFrame: randomizeInitialFrame)
  }

  func setInteraction(volume: Float, muted: Bool, locked: Bool) {
    petView.soundVolume = volume
    petView.isMuted = muted
    petView.positionLocked = locked
  }

  func setSessionTooltip(_ text: String) { petView.toolTip = text }
  func setContextMenuProvider(_ provider: @escaping () -> NSMenu?) {
    petView.contextMenuProvider = provider
  }

  func setCursorTrackingMode(_ mode: PetCursorTrackingMode) {
    petView.cursorTrackingMode = mode
  }

  func setScale(_ scale: Double) {
    guard let window else { return }

    let oldFrame = window.frame
    let newSize = Self.windowSize(scale: scale)
    let newFrame = NSRect(origin: oldFrame.origin, size: newSize)
    window.setFrame(newFrame, display: true)
    petView.frame = NSRect(origin: .zero, size: newSize)
    updateNameLabel()
  }

  func setNameLabel(_ name: String, style: PetNameLabel) {
    guard petName != name || nameLabel != style else { return }
    petName = name
    nameLabel = style
    updateNameLabel()
  }

  func windowDidMove(_ notification: Notification) { positionNameLabel() }

  private func positionNameLabel() {
    guard let window, let label = nameLabelWindow, label.parent != nil else { return }
    let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
    label.setFrame(nameLabel.frame(pet: window.frame, size: label.frame.size, screen: screen), display: true)
  }

  private func updateNameLabel() {
    guard let window else { return }
    guard nameLabel.position != .hidden, window.isVisible else {
      if let label = nameLabelWindow {
        window.removeChildWindow(label)
        label.orderOut(nil)
      }
      return
    }
    let labelWindow: NSWindow
    if let existing = nameLabelWindow {
      labelWindow = existing
    } else {
      labelWindow = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
      labelWindow.isReleasedWhenClosed = false
      labelWindow.isOpaque = false
      labelWindow.backgroundColor = .clear
      labelWindow.hasShadow = false
      labelWindow.ignoresMouseEvents = true
      labelWindow.collectionBehavior = window.collectionBehavior
      nameLabelWindow = labelWindow
    }
    let text = NSTextField(labelWithString: petName)
    text.font = .systemFont(ofSize: nameLabel.resolvedFontSize, weight: .medium)
    text.textColor = nameLabel.color
    text.lineBreakMode = .byTruncatingTail
    text.alignment = .center
    let size = NSSize(width: min(280, max(36, text.fittingSize.width + 16)),
      height: text.fittingSize.height + 8)
    let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
    let frame = nameLabel.frame(pet: window.frame, size: size, screen: screen)
    labelWindow.setFrame(frame, display: true)
    let content = NSView(frame: NSRect(origin: .zero, size: size))
    content.wantsLayer = true
    content.layer?.backgroundColor = nameLabel.backgroundColor.cgColor
    content.layer?.cornerRadius = 6
    text.frame = NSRect(x: 8, y: 4, width: size.width - 16, height: size.height - 8)
    content.addSubview(text)
    labelWindow.contentView = content
    if labelWindow.parent == nil { window.addChildWindow(labelWindow, ordered: .above) }
  }

  override func close() {
    if let label = nameLabelWindow {
      window?.removeChildWindow(label)
      label.close()
      nameLabelWindow = nil
    }
    super.close()
  }

  func setFrameOrigin(_ origin: NSPoint) {
    window?.setFrameOrigin(origin)
  }
}
