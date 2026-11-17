import AVFoundation
import AppKit
import MultiCodexPetsCore

final class PetSpriteView: NSView {
  private let image: CGImage?
  private var frameImages: [Int: NSImage] = [:]
  private var clickSound: AVAudioPlayer?
  var soundVolume: Float = 1 { didSet { clickSound?.volume = soundVolume } }
  var isMuted = false { didSet { if isMuted { clickSound?.stop() } } }
  var isInteractive = true
  var positionLocked = false
  var onDragEnded: ((NSRect) -> Void)?
  var contextMenuProvider: (() -> NSMenu?)?
  private var movedDuringPress = false
  private var frames: [AnimationFrame] = []
  private var frameIndex = 0
  private var frameTimer: Timer?
  private var pointerTimer: Timer?
  private(set) var lookFrame: AnimationFrame?
  private var shakeTracker = CursorShakeTracker()
  private var reduceMotionObserver: NSObjectProtocol?
  private var trackingAreaRef: NSTrackingArea?
  private var dragStartMouseLocation: NSPoint?
  private var dragDirection: DragDirectionTracker?
  private var dragStartWindowOrigin: NSPoint?
  private var transientState: AnimationState?
  private var randomizesNextAnimationStart = false

  let pet: PetPackage
  private(set) var isDragging = false
  var cursorTrackingMode = PetCursorTrackingMode.always {
    didSet {
      guard cursorTrackingMode != oldValue else { return }
      shakeTracker = CursorShakeTracker()
      updatePointerTracking()
    }
  }

  var animationState: AnimationState {
    didSet {
      guard animationState != oldValue else { return }
      guard transientState == nil else { return }
      restartAnimation(
        for: animationState,
        randomizeInitialFrame: randomizesNextAnimationStart
      )
      randomizesNextAnimationStart = false
    }
  }

  init(pet: PetPackage, animationState: AnimationState) {
    self.pet = pet
    self.animationState = animationState
    self.image = PetImageDecoder.image(for: pet)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      self.restartAnimation(for: self.transientState ?? self.animationState)
      self.updatePointerTracking()
    }
    restartAnimation(for: animationState)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  deinit {
    if let reduceMotionObserver { NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver) }
    frameTimer?.invalidate()
    pointerTimer?.invalidate()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    isInteractive ? super.hitTest(point) : nil
  }

  override var acceptsFirstResponder: Bool {
    true
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updatePointerTracking()
  }

  private func updatePointerTracking() {
    pointerTimer?.invalidate()
    pointerTimer = nil
    updateLookFrame()
    guard cursorTrackingMode != .off, pet.spriteVersion == .v2, window != nil,
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      self?.updateLookFrame()
    }
    RunLoop.main.add(timer, forMode: .common)
    pointerTimer = timer
  }

  func updateLookFrame(pointer: CGPoint = NSEvent.mouseLocation,
    now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    let nextFrame: AnimationFrame?
    if cursorTrackingMode != .off, pet.spriteVersion == .v2, animationState.allowsCursorTracking,
      transientState == nil, !isDragging,
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      let window, window.isVisible
    {
      let shouldLook = cursorTrackingMode == .always
        || shakeTracker.update(point: pointer, now: now)
      let center = window.convertPoint(
        toScreen: convert(
          NSPoint(x: bounds.midX, y: bounds.midY), to: nil
        ))
      nextFrame = shouldLook ? pet.spriteVersion.lookFrame(
        pointer: pointer,
        center: center,
        deadzone: min(bounds.width, bounds.height) * 0.25
      ) : nil
    } else {
      shakeTracker = CursorShakeTracker()
      nextFrame = nil
    }
    guard lookFrame != nextFrame else { return }
    lookFrame = nextFrame
    needsDisplay = true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let trackingAreaRef {
      removeTrackingArea(trackingAreaRef)
    }

    guard isInteractive else { return }
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
      owner: self
    )
    addTrackingArea(trackingArea)
    trackingAreaRef = trackingArea
  }

  override func mouseEntered(with event: NSEvent) {
    guard isInteractive, pet.spriteVersion == .v1, transientState == nil else { return }
    setTransientState(.jumping)
  }

  override func mouseExited(with event: NSEvent) {
    if transientState == .jumping {
      setTransientState(nil)
    }
  }

  override func mouseDown(with event: NSEvent) {
    movedDuringPress = false
    isDragging = true
    updateLookFrame()
    let location = NSEvent.mouseLocation
    dragStartMouseLocation = location
    dragDirection = DragDirectionTracker(startX: location.x)
    dragStartWindowOrigin = window?.frame.origin
  }

  override func menu(for event: NSEvent) -> NSMenu? { contextMenuProvider?() }

  override func mouseDragged(with event: NSEvent) {
    guard let dragStartMouseLocation else { return }
    let currentLocation = NSEvent.mouseLocation
    let deltaX = currentLocation.x - dragStartMouseLocation.x
    let deltaY = currentLocation.y - dragStartMouseLocation.y
    if hypot(deltaX, deltaY) > 4 { movedDuringPress = true }
    guard !positionLocked, let window, let dragStartWindowOrigin else { return }
    window.setFrameOrigin(
      NSPoint(
        x: dragStartWindowOrigin.x + deltaX,
        y: dragStartWindowOrigin.y + deltaY
      ))

    if let state = dragDirection?.update(x: currentLocation.x) {
      setTransientState(state)
    }
  }

  override func mouseUp(with event: NSEvent) {
    if isDragging, !movedDuringPress,
      bounds.contains(convert(event.locationInWindow, from: nil))
    {
      playClickSound()
    }
    if movedDuringPress, let frame = window?.frame { onDragEnded?(frame) }
    isDragging = false
    dragStartMouseLocation = nil
    dragDirection = nil
    dragStartWindowOrigin = nil
    setTransientState(nil)
    updateLookFrame()
  }

  private func playClickSound() {
    guard !isMuted else { return }
    clickSound?.stop()
    clickSound = nil
    for url in PetSoundLibrary().soundURLs(forPetID: pet.id, role: .click).shuffled() {
      do {
        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = soundVolume
        if player.play() {
          clickSound = player
          return
        }
      } catch {
        NSLog("Could not play pet sound %@: %@", url.path, error.localizedDescription)
      }
    }
  }

  func setAnimationState(_ state: AnimationState, randomizeInitialFrame: Bool = false) {
    guard animationState != state else {
      if randomizeInitialFrame, transientState == nil {
        restartAnimation(for: state, randomizeInitialFrame: true)
      }
      return
    }

    randomizesNextAnimationStart = randomizeInitialFrame
    animationState = state
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let image,
      !frames.isEmpty
    else {
      return
    }

    let frame = lookFrame ?? frames[min(frameIndex, frames.count - 1)]
    let key = frame.rowIndex * PetAtlas.columns + frame.columnIndex
    let cell: NSImage
    if let cached = frameImages[key] {
      cell = cached
    } else {
      guard let cropped = PetImageDecoder.cell(in: image, frame: frame) else { return }
      cell = NSImage(cgImage: cropped, size: NSSize(width: PetAtlas.cellWidth, height: PetAtlas.cellHeight))
      frameImages[key] = cell
    }

    NSGraphicsContext.current?.imageInterpolation = .high
    cell.draw(
      in: bounds,
      from: NSRect(origin: .zero, size: cell.size),
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: false,
      hints: nil
    )
  }

  private func setTransientState(_ state: AnimationState?) {
    guard transientState != state else { return }
    let reversesRunning =
      (transientState == .runningLeft && state == .runningRight)
      || (transientState == .runningRight && state == .runningLeft)
    transientState = state
    if reversesRunning, let state {
      // Both running rows share timing; retain the current frame and its scheduled tick.
      frames = AnimationTimeline.frames(
        for: state,
        reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
      frameIndex = min(frameIndex, frames.count - 1)
      needsDisplay = true
    } else {
      restartAnimation(for: state ?? animationState)
    }
  }

  private func restartAnimation(for state: AnimationState, randomizeInitialFrame: Bool = false) {
    frameTimer?.invalidate()
    updateLookFrame()
    frames = AnimationTimeline.frames(
      for: state,
      reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    )
    frameIndex = randomizeInitialFrame && frames.count > 1 ? Int.random(in: frames.indices) : 0
    needsDisplay = true
    scheduleNextFrame()
  }

  private func scheduleNextFrame() {
    guard frames.count > 1 else { return }

    let duration = TimeInterval(frames[frameIndex].frameDurationMs) / 1000
    let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
      self?.advanceFrame()
    }
    RunLoop.main.add(timer, forMode: .common)
    frameTimer = timer
  }

  private func advanceFrame() {
    guard !frames.isEmpty else { return }

    frameIndex = (frameIndex + 1) % frames.count
    needsDisplay = true
    scheduleNextFrame()
  }
}
